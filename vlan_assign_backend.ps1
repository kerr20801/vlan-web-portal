<#
.SYNOPSIS
    Backend script: Change VM network adapter to target vSwitch / Port Group,
    then execute connectivity test (Ping/ICMP, SSH/22, RDP/3389, Custom TCP).
    Supports both vCenter and standalone ESXi.
#>

param(
    [Parameter(Mandatory=$true)] [string]$VMName,
    [Parameter(Mandatory=$true)] [string]$TargetIP,
    [Parameter(Mandatory=$true)] [string]$VSwitchName,
    [Parameter(Mandatory=$true)] [string]$PortGroupName,
    [string]$NicName = "",
    [string]$Protocol = "icmp",
    [int]$Port = 0,
    [int]$TimeoutSeconds = 3,
    [int]$RetryCount = 3,
    [string]$Server = "",
    [string]$Username = "",
    [string]$Password = ""
)

$ErrorActionPreference = "Stop"

# 1. Load portable modules if present
$localModules = Join-Path $PSScriptRoot "Modules"
if (Test-Path $localModules) {
    $env:PSModulePath = "$localModules;$env:PSModulePath"
}
Import-Module VMware.VimAutomation.Core -ErrorAction SilentlyContinue

function Write-Result {
    param(
        [bool]$Success,
        [string]$Message,
        [bool]$ConnectivityPassed = $false,
        [string]$BeforePortGroup = "",
        [string]$TestDetail = ""
    )
    $result = [PSCustomObject]@{
        success          = $Success
        message          = $Message
        sshOpen          = $ConnectivityPassed # Keep for backward compatibility
        connectivityOk   = $ConnectivityPassed
        detail           = $TestDetail
        beforePortGroup  = $BeforePortGroup
        timestamp        = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }
    $result | ConvertTo-Json -Compress
}

function Test-Connectivity {
    param(
        [string]$Ip,
        [string]$TestProtocol,
        [int]$TestPort,
        [int]$TimeoutSec,
        [int]$Retries
    )
    
    if (-not $Ip) {
        return @{ success = $false; detail = "Target IP is empty" }
    }

    # Normalize protocol & target port
    $proto = if ($TestProtocol) { $TestProtocol.ToLower().Trim() } else { "icmp" }
    $resolvedPort = $TestPort
    if ($proto -eq "ssh" -and $resolvedPort -le 0) { $resolvedPort = 22 }
    elseif ($proto -eq "rdp" -and $resolvedPort -le 0) { $resolvedPort = 3389 }
    elseif ($proto -eq "custom" -and $resolvedPort -le 0) { $resolvedPort = 80 }

    for ($attempt = 1; $attempt -le $Retries; $attempt++) {
        if ($proto -eq "icmp" -or $proto -eq "ping") {
            try {
                $ping = New-Object System.Net.NetworkInformation.Ping
                $reply = $ping.Send($Ip, $TimeoutSec * 1000)
                if ($reply.Status -eq "Success") {
                    return @{
                        success = $true
                        detail  = "ICMP Ping reply in $($reply.RoundtripTime)ms (Attempt $attempt)"
                    }
                }
            } catch {
                # Ping retry
            }
        } else {
            # TCP Port check (SSH, RDP, Custom)
            try {
                $tcp = New-Object System.Net.Sockets.TcpClient
                $connectTask = $tcp.ConnectAsync($Ip, $resolvedPort)
                $completed = $connectTask.Wait([TimeSpan]::FromSeconds($TimeoutSec))
                $isOpen = $completed -and $tcp.Connected
                $tcp.Close()
                if ($isOpen) {
                    return @{
                        success = $true
                        detail  = "TCP Port $resolvedPort connected successfully (Attempt $attempt)"
                    }
                }
            } catch {
                # TCP retry
            }
        }

        if ($attempt -lt $Retries) {
            Start-Sleep -Seconds 2
        }
    }

    $failDesc = if ($proto -eq "icmp" -or $proto -eq "ping") {
        "ICMP Ping Timeout (Tried $Retries times)"
    } else {
        "TCP Port $resolvedPort Closed/Timeout (Tried $Retries times)"
    }
    return @{ success = $false; detail = $failDesc }
}

if (Get-Command Set-PowerCLIConfiguration -ErrorAction SilentlyContinue) {
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -ParticipateInCEIP $false -Confirm:$false -Scope Session -ErrorAction SilentlyContinue | Out-Null
}

