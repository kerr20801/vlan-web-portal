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

function Get-SafeHostPortGroups {
    param(
        [Parameter(Mandatory = $true)]
        $vmHostObj
    )

    $dict = [ordered]@{}

    # Source 1: Direct ESXi Host ExtensionData (Instant, complete, in-memory array of standard portgroups)
    try {
        if ($vmHostObj.ExtensionData -and $vmHostObj.ExtensionData.Config -and $vmHostObj.ExtensionData.Config.Network -and $vmHostObj.ExtensionData.Config.Network.Portgroup) {
            foreach ($rawPg in $vmHostObj.ExtensionData.Config.Network.Portgroup) {
                $pgName = [string]$rawPg.Spec.Name
                $vswName = [string]$rawPg.Spec.VswitchName
                $vlanId = 0
                if ($rawPg.Spec.VlanId -ne $null) {
                    [int]::TryParse([string]$rawPg.Spec.VlanId, [ref]$vlanId) | Out-Null
                }
                if ($pgName -and $vswName) {
                    $key = "$vswName|$pgName".ToLowerInvariant()
                    if (-not $dict.Contains($key)) {
                        $dict[$key] = [PSCustomObject]@{
                            host       = $vmHostObj.Name
                            vswitch    = $vswName
                            name       = $pgName
                            vlanId     = $vlanId
                            switchType = "Standard"
                        }
                    }
                }
            }
        }
    } catch {}

    # Source 2: Standard PowerCLI Get-VirtualPortGroup (Supplemental / Fallback with safe string/object checking)
    try {
        $pgs = Get-VirtualPortGroup -VMHost $vmHostObj -ErrorAction SilentlyContinue
        foreach ($pg in $pgs) {
            $vswName = ""
            if ($pg.VirtualSwitchName) {
                $vswName = [string]$pg.VirtualSwitchName
            } elseif ($pg.VirtualSwitch) {
                if ($pg.VirtualSwitch -is [string]) {
                    $vswName = [string]$pg.VirtualSwitch
                } elseif ($pg.VirtualSwitch.Name) {
                    $vswName = [string]$pg.VirtualSwitch.Name
                } else {
                    $vswName = [string]$pg.VirtualSwitch
                }
            }
            if (-not $vswName) { continue }

            $pgName = [string]$pg.Name
            if (-not $pgName) { continue }

            $vlanId = 0
            if ($pg.VLanId -ne $null) {
                [int]::TryParse([string]$pg.VLanId, [ref]$vlanId) | Out-Null
            }

            $key = "$vswName|$pgName".ToLowerInvariant()
            if (-not $dict.Contains($key)) {
                $dict[$key] = [PSCustomObject]@{
                    host       = $vmHostObj.Name
                    vswitch    = $vswName
                    name       = $pgName
                    vlanId     = $vlanId
                    switchType = "Standard"
                }
            }
        }
    } catch {}

    # Source 3: Distributed Virtual PortGroups (vDS)
    try {
        if (-not (Get-Command Get-VDSwitch -ErrorAction SilentlyContinue)) {
            Import-Module VMware.VimAutomation.Vds -ErrorAction SilentlyContinue
        }
        if (Get-Command Get-VDSwitch -ErrorAction SilentlyContinue) {
            $vdsList = Get-VDSwitch -VMHost $vmHostObj -ErrorAction SilentlyContinue
            foreach ($vds in $vdsList) {
                $vdPgs = Get-VDPortgroup -VDSwitch $vds -ErrorAction SilentlyContinue
                foreach ($vdpg in $vdPgs) {
                    $pgName = [string]$vdpg.Name
                    if (-not $pgName) { continue }
                    if ($vdpg.IsUplink -eq $true -or $pgName -like "*DVUplinks*") { continue }

                    $vswName = [string]$vds.Name
                    $vlanId = 0
                    if ($vdpg.VlanConfiguration) {
                        if ($vdpg.VlanConfiguration.VlanId -ne $null) {
                            [int]::TryParse([string]$vdpg.VlanConfiguration.VlanId, [ref]$vlanId) | Out-Null
                        } elseif ($vdpg.VlanConfiguration -is [int]) {
                            $vlanId = [int]$vdpg.VlanConfiguration
                        } elseif ($vdpg.VlanConfiguration.Ranges) {
                            $firstRange = $vdpg.VlanConfiguration.Ranges | Select-Object -First 1
                            if ($firstRange -and $firstRange.Start) {
                                $vlanId = [int]$firstRange.Start
                            }
                        }
                    }
                    if ($vlanId -eq 0 -and $vdpg.ExtensionData -and $vdpg.ExtensionData.Config -and $vdpg.ExtensionData.Config.DefaultPortConfig) {
                        try {
                            $vlanSpec = $vdpg.ExtensionData.Config.DefaultPortConfig.Vlan
                            if ($vlanSpec -and $vlanSpec.VlanId -ne $null) {
                                [int]::TryParse([string]$vlanSpec.VlanId, [ref]$vlanId) | Out-Null
                            }
                        } catch {}
                    }

                    $key = "$vswName|$pgName".ToLowerInvariant()
                    if (-not $dict.Contains($key)) {
                        $dict[$key] = [PSCustomObject]@{
                            host       = $vmHostObj.Name
                            vswitch    = $vswName
                            name       = $pgName
                            vlanId     = $vlanId
                            switchType = "Distributed"
                        }
                    }
                }
            }
        }
    } catch {}

    return @($dict.Values)
}

