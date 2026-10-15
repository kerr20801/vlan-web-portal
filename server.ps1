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

    # Allow CORS
    $response.AddHeader("Access-Control-Allow-Origin", "*")
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

            if ($global:ActiveVIServer) {
                Disconnect-VIServer -Server $global:ActiveVIServer -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            }

            Write-Host "Connecting to target host [$targetServer]..." -ForegroundColor Cyan
            $secPass = ConvertTo-SecureString $body.password -AsPlainText -Force
            $cred = New-Object System.Management.Automation.PSCredential($body.username, $secPass)

            $conn = Connect-VIServer -Server $targetServer -Credential $cred -ErrorAction Stop

            $global:ActiveVIServer = $conn
            $global:CachedCred = @{
                Server   = $targetServer
                Username = $body.username
                Password = $body.password
            }

            Write-Host "Querying ESXi hosts inventory..." -ForegroundColor Gray
            $hosts = Get-VMHost -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name | Sort-Object

            Write-Host "Querying VM inventory..." -ForegroundColor Gray
            $vms = Get-VM -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name | Sort-Object

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
                                message = "Already exists (Skipped)"
                            }
                        } else {
                            New-VirtualPortGroup -VirtualSwitch $vsw -Name $pgName -VLanId $vlanId -ErrorAction Stop | Out-Null
                            $results += [PSCustomObject]@{
                                host    = $h.Name
                                vswitch = $vswName
                                name    = $pgName
                                vlanId  = $vlanId
                                status  = "created"
                                message = if ($vswCreated) { "Created (and auto-created $vswName)" } else { "Created" }
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

            Send-JsonResponse $response @{
                success = $true
                results = $results
                summary = @{
                    total   = $results.Count
                    created = $createdCount
                    skipped = $skippedCount
                    error   = $errorCount
                }
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

        Write-Host "Switching request: VM [$($body.vmName)] -> Switch [$($body.vswitch)] -> PortGroup [$($body.portGroup)]" -ForegroundColor Yellow

        try {
            $global:KeepVIServerSession = $true
            $resultJson = & $BackendScript `
                -VMName $body.vmName `
                -TargetIP $body.targetIp `
                -VSwitchName $body.vswitch `
                -PortGroupName $body.portGroup `
                -NicName $body.nicName `
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

    $response.StatusCode = 404
    $response.OutputStream.Close()
}