$rawServer = if ($Server) { $Server } else { $env:VC_SERVER }
$vcServer = if ($rawServer) { $rawServer.Trim() -replace '^https?://', '' -replace '/.*$', '' } else { "" }
$vcUser   = if ($Username) { $Username } else { $env:VC_SERVICE_USER }
$vcPass   = if ($Password) { $Password } else { $env:VC_SERVICE_PASS }

if (-not $vcServer -or -not $vcUser -or -not $vcPass) {
    Write-Result -Success $false -Message "Missing connection credentials (Server, Username, Password)."
    exit 1
}

$needDisconnect = $false

try {
    $existingServer = $global:DefaultVIServers | Where-Object { $_.Name -eq $vcServer -and $_.IsConnected }
    if (-not $existingServer) {
        $securePass = ConvertTo-SecureString $vcPass -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential($vcUser, $securePass)
        Connect-VIServer -Server $vcServer -Credential $cred -ErrorAction Stop | Out-Null
        $needDisconnect = $true
    }

    $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
    if (-not $vm) {
        Write-Result -Success $false -Message "Target VM '$VMName' not found on server [$vcServer]."
        exit 1
    }

    $targetHost = if ($vm.VMHost) { $vm.VMHost } else { Get-VMHost | Select-Object -First 1 }
    
    $vswitch = $null
    if ($targetHost) {
        $vswitch = Get-VirtualSwitch -VMHost $targetHost -Name $VSwitchName -ErrorAction SilentlyContinue
    }
    if (-not $vswitch) {
        $vswitch = Get-VirtualSwitch -Name $VSwitchName -ErrorAction SilentlyContinue
    }

    if (-not $vswitch) {
        Write-Result -Success $false -Message "vSwitch '$VSwitchName' not found."
        exit 1
    }

    $portGroup = Get-VirtualPortGroup -VirtualSwitch $vswitch -Name $PortGroupName -ErrorAction SilentlyContinue
    if (-not $portGroup) {
        $portGroup = Get-VirtualPortGroup -Name $PortGroupName -ErrorAction SilentlyContinue | Where-Object { 
            $_.VirtualSwitchName -eq $VSwitchName -or $_.VirtualSwitch.Name -eq $VSwitchName 
        } | Select-Object -First 1
    }

    if (-not $portGroup) {
        Write-Result -Success $false -Message "Port Group (VLAN) '$PortGroupName' not found in vSwitch '$VSwitchName'."
        exit 1
    }

    $nic = $null
    if ($NicName) {
        $nic = Get-NetworkAdapter -VM $vm -Name $NicName -ErrorAction SilentlyContinue
        if (-not $nic) {
            Write-Result -Success $false -Message "Network adapter '$NicName' not found on VM '$VMName'."
            exit 1
        }
    } else {
        $nic = Get-NetworkAdapter -VM $vm | Select-Object -First 1
        if (-not $nic) {
            Write-Result -Success $false -Message "No network adapter found on VM '$VMName'."
            exit 1
        }
    }

    $beforePortGroup = $nic.NetworkName

    Set-NetworkAdapter -NetworkAdapter $nic -PortGroup $portGroup -Confirm:$false | Out-Null

    # Wait for network layer stabilization
    Start-Sleep -Seconds 2

    # Run multi-protocol connectivity test with retry buffer
    $testResult = Test-Connectivity `
        -Ip $TargetIP `
        -TestProtocol $Protocol `
        -TestPort $Port `
        -TimeoutSec $TimeoutSeconds `
        -Retries $RetryCount

    $connStatusStr = if ($testResult.success) { "PASS ($($testResult.detail))" } else { "FAIL ($($testResult.detail))" }
    $msg = "VM '$VMName' adapter [$($nic.Name)] switched from '$beforePortGroup' to '$PortGroupName' ($VSwitchName). Connectivity check [$TargetIP]: $connStatusStr."
    
    Write-Result `
        -Success $true `
        -Message $msg `
        -ConnectivityPassed $testResult.success `
        -BeforePortGroup $beforePortGroup `
        -TestDetail $testResult.detail
}
catch {
    Write-Result -Success $false -Message "Exception occurred: $($_.Exception.Message)"
    exit 1
}
finally {
    if ($needDisconnect -and (-not $global:KeepVIServerSession)) {
        Disconnect-VIServer -Server $vcServer -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    }
}