function Get-AllInventoryPortGroups {
    $dict = [ordered]@{}

    # 1. Iterate over all VMHosts
    $allHosts = Get-VMHost -ErrorAction SilentlyContinue
    foreach ($h in $allHosts) {
        $hostPgs = Get-SafeHostPortGroups -vmHostObj $h
        foreach ($item in $hostPgs) {
            $key = "$($item.vswitch)|$($item.name)".ToLowerInvariant()
            if (-not $dict.Contains($key)) {
                $dict[$key] = $item
            }
        }
    }

    # 2. Iterate over all VDPortgroups (Global vCenter vDS)
    try {
        if (-not (Get-Command Get-VDSwitch -ErrorAction SilentlyContinue)) {
            Import-Module VMware.VimAutomation.Vds -ErrorAction SilentlyContinue
        }
        if (Get-Command Get-VDSwitch -ErrorAction SilentlyContinue) {
            $allVds = Get-VDSwitch -ErrorAction SilentlyContinue
            foreach ($vds in $allVds) {
                $vdPgs = Get-VDPortgroup -VDSwitch $vds -ErrorAction SilentlyContinue
                foreach ($vdpg in $vdPgs) {
                    $pgName = [string]$vdpg.Name
                    if (-not $pgName) { continue }
                    if ($vdpg.IsUplink -eq $true -or $pgName -like "*DVUplinks*") { continue }

                    $vswName = [string]$vds.Name
                    $vlanId = 0
                    if ($vdpg.VlanConfiguration) {
                        if ($vdpg.VlanConfiguration.VlanId -ne $null) {
                            [int]::TryParse([string]$vdpg.VlanConfiguration.VlanId, [ref]$vlanId) | Out-Null
                        } elseif ($vdpg.VlanConfiguration -is [int]) {
                            $vlanId = [int]$vdpg.VlanConfiguration
                        } elseif ($vdpg.VlanConfiguration.Ranges) {
                            $firstRange = $vdpg.VlanConfiguration.Ranges | Select-Object -First 1
                            if ($firstRange -and $firstRange.Start) {
                                $vlanId = [int]$firstRange.Start
                            }
                        }
                    }
                    if ($vlanId -eq 0 -and $vdpg.ExtensionData -and $vdpg.ExtensionData.Config -and $vdpg.ExtensionData.Config.DefaultPortConfig) {
                        try {
                            $vlanSpec = $vdpg.ExtensionData.Config.DefaultPortConfig.Vlan
                            if ($vlanSpec -and $vlanSpec.VlanId -ne $null) {
                                [int]::TryParse([string]$vlanSpec.VlanId, [ref]$vlanId) | Out-Null
                            }
                        } catch {}
                    }

                    $key = "$vswName|$pgName".ToLowerInvariant()
                    if (-not $dict.Contains($key)) {
                        $dict[$key] = [PSCustomObject]@{
                            host       = "vCenter-Global"
                            vswitch    = $vswName
                            name       = $pgName
                            vlanId     = $vlanId
                            switchType = "Distributed"
                        }
                    }
                }
            }
        }
    } catch {}

    return @($dict.Values)
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
            $tempMap = [ordered]@{}

            # 1. Standard Switches & PortGroups across all hosts
            $allVswitches = Get-VirtualSwitch -ErrorAction SilentlyContinue
            foreach ($vsw in $allVswitches) {
                $vswName = [string]$vsw.Name
                if (-not $vswName) { continue }
                if (-not $tempMap.Contains($vswName)) {
                    $tempMap[$vswName] = New-Object System.Collections.Generic.HashSet[string]
                }
                $pgs = Get-VirtualPortGroup -VirtualSwitch $vsw -ErrorAction SilentlyContinue
                foreach ($pg in $pgs) {
                    if ($pg.Name) {
                        $tempMap[$vswName].Add([string]$pg.Name) | Out-Null
                    }
                }
            }

            # Supplement from ESXi host direct ExtensionData config to ensure 100% of standard portgroups are included
            $allHostObjs = Get-VMHost -ErrorAction SilentlyContinue
            foreach ($hObj in $allHostObjs) {
                try {
                    if ($hObj.ExtensionData.Config.Network.Portgroup) {
                        foreach ($rawPg in $hObj.ExtensionData.Config.Network.Portgroup) {
                            $vswName = [string]$rawPg.Spec.VswitchName
                            $pgName = [string]$rawPg.Spec.Name
                            if ($vswName -and $pgName) {
                                if (-not $tempMap.Contains($vswName)) {
                                    $tempMap[$vswName] = New-Object System.Collections.Generic.HashSet[string]
                                }
                                $tempMap[$vswName].Add($pgName) | Out-Null
                            }
                        }
                    }
                } catch {}
            }

            # 2. Distributed Switches (vDS)
            try {
                if (-not (Get-Command Get-VDSwitch -ErrorAction SilentlyContinue)) {
                    Import-Module VMware.VimAutomation.Vds -ErrorAction SilentlyContinue
                }
                if (Get-Command Get-VDSwitch -ErrorAction SilentlyContinue) {
                    $allVds = Get-VDSwitch -ErrorAction SilentlyContinue
                    foreach ($vds in $allVds) {
                        $vdsName = [string]$vds.Name
                        if (-not $vdsName) { continue }
                        if (-not $tempMap.Contains($vdsName)) {
                            $tempMap[$vdsName] = New-Object System.Collections.Generic.HashSet[string]
                        }
                        $vdpgs = Get-VDPortgroup -VDSwitch $vds -ErrorAction SilentlyContinue
                        foreach ($vdpg in $vdpgs) {
                            if ($vdpg.Name -and $vdpg.IsUplink -ne $true -and $vdpg.Name -notlike "*DVUplinks*") {
                                $tempMap[$vdsName].Add([string]$vdpg.Name) | Out-Null
                            }
                        }
                    }
                }
            } catch {}

            $networkMap = [ordered]@{}
            foreach ($key in $tempMap.Keys) {
                $networkMap[$key] = @($tempMap[$key] | Sort-Object)
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
                $hostsToQuery = Get-VMHost -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $targetHostName }
                if (-not $hostsToQuery) {
                    try {
                        $escTH = [System.Management.Automation.WildcardPattern]::Escape($targetHostName)
                        $hostsToQuery = Get-VMHost -Name $escTH -ErrorAction SilentlyContinue
                    } catch {}
                }
            }

            $portGroupList = @()
            if ($targetHostName -eq "_ALL_") {
                $portGroupList = Get-AllInventoryPortGroups
            } else {
                foreach ($h in $hostsToQuery) {
                    $hostPgs = Get-SafeHostPortGroups -vmHostObj $h
                    $portGroupList += $hostPgs
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
            Write-Host "Extracting network configuration from source: [$srcHostName]..." -ForegroundColor Cyan

            $rawItems = @()
            if ($srcHostName -eq "_ALL_") {
                $rawItems = Get-AllInventoryPortGroups
            } else {
                $hostObj = Get-VMHost -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $srcHostName } | Select-Object -First 1
                if (-not $hostObj) {
                    try {
                        $escSH = [System.Management.Automation.WildcardPattern]::Escape($srcHostName)
                        $hostObj = Get-VMHost -Name $escSH -ErrorAction SilentlyContinue | Select-Object -First 1
                    } catch {}
                }
                if (-not $hostObj) {
                    Send-JsonResponse $response @{
                        success = $false
                        message = "Source host '$srcHostName' not found."
                    }
                    continue
                }
                $rawItems = Get-SafeHostPortGroups -vmHostObj $hostObj
            }

            $items = @()
            $textLines = @()

            foreach ($item in $rawItems) {
                $vswName = $item.vswitch
                $pgName  = $item.name
                $vlanId  = [int]$item.vlanId

                # Skip default VM / Management networks if requested
                if ($body.skipDefaultVmNetwork -and ($pgName -eq "VM Network" -or $pgName -eq "Management Network")) {
                    continue
                }

                $items += [PSCustomObject]@{
                    vswitch    = $vswName
                    name       = $pgName
                    vlanId     = $vlanId
                    switchType = $item.switchType
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
                $targetHosts = Get-VMHost -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $body.targetHost }
                if (-not $targetHosts) {
                    try {
                        $escTH = [System.Management.Automation.WildcardPattern]::Escape($body.targetHost)
                        $targetHosts = Get-VMHost -Name $escTH -ErrorAction SilentlyContinue
                    } catch {}
                }
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

                # Pre-cache existing portgroups for instant O(1) existence checks
                $existingPgMap = @{}
                $currentHostPgs = Get-SafeHostPortGroups -vmHostObj $h
                foreach ($cpg in $currentHostPgs) {
                    $existingPgMap["$($cpg.vswitch)|$($cpg.name)".ToLowerInvariant()] = $true
                }

                # Pre-cache vSwitches
                $vswMap = @{}
                $existingVsws = Get-VirtualSwitch -VMHost $h -ErrorAction SilentlyContinue
                foreach ($v in $existingVsws) {
                    if ($v.Name) { $vswMap[$v.Name.ToLowerInvariant()] = $v }
                }

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
                        $pgKey = "$vswName|$pgName".ToLowerInvariant()
                        if ($existingPgMap.ContainsKey($pgKey)) {
                            $results += [PSCustomObject]@{
                                host    = $h.Name
                                vswitch = $vswName
                                name    = $pgName
                                vlanId  = $vlanId
                                status  = "skipped"
                                message = "已存在主機 (自動略過)"
                            }
                            continue
                        }

                        # 1. Check or auto-create vSwitch
                        $vsw = $vswMap[$vswName.ToLowerInvariant()]
                        $vswCreated = $false
                        if (-not $vsw) {
                            $vsw = New-VirtualSwitch -VMHost $h -Name $vswName -ErrorAction Stop
                            $vswMap[$vswName.ToLowerInvariant()] = $vsw
                            $vswCreated = $true
                        }

                        # 2. Create Port Group
                        New-VirtualPortGroup -VirtualSwitch $vsw -Name $pgName -VLanId $vlanId -ErrorAction Stop | Out-Null
                        $existingPgMap[$pgKey] = $true

                        $msg = if ($vswCreated) { "建立成功 (⚠️ 自動新建交換器 $vswName，尚未綁定實體 Uplink 網卡)" } else { "建立成功" }
                        $results += [PSCustomObject]@{
                            host    = $h.Name
                            vswitch = $vswName
                            name    = $pgName
                            vlanId  = $vlanId
                            status  = "created"
                            message = $msg
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
            # Exact pipeline match first (immune to PowerShell wildcard characters like [ ], *, ?)
            $srcVm = Get-VM -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $srcName } | Select-Object -First 1
            if (-not $srcVm) {
                try {
                    $escPattern = [System.Management.Automation.WildcardPattern]::Escape($srcName)
                    $srcVm = Get-VM -Name $escPattern -ErrorAction SilentlyContinue | Select-Object -First 1
                } catch {}
            }
            if (-not $srcVm) {
                $srcVm = Get-VM -Name $srcName -ErrorAction SilentlyContinue | Select-Object -First 1
            }

            if (-not $srcVm) {
                $avail = @(Get-VM -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
                Write-Host "Source VM '$srcName' not found. Available: $($avail -join ', ')" -ForegroundColor Yellow
                Send-JsonResponse $response @{
                    success = $false
                    message = "Source VM '$srcName' not found. Please verify the VM exists in inventory."
                }
                continue
            }

            $existingDst = Get-VM -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $dstName } | Select-Object -First 1
            if (-not $existingDst) {
                try {
                    $escDst = [System.Management.Automation.WildcardPattern]::Escape($dstName)
                    $existingDst = Get-VM -Name $escDst -ErrorAction SilentlyContinue | Select-Object -First 1
                } catch {}
            }
            if ($existingDst) {
                Send-JsonResponse $response @{
                    success = $false
                    message = "A VM named '$dstName' already exists. Please choose a different name."
                }
                continue
            }

            Write-Host "Building NonPersistent OS Customization Spec for [$dstName]..." -ForegroundColor Cyan

            # 1. Parse DNS servers list
            $dnsList = @()
            if ($body.dns) {
                $dnsList = @(("" + $body.dns).Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            }

            # 2. Robust OS detection: check GuestId, Guest.OSFullName, and VM Name
            $isLinux = $false
            $guestId = ("" + $srcVm.GuestId).ToLowerInvariant()
            $guestOs = ("" + $srcVm.Guest.OSFullName).ToLowerInvariant()
            $vmNameLower = ("" + $srcVm.Name).ToLowerInvariant()

            $linuxKeywords = @("linux", "ubuntu", "debian", "centos", "rhel", "redhat", "sles", "suse", "photon", "fedora", "oracle", "rocky", "alma", "arch", "gentoo", "alpine", "freebsd")

            foreach ($kw in $linuxKeywords) {
                if ($guestId.Contains($kw) -or $guestOs.Contains($kw) -or $vmNameLower.Contains($kw)) {
                    $isLinux = $true
                    break
                }
            }

            if ($body.osType) {
                if ($body.osType -eq "Linux") { $isLinux = $true }
                if ($body.osType -eq "Windows") { $isLinux = $false }
            }

            $osType = if ($isLinux) { "Linux" } else { "Windows" }
            Write-Host "Detected OS Type: $osType for [$srcName] (GuestId: $guestId, OS: $guestOs)" -ForegroundColor Cyan

            # 3. Sanitize hostName for RFC 1123 / NetBIOS compliance
            # RFC 1123 only allows alphanumeric and hyphen (-). Underscores (_), periods, and spaces are strictly disallowed by vCenter.
            $rawHostName = ("" + $body.hostName).Trim()
            if (-not $rawHostName) { $rawHostName = $dstName }

            $cleanHostName = ($rawHostName -replace '[^a-zA-Z0-9-]', '-') -replace '-+', '-'
            $cleanHostName = $cleanHostName.Trim('-')
            if (-not $cleanHostName) {
                $cleanHostName = "vm-host"
            }

            if ($osType -eq "Windows") {
                # Windows NetBIOS computer name limit: 15 characters
                if ($cleanHostName.Length -gt 15) {
                    $cleanHostName = $cleanHostName.Substring(0, 15).Trim('-')
                }
            } else {
                # Linux RFC 1123 hostname: lowercase, max 63 characters
                $cleanHostName = $cleanHostName.ToLowerInvariant()
                if ($cleanHostName.Length -gt 63) {
                    $cleanHostName = $cleanHostName.Substring(0, 63).Trim('-')
                }
            }
            Write-Host "Sanitized RFC 1123 Hostname: [$rawHostName] -> [$cleanHostName]" -ForegroundColor Cyan

            $specParams = @{
                Type         = "NonPersistent"
                OSType       = $osType
                NamingScheme = "Fixed"
                NamingPrefix = $cleanHostName
                ErrorAction  = "Stop"
            }

            if ($osType -eq "Windows") {
                # WindowsParameterSet mandatory parameters: FullName & OrgName
                $specParams["FullName"]  = "Administrator"
                $specParams["OrgName"]   = "Organization"
                $specParams["TimeZone"]  = 205
                $specParams["Workgroup"] = "WORKGROUP"
                $specParams["ChangeSid"] = $true
            } else {
                # Linux customization spec: DnsServer is placed directly on the spec
                $specParams["Domain"] = "local"
                if ($dnsList.Count -gt 0) {
                    $specParams["DnsServer"] = $dnsList
                }
            }

            $spec = New-OSCustomizationSpec @specParams

            $nicMap = Get-OSCustomizationNicMapping -OSCustomizationSpec $spec | Select-Object -First 1

            # 4. Configure IP mode (DHCP vs Static IP)
            $ipMode = if ($body.ipMode) { ("" + $body.ipMode).Trim().ToLowerInvariant() } else { "auto" }
            $staticIp = ("" + $body.ip).Trim()
            $isDhcp = ($ipMode -eq "dhcp" -or -not $staticIp)

            if ($isDhcp) {
                Write-Host "Configuring NIC mapping for DHCP (Dynamic IP)..." -ForegroundColor Cyan
                $nicMap | Set-OSCustomizationNicMapping -IpMode UseDhcp -ErrorAction Stop | Out-Null
            } else {
                Write-Host "Configuring NIC mapping for Static IP [$staticIp]..." -ForegroundColor Cyan
                $subnet = if ($body.subnet) { ("" + $body.subnet).Trim() } else { "255.255.255.0" }
                $gw = if ($body.gateway) { ("" + $body.gateway).Trim() } else { $null }

                $nicParams = @{
                    IpMode      = "UseStatic"
                    IpAddress   = $staticIp
                    SubnetMask  = $subnet
                    ErrorAction = "Stop"
                }
                if ($gw) { $nicParams["DefaultGateway"] = $gw }
                # Only pass -Dns to Set-OSCustomizationNicMapping if Windows (Linux must not provide Dns on NIC mapping)
                if ($osType -eq "Windows" -and $dnsList.Count -gt 0) {
                    $nicParams["Dns"] = $dnsList
                }

                $nicMap | Set-OSCustomizationNicMapping @nicParams | Out-Null
            }

            $vmParams = @{
                Name = $dstName
                VM = $srcVm
                OSCustomizationSpec = $spec
                ErrorAction = "Stop"
            }

            if ($body.targetHost) {
                $targetH = Get-VMHost -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $body.targetHost } | Select-Object -First 1
                if (-not $targetH) {
                    try {
                        $escH = [System.Management.Automation.WildcardPattern]::Escape($body.targetHost)
                        $targetH = Get-VMHost -Name $escH -ErrorAction SilentlyContinue | Select-Object -First 1
                    } catch {}
                }
                if ($targetH) { $vmParams["VMHost"] = $targetH }
            }

            if ($body.datastore) {
                $dsName = ("" + $body.datastore).Trim()
                $targetDs = Get-Datastore -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $dsName } | Select-Object -First 1
                if (-not $targetDs) {
                    try {
                        $escDs = [System.Management.Automation.WildcardPattern]::Escape($dsName)
                        $targetDs = Get-Datastore -Name $escDs -ErrorAction SilentlyContinue | Select-Object -First 1
                    } catch {}
                }
                if ($targetDs) { $vmParams["Datastore"] = $targetDs }
            }

            Write-Host "Cloning VM [$srcName] -> [$dstName] with CustomizationSpec..." -ForegroundColor Yellow
            $clonedVm = New-VM @vmParams

            $targetPg = ("" + $body.portGroup).Trim()
            if ($targetPg) {
                Write-Host "Assigning PortGroup [$targetPg] to cloned VM [$dstName]..." -ForegroundColor Cyan
                $nic = Get-NetworkAdapter -VM $clonedVm -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($nic) {
                    $pgObj = Get-VirtualPortGroup -Name $targetPg -ErrorAction SilentlyContinue | Select-Object -First 1
                    if (-not $pgObj -and (Get-Command Get-VDPortgroup -ErrorAction SilentlyContinue)) {
                        $pgObj = Get-VDPortgroup -Name $targetPg -ErrorAction SilentlyContinue | Select-Object -First 1
                    }
                    if ($pgObj) {
                        $nic | Set-NetworkAdapter -PortGroup $pgObj -Confirm:$false -ErrorAction Stop | Out-Null
                    } else {
                        $nic | Set-NetworkAdapter -PortGroup $targetPg -Confirm:$false -ErrorAction Stop | Out-Null
                    }
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
                hostName  = $cleanHostName
                ip        = if ($isDhcp) { "DHCP (自動取得)" } else { $staticIp }
                portGroup = if ($targetPg) { $targetPg } else { "Original" }
                powerOn   = $isPowerOn
                message   = "VM [$dstName] 開通成功！OS 自訂規格 (Hostname: $cleanHostName, IP: $(if ($isDhcp) { 'DHCP (自動取得)' } else { $staticIp })) 已套用。"
            }
        } catch {
            Write-Host "Provision error: $($_.Exception.Message)" -ForegroundColor Red
            $rawErr = $_.Exception.Message
            $friendlyErr = $rawErr
            if ($rawErr -like "*not supported on the object*" -or $rawErr -like "*CloneVM_Task*" -or $rawErr -like "*vCenter Server*") {
                $friendlyErr = "克隆與 Sysprep 自訂規格需透過 vCenter Server 執行。若直接連線至單台 ESXi 主機，因 VMware 原生架構限制不支援 CloneVM_Task API，請切換連線至 vCenter Server 管理平台。"
            }
            Send-JsonResponse $response @{
                success = $false
                message = $friendlyErr
            }
        }
        continue
    }

    $response.StatusCode = 404
    $response.OutputStream.Close()
}