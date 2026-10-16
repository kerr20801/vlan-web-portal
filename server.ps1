# PowerShell Web Server for VMware VLAN Switcher & Batch Deployer
# Author: Kerr (https://github.com/kerr20801)
# Pure ASCII encoding - 100% compatible with all Windows code pages

$Port = 8899
$Prefix = "http://localhost:$Port/"
$HtmlPath = Join-Path $PSScriptRoot "index.html"
$BackendScript = Join-Path $PSScriptRoot "vlan_assign_backend.ps1"

# 1. Load portable modules if present
$localModules = Join-Path $PSScriptRoot "Modules"
if (Test-Path $localModules) {
    $env:PSModulePath = "$localModules;$env:PSModulePath"
}
Import-Module VMware.VimAutomation.Core -ErrorAction SilentlyContinue

# 2. Suppress certificate & CEIP prompts
if (Get-Command Set-PowerCLIConfiguration -ErrorAction SilentlyContinue) {
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -ParticipateInCEIP $false -Confirm:$false -Scope Session -ErrorAction SilentlyContinue | Out-Null
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($Prefix)

try {
    $listener.Start()
} catch {
    Write-Host "Failed to start listener on port $Port : $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " VMware VLAN Automation Portal is RUNNING!" -ForegroundColor Green
Write-Host " URL: $Prefix" -ForegroundColor Yellow
if (Get-Command Connect-VIServer -ErrorAction SilentlyContinue) {
    Write-Host " Status: PowerCLI module loaded successfully!" -ForegroundColor Green
} else {
    Write-Host " [WARNING] PowerCLI module NOT detected!" -ForegroundColor Yellow
    Write-Host " Please run 'setup_modules.bat' to download required modules." -ForegroundColor Yellow
}
Write-Host " Press Ctrl + C to stop the service." -ForegroundColor Gray
Write-Host "==========================================================" -ForegroundColor Cyan

# Auto open default browser
Start-Process $Prefix

$global:ActiveVIServer = $null
$global:CachedCred = $null
$global:LastDeployResult = $null

function Send-JsonResponse($response, $data, [int]$statusCode = 200) {
    $json = $data | ConvertTo-Json -Depth 6 -Compress
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
    $response.StatusCode = $statusCode
    $response.ContentType = "application/json; charset=utf-8"
    $response.ContentLength64 = $buffer.Length
    $response.OutputStream.Write($buffer, 0, $buffer.Length)
    $response.OutputStream.Close()
}

function Send-HtmlResponse($response, $filePath) {
    if (Test-Path $filePath) {
        $buffer = [System.IO.File]::ReadAllBytes($filePath)
        $response.StatusCode = 200
        $response.ContentType = "text/html; charset=utf-8"
        $response.ContentLength64 = $buffer.Length
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
    } else {
        $response.StatusCode = 404
    }
    $response.OutputStream.Close()
}

while ($listener.IsListening) {
    $context = $listener.GetContext()
    $request = $context.Request
    $response = $context.Response

    # Restrict CORS to localhost only for security
    $origin = $request.Headers["Origin"]
    if ($origin -and ($origin -like "http://localhost:*" -or $origin -like "http://127.0.0.1:*")) {
        $response.AddHeader("Access-Control-Allow-Origin", $origin)
    } else {
        $response.AddHeader("Access-Control-Allow-Origin", "http://localhost:$Port")
    }
    $response.AddHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    $response.AddHeader("Access-Control-Allow-Headers", "Content-Type")

    if ($request.HttpMethod -eq "OPTIONS") {
        $response.StatusCode = 200
        $response.OutputStream.Close()
        continue
    }

    $rawUrl = $request.RawUrl

    # 1. Serve index.html
    if ($rawUrl -eq "/" -or $rawUrl -eq "/index.html") {
        Send-HtmlResponse $response $HtmlPath
        continue
    }

    # 2. API: Connect and load inventory
    if ($rawUrl -eq "/api/connect" -and $request.HttpMethod -eq "POST") {
        $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
        $body = $reader.ReadToEnd() | ConvertFrom-Json

        try {
            if (-not (Get-Command Connect-VIServer -ErrorAction SilentlyContinue)) {
                Import-Module VMware.VimAutomation.Core -ErrorAction SilentlyContinue
            }

            if (-not (Get-Command Connect-VIServer -ErrorAction SilentlyContinue)) {
                Send-JsonResponse $response @{
                    success = $false
                    message = "VMware PowerCLI module not detected! Please run setup_modules.bat to download portable modules or install PowerCLI."
                }
                continue
            }

            $targetServer = $body.server.Trim() -replace '^https?://', '' -replace '/.*$', ''
            $targetUser   = ("" + $body.username).Trim()

            if ($global:ActiveVIServer) {
                Disconnect-VIServer -Server $global:ActiveVIServer -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            }

            Write-Host "Connecting to target host [$targetServer] with user [$targetUser]..." -ForegroundColor Cyan
            $secPass = ConvertTo-SecureString $body.password -AsPlainText -Force
            $cred = New-Object System.Management.Automation.PSCredential($targetUser, $secPass)

            $conn = Connect-VIServer -Server $targetServer -Credential $cred -ErrorAction Stop

            $global:ActiveVIServer = $conn
            $global:CachedCred = @{
                Server   = $targetServer
                Username = $targetUser
                Password = $body.password
            }

            Write-Host "Querying ESXi hosts inventory..." -ForegroundColor Gray
            $hosts = Get-VMHost -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name | Sort-Object

            Write-Host "Querying VM inventory..." -ForegroundColor Gray
            $vms = Get-VM -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name | Sort-Object

            Write-Host "Querying Datastores inventory..." -ForegroundColor Gray
            $datastores = Get-Datastore -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name | Sort-Object

            Write-Host "Querying vSwitch and PortGroup topology..." -ForegroundColor Gray
            $networkMap = [ordered]@{}
            $vswitches = Get-VirtualSwitch -ErrorAction SilentlyContinue
            foreach ($vsw in $vswitches) {
                $pgs = Get-VirtualPortGroup -VirtualSwitch $vsw -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name | Sort-Object
                $networkMap[$vsw.Name] = @($pgs)
            }

            Send-JsonResponse $response @{
                success    = $true
                serverType = if ($conn.ProductLine -eq "esx") { "ESXi" } else { "vCenter" }
                hosts      = @($hosts)
                vms        = @($vms)
                datastores = @($datastores)
                networkMap = $networkMap
            }
            Write-Host "Connected and inventory loaded successfully!" -ForegroundColor Green
        } catch {
            Write-Host "Connection failed: $($_.Exception.Message)" -ForegroundColor Red
            Send-JsonResponse $response @{
                success = $false
                message = $_.Exception.Message
            }
        }
        continue
    }

    # 2.2 API: Disconnect from server
    if ($rawUrl -eq "/api/disconnect" -and $request.HttpMethod -eq "POST") {
        try {
            if ($global:ActiveVIServer) {
                Write-Host "Disconnecting active session..." -ForegroundColor Cyan
                Disconnect-VIServer -Server $global:ActiveVIServer -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            }
            $global:ActiveVIServer = $null
            $global:CachedCred = $null
            Send-JsonResponse $response @{
                success = $true
                message = "Disconnected successfully."
            }
            Write-Host "Session disconnected." -ForegroundColor Green
        } catch {
            Send-JsonResponse $response @{
                success = $false
                message = $_.Exception.Message
            }
        }
        continue
    }

    # 2.3 API: Query host existing network state (for live diff comparison)
    if ($rawUrl.StartsWith("/api/host-network-state") -and ($request.HttpMethod -eq "GET" -or $request.HttpMethod -eq "POST")) {
        if (-not $global:ActiveVIServer) {
            Send-JsonResponse $response @{
                success = $false
                message = "Not connected to any vCenter/ESXi yet. Please connect first."
            }
            continue
        }

        try {
            $targetHostName = ""
            if ($request.HttpMethod -eq "POST") {
                $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
                $body = $reader.ReadToEnd() | ConvertFrom-Json
                $targetHostName = ("" + $body.host).Trim()
            } else {
                if ($request.Url.Query) {
                    $queryString = $request.Url.Query.TrimStart('?')
                    foreach ($pair in $queryString.Split('&')) {
                        $kv = $pair.Split('=', 2)
                        if ($kv[0] -eq "host" -and $kv.Count -gt 1) {
                            $targetHostName = [System.Uri]::UnescapeDataString($kv[1])
                        }
                    }
                }
            }

            $hostsToQuery = @()
            if (-not $targetHostName -or $targetHostName -eq "_ALL_") {
                $hostsToQuery = Get-VMHost -ErrorAction SilentlyContinue
            } else {
                $hostsToQuery = Get-VMHost -Name $targetHostName -ErrorAction SilentlyContinue
            }

            $portGroupList = @()
            foreach ($h in $hostsToQuery) {
                $pgs = Get-VirtualPortGroup -VMHost $h -ErrorAction SilentlyContinue
                foreach ($pg in $pgs) {
                    $vswName = if ($pg.VirtualSwitchName) { $pg.VirtualSwitchName } elseif ($pg.VirtualSwitch) { $pg.VirtualSwitch.Name } else { "" }
                    if ($vswName) {
                        $portGroupList += [PSCustomObject]@{
                            host    = $h.Name
                            vswitch = $vswName
                            name    = $pg.Name
                            vlanId  = [int]$pg.VLanId
                        }
                    }
                }
            }

            Send-JsonResponse $response @{
                success    = $true
                host       = $targetHostName
                portGroups = $portGroupList
            }
        } catch {
            Send-JsonResponse $response @{
                success = $false
                message = $_.Exception.Message
            }
        }
        continue
    }

    # 2.4 API: Get last deploy result
    if ($rawUrl -eq "/api/last-deploy" -and $request.HttpMethod -eq "GET") {
        if ($global:LastDeployResult) {
            Send-JsonResponse $response @{
                success = $true
                hasData = $true
                data    = $global:LastDeployResult
            }
        } else {
            Send-JsonResponse $response @{
                success = $true
                hasData = $false
            }
        }
        continue
    }

    # 2.5 API: Extract/Clone Network Configuration from an Existing Host
    if ($rawUrl -eq "/api/clone-host-network" -and $request.HttpMethod -eq "POST") {
        $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
        $body = $reader.ReadToEnd() | ConvertFrom-Json

        if (-not $global:ActiveVIServer) {
            Send-JsonResponse $response @{
                success = $false
                message = "Not connected to any vCenter/ESXi yet. Please connect first."
            }
            continue
        }

        try {
            $srcHostName = ("" + $body.sourceHost).Trim()
            Write-Host "Extracting network configuration from source host [$srcHostName]..." -ForegroundColor Cyan

            $hostObj = Get-VMHost -Name $srcHostName -ErrorAction SilentlyContinue
            if (-not $hostObj) {
                Send-JsonResponse $response @{
                    success = $false
                    message = "Source host '$srcHostName' not found."
                }
                continue
            }

            $pgs = Get-VirtualPortGroup -VMHost $hostObj -ErrorAction SilentlyContinue
            $items = @()
            $textLines = @()

            foreach ($pg in $pgs) {
                $vswName = if ($pg.VirtualSwitchName) { $pg.VirtualSwitchName } elseif ($pg.VirtualSwitch) { $pg.VirtualSwitch.Name } else { "" }
                if (-not $vswName) { continue }

                $pgName = $pg.Name
                $vlanId = [int]$pg.VLanId

                # Skip default VM / Management networks if requested
                if ($body.skipDefaultVmNetwork -and ($pgName -eq "VM Network" -or $pgName -eq "Management Network")) {
                    continue
                }

                $items += [PSCustomObject]@{
                    vswitch = $vswName
                    name    = $pgName
                    vlanId  = $vlanId
                }
                $textLines += "$vswName, $pgName, $vlanId"
            }

            Write-Host "Extracted $($items.Count) PortGroups from [$srcHostName]." -ForegroundColor Green
            Send-JsonResponse $response @{
                success    = $true
                sourceHost = $srcHostName
                count      = $items.Count
                items      = $items
                text       = ($textLines -join [Environment]::NewLine)
            }
        } catch {
            Write-Host "Extract host network error: $($_.Exception.Message)" -ForegroundColor Red
            Send-JsonResponse $response @{
                success = $false
                message = $_.Exception.Message
            }
        }
        continue
    }

    # 3. API: Batch Deploy VLANs (PortGroups) to ESXi Host
    if ($rawUrl -eq "/api/deploy-batch" -and $request.HttpMethod -eq "POST") {
        $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
        $body = $reader.ReadToEnd() | ConvertFrom-Json

        if (-not $global:ActiveVIServer) {
            Send-JsonResponse $response @{
                success = $false
                message = "Not connected to any vCenter/ESXi. Please connect first."
            }
            continue
        }

        Write-Host "Received batch deploy request for $($body.items.Count) VLANs on target: $($body.targetHost)" -ForegroundColor Yellow

        try {
            $targetHosts = @()
            if ($body.targetHost -eq "_ALL_") {
                $targetHosts = Get-VMHost -ErrorAction SilentlyContinue
            } else {
                $targetHosts = Get-VMHost -Name $body.targetHost -ErrorAction SilentlyContinue
            }

            if (-not $targetHosts -or $targetHosts.Count -eq 0) {
                Send-JsonResponse $response @{
                    success = $false
                    message = "Target host '$($body.targetHost)' not found on server."
                }
                continue
            }

            $results = @()
            foreach ($h in $targetHosts) {
                Write-Host "Processing host: $($h.Name)..." -ForegroundColor Cyan
                foreach ($item in $body.items) {
                    $vswName = ("" + $item.vswitch).Trim()
                    $pgName  = ("" + $item.name).Trim()
                    $vlanId  = [int]$item.vlanId

                    if (-not $vswName -or -not $pgName) {
                        continue
                    }

                    # Validate 802.1Q VLAN range (0 to 4095; 4095 is Trunk/VGT)
                    if ($vlanId -lt 0 -or $vlanId -gt 4095) {
                        $results += [PSCustomObject]@{
                            host    = $h.Name
                            vswitch = $vswName
                            name    = $pgName
                            vlanId  = $vlanId
                            status  = "error"
                            message = "VLAN ID $vlanId 超出有效範圍 (合法為 0 ~ 4095)"
                        }
                        continue
                    }

                    try {
                        # 1. Check or auto-create vSwitch
                        $vsw = Get-VirtualSwitch -VMHost $h -Name $vswName -ErrorAction SilentlyContinue
                        $vswCreated = $false
                        if (-not $vsw) {
                            $vsw = New-VirtualSwitch -VMHost $h -Name $vswName -ErrorAction Stop
                            $vswCreated = $true
                        }

                        # 2. Check if Port Group exists
                        $existingPg = Get-VirtualPortGroup -VMHost $h -Name $pgName -ErrorAction SilentlyContinue | Where-Object {
                            $_.VirtualSwitchName -eq $vswName -or $_.VirtualSwitch.Name -eq $vswName
                        }

                        if ($existingPg) {
                            $results += [PSCustomObject]@{
                                host    = $h.Name
                                vswitch = $vswName
                                name    = $pgName
                                vlanId  = $vlanId
                                status  = "skipped"
                                message = "已存在主機 (自動略過)"
                            }
                        } else {
                            New-VirtualPortGroup -VirtualSwitch $vsw -Name $pgName -VLanId $vlanId -ErrorAction Stop | Out-Null
                            $msg = if ($vswCreated) { "建立成功 (⚠️ 自動新建交換器 $vswName，尚未綁定實體 Uplink 網卡)" } else { "建立成功" }
                            $results += [PSCustomObject]@{
                                host    = $h.Name
                                vswitch = $vswName
                                name    = $pgName
                                vlanId  = $vlanId
                                status  = "created"
                                message = $msg
                            }
                        }
                    } catch {
                        $results += [PSCustomObject]@{
                            host    = $h.Name
                            vswitch = $vswName
                            name    = $pgName
                            vlanId  = $vlanId
                            status  = "error"
                            message = $_.Exception.Message
                        }
                    }
                }
            }

            $createdCount = ($results | Where-Object { $_.status -eq "created" }).Count
            $skippedCount = ($results | Where-Object { $_.status -eq "skipped" }).Count
            $errorCount   = ($results | Where-Object { $_.status -eq "error" }).Count

            Write-Host "Batch deploy finished: Created=$createdCount, Skipped=$skippedCount, Error=$errorCount" -ForegroundColor Green

            $summaryData = @{
                total   = $results.Count
                created = $createdCount
                skipped = $skippedCount
                error   = $errorCount
            }

            # Cache last deploy result for resume/audit
            $global:LastDeployResult = @{
                timestamp  = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                targetHost = $body.targetHost
                summary    = $summaryData
                results    = $results
            }

            Send-JsonResponse $response @{
                success = $true
                results = $results
                summary = $summaryData
            }
        } catch {
            Write-Host "Batch deploy exception: $($_.Exception.Message)" -ForegroundColor Red
            Send-JsonResponse $response @{
                success = $false
                message = $_.Exception.Message
            }
        }
        continue
    }

    # 4. API: Assign VM VLAN
    if ($rawUrl -eq "/api/assign" -and $request.HttpMethod -eq "POST") {
        $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
        $body = $reader.ReadToEnd() | ConvertFrom-Json

        if (-not $global:CachedCred) {
            Send-JsonResponse $response @{
                success = $false
                message = "Not connected to any vCenter/ESXi yet. Please connect first."
            }
            continue
        }

        $proto = if ($body.protocol) { $body.protocol } else { "icmp" }
        $testPort = if ($body.port) { [int]$body.port } else { 0 }

        Write-Host "Switching request: VM [$($body.vmName)] -> Switch [$($body.vswitch)] -> PortGroup [$($body.portGroup)] (Protocol: $proto, Port: $testPort)" -ForegroundColor Yellow

        try {
            $global:KeepVIServerSession = $true
            $resultJson = & $BackendScript `
                -VMName $body.vmName `
                -TargetIP $body.targetIp `
                -VSwitchName $body.vswitch `
                -PortGroupName $body.portGroup `
                -NicName $body.nicName `
                -Protocol $proto `
                -Port $testPort `
                -Server $global:CachedCred.Server `
                -Username $global:CachedCred.Username `
                -Password $global:CachedCred.Password

            $resultObj = $resultJson | ConvertFrom-Json
            Send-JsonResponse $response $resultObj
            Write-Host "Switch completed successfully!" -ForegroundColor Green
        } catch {
            Write-Host "Switch error: $($_.Exception.Message)" -ForegroundColor Red
            Send-JsonResponse $response @{
                success   = $false
                message   = $_.Exception.Message
                timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            }
        }
        continue
    }

    # 5. API: Clone VM with OS Customization (Hostname, Static IP, PortGroup)
    if ($rawUrl -eq "/api/clone-vm-custom" -and $request.HttpMethod -eq "POST") {
        $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
        $body = $reader.ReadToEnd() | ConvertFrom-Json

        if (-not $global:ActiveVIServer) {
            Send-JsonResponse $response @{
                success = $false
                message = "Not connected to any vCenter/ESXi yet. Please connect first."
            }
            continue
        }

        try {
            $srcName = ("" + $body.sourceVm).Trim()
            $dstName = ("" + $body.newVmName).Trim()
            $hostName = ("" + $body.hostName).Trim()
            if (-not $hostName) { $hostName = $dstName }

            if (-not $srcName -or -not $dstName) {
                Send-JsonResponse $response @{
                    success = $false
                    message = "Source VM and New VM Name are required."
                }
                continue
            }

            Write-Host "Fetching source VM [$srcName]..." -ForegroundColor Cyan
            $srcVm = Get-VM -Name $srcName -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $srcVm) {
                Send-JsonResponse $response @{
                    success = $false
                    message = "Source VM '$srcName' not found."
                }
                continue
            }

            $existingDst = Get-VM -Name $dstName -ErrorAction SilentlyContinue
            if ($existingDst) {
                Send-JsonResponse $response @{
                    success = $false
                    message = "A VM named '$dstName' already exists. Please choose a different name."
                }
                continue
            }

            Write-Host "Building NonPersistent OS Customization Spec for [$dstName]..." -ForegroundColor Cyan
            $osType = "Windows"
            if ($srcVm.GuestId -and $srcVm.GuestId -like "*linux*") {
                $osType = "Linux"
            }

            $specParams = @{
                Type = "NonPersistent"
                OSType = $osType
                NamingScheme = "Fixed"
                NamingPrefix = $hostName
                ErrorAction = "Stop"
            }
            if ($osType -eq "Windows") {
                $specParams["TimeZone"] = 205
                $specParams["Workgroup"] = "WORKGROUP"
            } else {
                $specParams["Domain"] = "local"
            }

            $spec = New-OSCustomizationSpec @specParams

            $nicMap = Get-OSCustomizationNicMapping -OSCustomizationSpec $spec | Select-Object -First 1
            $staticIp = ("" + $body.ip).Trim()

            if ($staticIp) {
                $subnet = if ($body.subnet) { ("" + $body.subnet).Trim() } else { "255.255.255.0" }
                $gw = if ($body.gateway) { ("" + $body.gateway).Trim() } else { $null }
                $dnsList = @()
                if ($body.dns) {
                    $dnsList = @(("" + $body.dns).Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                }

                $nicParams = @{
                    IpMode = "UseStatic"
                    IpAddress = $staticIp
                    SubnetMask = $subnet
                    ErrorAction = "Stop"
                }
                if ($gw) { $nicParams["DefaultGateway"] = $gw }
                if ($dnsList.Count -gt 0) { $nicParams["Dns"] = $dnsList }

                $nicMap | Set-OSCustomizationNicMapping @nicParams | Out-Null
            } else {
                $nicMap | Set-OSCustomizationNicMapping -IpMode UseDhcp -ErrorAction Stop | Out-Null
            }

            $vmParams = @{
                Name = $dstName
                VM = $srcVm
                OSCustomizationSpec = $spec
                ErrorAction = "Stop"
            }

            if ($body.targetHost) {
                $targetH = Get-VMHost -Name $body.targetHost -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($targetH) { $vmParams["VMHost"] = $targetH }
            }

            if ($body.datastore) {
                $targetDs = Get-Datastore -Name $body.datastore -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($targetDs) { $vmParams["Datastore"] = $targetDs }
            }

            Write-Host "Cloning VM [$srcName] -> [$dstName] with CustomizationSpec..." -ForegroundColor Yellow
            $clonedVm = New-VM @vmParams

            $targetPg = ("" + $body.portGroup).Trim()
            if ($targetPg) {
                Write-Host "Assigning PortGroup [$targetPg] to cloned VM [$dstName]..." -ForegroundColor Cyan
                $nic = Get-NetworkAdapter -VM $clonedVm -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($nic) {
                    $nic | Set-NetworkAdapter -PortGroup $targetPg -Confirm:$false -ErrorAction Stop | Out-Null
                }
            }

            $isPowerOn = [bool]$body.autoPowerOn
            if ($isPowerOn) {
                Write-Host "Powering on [$dstName] to execute Sysprep customization..." -ForegroundColor Green
                Start-VM -VM $clonedVm -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            }

            Write-Host "VM [$dstName] provisioned successfully!" -ForegroundColor Green

            Send-JsonResponse $response @{
                success   = $true
                vmName    = $dstName
                hostName  = $hostName
                ip        = if ($staticIp) { $staticIp } else { "DHCP" }
                portGroup = if ($targetPg) { $targetPg } else { "Original" }
                powerOn   = $isPowerOn
                message   = "VM [$dstName] provisioned successfully! OS Customization (Hostname: $hostName, IP: $(if ($staticIp) { $staticIp } else { 'DHCP' })) applied."
            }
        } catch {
            Write-Host "Provision error: $($_.Exception.Message)" -ForegroundColor Red
            Send-JsonResponse $response @{
                success = $false
                message = $_.Exception.Message
            }
        }
        continue
    }

    $response.StatusCode = 404
    $response.OutputStream.Close()
}