[VMware.VimAutomation.Sdk.Interop.V1.CoreServiceFactory]::CoreService.OnImportModule(
    "VMware.VimAutomation.ViCore.Cmdlets",
    (Split-Path $script:MyInvocation.MyCommand.Path));

function global:New-DatastoreDrive([string] $Name, $Datastore){
<#
.SYNOPSIS
This function creates a new datastore drive.
.DESCRIPTION
This function creates a new drive that is mapped to a location in a datastore.
.PARAMETER Name
Specifies a name for the new drive.
.PARAMETER Datastore
Specifies the datastore for which you want to create a new drive.
#>
	begin {
		if ($Datastore) {
			Write-Output $Datastore | New-DatastoreDrive -Name $Name
		}
	}
	process {
		if ($_) {
			$ds = $_
			New-PSDrive -Name $Name -Root \ -PSProvider VimDatastore -Datastore $ds -Scope global
		}
	}
	end {
	}
}

function global:New-VIInventoryDrive([string] $Name, $Location){
<#
.SYNOPSIS
This function creates a new drive for an inventory item.
.DESCRIPTION
This function creates a new inventory drive that is mapped to a location in a datastore.
.PARAMETER Name
Specifies the name of the new inventory drive.
.PARAMETER Location
Specifies the vSphere container objects (such as folders, data centers, and clusters) for which you want to create the drive.
#>
	begin {
		if ($Location) {
			Write-Output $Location | New-VIInventoryDrive -Name $Name
		}
	}
	process {
		if ($_) {
			$location = $_
			New-PSDrive -Name $name -Root \ -PSProvider VimInventory -Location $location -Scope global
		}
	}
	end {
	}
}

function global:Get-VICommand([string] $Name = "*") {
<#
.SYNOPSIS
This function retrieves all commands of the VMware modules.
.DESCRIPTION
This function retrieves all commands of the imported VMware modules, including cmdlets, aliases, and functions.
.PARAMETER Name
Specifies the name of the command you want to retrieve.
#>

<#
Workaround for https://bugzilla-vcf.lvn.broadcom.net/show_bug.cgi?id=3500727

This file is imported as a nested module in the binary module descriptor. This leads to duplicate results when retrieving
cmdlet aliases.
Since the file does not actually contain any module metadata its GUID is set to a default value which we can use to filter out these duplicates.
#>
  Get-Command -Module VMware.* -Name $Name | ? {$_.Module.Guid -ne '00000000-0000-0000-0000-000000000000'}
}


function HookGetViewAutoCompleter() {	
	if ( -not (Test-Path Function:\TabExpansionDefault) ) {
		
		# This is the new definition of the TabExpansion2 function
		$tabExpansionProxyFunction = 
		'
			[CmdletBinding(DefaultParameterSetName = ''ScriptInputSet'')]
			Param(
				[Parameter(ParameterSetName = ''ScriptInputSet'', Mandatory = $true, Position = 0)]
				[string] $inputScript,

				[Parameter(ParameterSetName = ''ScriptInputSet'', Mandatory = $true, Position = 1)]
				[int] $cursorColumn,

				[Parameter(ParameterSetName = ''AstInputSet'', Mandatory = $true, Position = 0)]
				[System.Management.Automation.Language.Ast] $ast,

				[Parameter(ParameterSetName = ''AstInputSet'', Mandatory = $true, Position = 1)]
				[System.Management.Automation.Language.Token[]] $tokens,

				[Parameter(ParameterSetName = ''AstInputSet'', Mandatory = $true, Position = 2)]
				[System.Management.Automation.Language.IScriptPosition] $positionOfCursor,

				[Parameter(ParameterSetName = ''ScriptInputSet'', Position = 2)]
				[Parameter(ParameterSetName = ''AstInputSet'', Position = 3)]
				[Hashtable] $options = $null
			)

			End
			{
				if ($psCmdlet.ParameterSetName -eq ''ScriptInputSet'') {
					$shouldProcessInput = [VMware.VimAutomation.ViCore.Cmdlets.Commands.DotNetInterop.GetViewAutoCompleter]::ShouldProcess(
						<#inputScript#>  $inputScript,
						<#cursorColumn#> $cursorColumn,
						<#options#>        $options)
					
					if ($shouldProcessInput) {
						return [VMware.VimAutomation.ViCore.Cmdlets.Commands.DotNetInterop.GetViewAutoCompleter]::CompleteInput(
							<#inputScript#>  $inputScript,
							<#cursorColumn#> $cursorColumn,
							<#options#>        $options)
					} else {
						return global:TabExpansionDefault $inputScript $cursorColumn $options
					}
				} else {
					$shouldProcessInput = [VMware.VimAutomation.ViCore.Cmdlets.Commands.DotNetInterop.GetViewAutoCompleter]::ShouldProcess(
						<#ast#>              $ast,
						<#tokens#>           $tokens,
						<#positionOfCursor#> $positionOfCursor,
						<#options#>          $options)
					
					if ($shouldProcessInput) {
						return [VMware.VimAutomation.ViCore.Cmdlets.Commands.DotNetInterop.GetViewAutoCompleter]::CompleteInput(
							<#ast#>              $ast,
							<#tokens#>           $tokens,
							<#positionOfCursor#> $positionOfCursor,
							<#options#>          $options)
					} else {
						return global:TabExpansionDefault $ast $tokens $positionOfCursor $options
					}
				}
			}
		'
	
		# Declare a new function that will hold the current tab expansion implementation
		Copy-Item Function:\TabExpansion2 Function:\global:TabExpansionDefault
		
		# Override the current tab expansion implementation to hook our proxy
		Set-Item -Path Function:\TabExpansion2 -Value $tabExpansionProxyFunction
	}
}


# Aliases
set-alias Get-VIServer Connect-VIServer -Scope Global
set-alias Get-VC Connect-VIServer -Scope Global
set-alias Get-ESX Connect-VIServer -Scope Global
set-alias Answer-VMQuestion Set-VMQuestion -Scope Global
set-alias Get-PowerCLIDocumentation Get-PowerCLIHelp -Scope Global
set-alias Get-VIToolkitVersion Get-PowerCLIVersion -Scope Global
set-alias Get-VIToolkitConfiguration Get-PowerCLIConfiguration -Scope Global
set-alias Set-VIToolkitConfiguration Set-PowerCLIConfiguration -Scope Global
set-alias Export-VM Export-VApp -Scope Global
set-alias Apply-VMHostProfile Invoke-VMHostProfile -Scope Global
set-alias Apply-DrsRecommendation Invoke-DrsRecommendation -Scope Global
set-alias Shutdown-VMGuest Stop-VMGuest -Scope Global

# Uid utilities
$global:UidUtil = [VMware.VimAutomation.ViCore.Cmdlets.Utilities.UidUtil]::Create()
add-member -inputobject $global:UidUtil -membertype scriptmethod -name GetHelp -Value { Get-Help about_uid }

HookGetViewAutoCompleter

# SIG # Begin signature block
# MIIpvgYJKoZIhvcNAQcCoIIprzCCKasCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCA2fC9biw+ryDuO
# cdawFRkNnkDBo77quqDjiqI5am/llKCCDnQwggawMIIEmKADAgECAhAIrUCyYNKc
# TJ9ezam9k67ZMA0GCSqGSIb3DQEBDAUAMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQK
# EwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNV
# BAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDAeFw0yMTA0MjkwMDAwMDBaFw0z
# NjA0MjgyMzU5NTlaMGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwg
# SW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBDb2RlIFNpZ25pbmcg
# UlNBNDA5NiBTSEEzODQgMjAyMSBDQTEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAw
# ggIKAoICAQDVtC9C0CiteLdd1TlZG7GIQvUzjOs9gZdwxbvEhSYwn6SOaNhc9es0
# JAfhS0/TeEP0F9ce2vnS1WcaUk8OoVf8iJnBkcyBAz5NcCRks43iCH00fUyAVxJr
# Q5qZ8sU7H/Lvy0daE6ZMswEgJfMQ04uy+wjwiuCdCcBlp/qYgEk1hz1RGeiQIXhF
# LqGfLOEYwhrMxe6TSXBCMo/7xuoc82VokaJNTIIRSFJo3hC9FFdd6BgTZcV/sk+F
# LEikVoQ11vkunKoAFdE3/hoGlMJ8yOobMubKwvSnowMOdKWvObarYBLj6Na59zHh
# 3K3kGKDYwSNHR7OhD26jq22YBoMbt2pnLdK9RBqSEIGPsDsJ18ebMlrC/2pgVItJ
# wZPt4bRc4G/rJvmM1bL5OBDm6s6R9b7T+2+TYTRcvJNFKIM2KmYoX7BzzosmJQay
# g9Rc9hUZTO1i4F4z8ujo7AqnsAMrkbI2eb73rQgedaZlzLvjSFDzd5Ea/ttQokbI
# YViY9XwCFjyDKK05huzUtw1T0PhH5nUwjewwk3YUpltLXXRhTT8SkXbev1jLchAp
# QfDVxW0mdmgRQRNYmtwmKwH0iU1Z23jPgUo+QEdfyYFQc4UQIyFZYIpkVMHMIRro
# OBl8ZhzNeDhFMJlP/2NPTLuqDQhTQXxYPUez+rbsjDIJAsxsPAxWEQIDAQABo4IB
# WTCCAVUwEgYDVR0TAQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQUaDfg67Y7+F8Rhvv+
# YXsIiGX0TkIwHwYDVR0jBBgwFoAU7NfjgtJxXWRM3y5nP+e6mK4cD08wDgYDVR0P
# AQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMDMHcGCCsGAQUFBwEBBGswaTAk
# BggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEEGCCsGAQUFBzAC
# hjVodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9v
# dEc0LmNydDBDBgNVHR8EPDA6MDigNqA0hjJodHRwOi8vY3JsMy5kaWdpY2VydC5j
# b20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNybDAcBgNVHSAEFTATMAcGBWeBDAED
# MAgGBmeBDAEEATANBgkqhkiG9w0BAQwFAAOCAgEAOiNEPY0Idu6PvDqZ01bgAhql
# +Eg08yy25nRm95RysQDKr2wwJxMSnpBEn0v9nqN8JtU3vDpdSG2V1T9J9Ce7FoFF
# UP2cvbaF4HZ+N3HLIvdaqpDP9ZNq4+sg0dVQeYiaiorBtr2hSBh+3NiAGhEZGM1h
# mYFW9snjdufE5BtfQ/g+lP92OT2e1JnPSt0o618moZVYSNUa/tcnP/2Q0XaG3Ryw
# YFzzDaju4ImhvTnhOE7abrs2nfvlIVNaw8rpavGiPttDuDPITzgUkpn13c5Ubdld
# AhQfQDN8A+KVssIhdXNSy0bYxDQcoqVLjc1vdjcshT8azibpGL6QB7BDf5WIIIJw
# 8MzK7/0pNVwfiThV9zeKiwmhywvpMRr/LhlcOXHhvpynCgbWJme3kuZOX956rEnP
# LqR0kq3bPKSchh/jwVYbKyP/j7XqiHtwa+aguv06P0WmxOgWkVKLQcBIhEuWTatE
# QOON8BUozu3xGFYHKi8QxAwIZDwzj64ojDzLj4gLDb879M4ee47vtevLt/B3E+bn
# KD+sEq6lLyJsQfmCXBVmzGwOysWGw/YmMwwHS6DTBwJqakAwSEs0qFEgu60bhQji
# WQ1tygVQK+pKHJ6l/aCnHwZ05/LWUpD9r4VIIflXO7ScA+2GRfS0YW6/aOImYIbq
# yK+p/pQd52MbOoZWeE4wgge8MIIFpKADAgECAhAGQAJb/wxIlzKZ1GMgg8N7MA0G
# CSqGSIb3DQEBCwUAMGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwg
# SW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBDb2RlIFNpZ25pbmcg
# UlNBNDA5NiBTSEEzODQgMjAyMSBDQTEwHhcNMjQwMzI4MDAwMDAwWhcNMjcwMzMw
# MjM1OTU5WjCBxDETMBEGCysGAQQBgjc8AgEDEwJVUzEZMBcGCysGAQQBgjc8AgEC
# EwhEZWxhd2FyZTEdMBsGA1UEDwwUUHJpdmF0ZSBPcmdhbml6YXRpb24xEDAOBgNV
# BAUTBzY2MTAxMTcxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpDYWxpZm9ybmlhMREw
# DwYDVQQHEwhTYW4gSm9zZTEVMBMGA1UEChMMQnJvYWRjb20gSW5jMRUwEwYDVQQD
# EwxCcm9hZGNvbSBJbmMwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC6
# 8C+jJxKfxp9c1A6fghwSNjnvV+Y1my2XmTHEPmk7COFTWw1VRBZBtv/zUXrSStlW
# 9Qqqp48wk+H+H5oM0qL9jsUQ6wAJpmjt33F3xvKqc8ehzVZLXUEACQBXTo30Hnbh
# bcacKAyX9sGByGqKlR6cHHrEebSWMoxOO6TOgYg06xfeYzxpx8HqMQjOKgNEbh4c
# m1Yx+ER/4BmWmYcvVHR9KtXwJWxmzUJCaS5OB9lp8JqO5+uAHvpGtQEAb39/h/vy
# 290isCYw16/uaLOz5Epchv5fogTBTh4o6SXWHam03FfMNVbmbMVuciTzfPSDt0i5
# xQWYtVkwVU+NGE4XUutX4zbaing53QYKNAa+NW9FiWcaoEwE1qTvk7ilsucPzdqC
# ikQpHyaaGCzHoDhveSLiJKgKRiDqee8KXfa/hkCoat9AtCihyd899kJ1kSlTO9fk
# ci5/CdKwmwXQIKh6OPueKr+OJ69XPx0V+RaaMAkkVtFb7/VwecFmFgsXFkAK8ulP
# aGYyIFOFqLMqH8ZuKiLVP5HkxDgSitJcWbaSf89TJuxNqh0vV1k4iwaQpcmQZhPK
# 49pNlj5j0cyw8B+xTYNDwnKvyoWgqKAb2cfzc6pCLk2GJLBwakKZ5YKC50XdhPlS
# yrqlLTb5otZRoYWFGKL1SqxxrBjRqg4qp1RvuxRcBQIDAQABo4ICAjCCAf4wHwYD
# VR0jBBgwFoAUaDfg67Y7+F8Rhvv+YXsIiGX0TkIwHQYDVR0OBBYEFL9ZTMS/Phgv
# GnXZm3XOrmDoJSIfMD0GA1UdIAQ2MDQwMgYFZ4EMAQMwKTAnBggrBgEFBQcCARYb
# aHR0cDovL3d3dy5kaWdpY2VydC5jb20vQ1BTMA4GA1UdDwEB/wQEAwIHgDATBgNV
# HSUEDDAKBggrBgEFBQcDAzCBtQYDVR0fBIGtMIGqMFOgUaBPhk1odHRwOi8vY3Js
# My5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRDb2RlU2lnbmluZ1JTQTQw
# OTZTSEEzODQyMDIxQ0ExLmNybDBToFGgT4ZNaHR0cDovL2NybDQuZGlnaWNlcnQu
# Y29tL0RpZ2lDZXJ0VHJ1c3RlZEc0Q29kZVNpZ25pbmdSU0E0MDk2U0hBMzg0MjAy
# MUNBMS5jcmwwgZQGCCsGAQUFBwEBBIGHMIGEMCQGCCsGAQUFBzABhhhodHRwOi8v
# b2NzcC5kaWdpY2VydC5jb20wXAYIKwYBBQUHMAKGUGh0dHA6Ly9jYWNlcnRzLmRp
# Z2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNENvZGVTaWduaW5nUlNBNDA5NlNI
# QTM4NDIwMjFDQTEuY3J0MAkGA1UdEwQCMAAwDQYJKoZIhvcNAQELBQADggIBAMLk
# M/5BZB1j2xjjR9IkyDYtLrqS9IztErzl4ogf2dXuAgBJP1EKm/EN4oOi/BHxLW0T
# VuclGZ3aEa3/n3UlHxqmvKm+4elD5oh4sEOm7+J7ECV0HobeZhRiLmdyla1Mqbxw
# xp56AVvhG/++nf+AVzw95c671a3kb+6VXMDzZK1qcUh6zyLklZ/vfjKipry9KgMR
# sXd81I+PRr+99iRI+5pUsF7ixmS4vTldNh2r/VRFKLtXtTefZ20Q55Efu/8NefJf
# fD/+LLmHszB3LRlguFYOUGon7q8eQKi20PMW6PQb8az4mn6MfA1Y2x+L7HFDiy//
# VMOy5DqcKOHWqz/NZr7/VEPtywoLbHlUwNJyFY0wnQhzvPCg67YpDEYERDnggtpe
# OchKlJoqLKQInq6xDLTtco+ynR6IHnWRcz+oYhm6TdvRcmP7giiqObKEFXQwLsjS
# HsqRluk2FQ4DhG63+8gyD4rKQVoybP0obE7Gi2RYHOT0qwPos6GklZraht/capa7
# wos1gNKXJL7G6BaCXQWCyakT76ZOJOdHzHjJ2n+yBgKWWGBv186nrP5nfuRu0vJE
# HG74cy5oRwe3vme6ztPQy9VSgSrP+g67bZ6yPe+z09T7NczW4aXrXbMUdTb02zKQ
# sK8WEKfcvzBmZ115SwMuf3g34C5yRhOsWInfosmAMYIaoDCCGpwCAQEwfTBpMQsw
# CQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xQTA/BgNVBAMTOERp
# Z2lDZXJ0IFRydXN0ZWQgRzQgQ29kZSBTaWduaW5nIFJTQTQwOTYgU0hBMzg0IDIw
# MjEgQ0ExAhAGQAJb/wxIlzKZ1GMgg8N7MA0GCWCGSAFlAwQCAQUAoHwwEAYKKwYB
# BAGCNwIBDDECMAAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGC
# NwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEICCcKguw84PyRxCg
# Z3p0JL3fx7LVXC3Tmc7M0S9bD0gLMA0GCSqGSIb3DQEBAQUABIICAKtA+kk7xZb9
# hY9yX9MnjOXK8+GcxEM269HAgFcPfUf8m1Ul/HZ+9hBkvsFpwzEyuK+kzSNt9DdJ
# HEYvM5sWYxC/IM5iHJVKGUI6KYxGpMh1XJiQ23A4SCiUdurZb5uyRD0+GFfHxsKl
# 5VbQZ9vCFvVKpAqqBsTC+7hnvxq9+/7cXPXMTRjMfbF2QB4Y0ECM/nBDMj1NRQRz
# Z5EdvuPmlU9iYdB+H7yHY/SyFka5CbX8EnQMMrdpMGQJsHOKd7EuYdK3uk6ZKy0y
# 80XeJ3Tngrb+UjzdL0eU7FbuDRkDOAwWAfnNlYDtDf9i6f/DITm1RYlCmMEWfwWY
# orRyY+hx27JUtR3Q2OVN8+exfyA3VY8E1ldfpjHg8320KDl7p8kSyL0vbusOBsLN
# 4dyDeTnlz8atldPKHlWmBz+VbTG1tFJJd8oojO3s8c1DwrB0PV9bHSOEsdeHz+sK
# 0ddhOOa9pBiiYkYpTRNkXOTsd/Cvsjl4hewXFeKAqw5hnRTWf9i3Z8pdN6/BjSH5
# C7fk+2J/ioXuiBzNYj2UziKi5uJuwP2vzEl7anQWrzy+H6fegnCA/y3v9tq1h5aC
# 4mPU34fu9hLytK6ibEWQAwEyCDOLyabRz6YwXWfIOc6CBITlkAyT9Nxp30umMEgI
# r2S0x9nXVIJhEq1qVb6DZIhBDtgtO1r+oYIXdjCCF3IGCisGAQQBgjcDAwExghdi
# MIIXXgYJKoZIhvcNAQcCoIIXTzCCF0sCAQMxDzANBglghkgBZQMEAgEFADB3Bgsq
# hkiG9w0BCRABBKBoBGYwZAIBAQYJYIZIAYb9bAcBMDEwDQYJYIZIAWUDBAIBBQAE
# IAmNuWX2NFa3jkdADswqEWoomLCJPcu0OprrA8CRO4s1AhBOcnwOGiSLYhjtnxi0
# jqI3GA8yMDI2MDgzMTEzNTgzN1qgghM6MIIG7TCCBNWgAwIBAgIQCoDvGEuN8QWC
# 0cR2p5V0aDANBgkqhkiG9w0BAQsFADBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMO
# RGlnaUNlcnQsIEluYy4xQTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgVGlt
# ZVN0YW1waW5nIFJTQTQwOTYgU0hBMjU2IDIwMjUgQ0ExMB4XDTI1MDYwNDAwMDAw
# MFoXDTM2MDkwMzIzNTk1OVowYzELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lD
# ZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBTSEEyNTYgUlNBNDA5NiBUaW1l
# c3RhbXAgUmVzcG9uZGVyIDIwMjUgMTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCC
# AgoCggIBANBGrC0Sxp7Q6q5gVrMrV7pvUf+GcAoB38o3zBlCMGMyqJnfFNZx+wvA
# 69HFTBdwbHwBSOeLpvPnZ8ZN+vo8dE2/pPvOx/Vj8TchTySA2R4QKpVD7dvNZh6w
# W2R6kSu9RJt/4QhguSssp3qome7MrxVyfQO9sMx6ZAWjFDYOzDi8SOhPUWlLnh00
# Cll8pjrUcCV3K3E0zz09ldQ//nBZZREr4h/GI6Dxb2UoyrN0ijtUDVHRXdmncOOM
# A3CoB/iUSROUINDT98oksouTMYFOnHoRh6+86Ltc5zjPKHW5KqCvpSduSwhwUmot
# uQhcg9tw2YD3w6ySSSu+3qU8DD+nigNJFmt6LAHvH3KSuNLoZLc1Hf2JNMVL4Q1O
# pbybpMe46YceNA0LfNsnqcnpJeItK/DhKbPxTTuGoX7wJNdoRORVbPR1VVnDuSeH
# VZlc4seAO+6d2sC26/PQPdP51ho1zBp+xUIZkpSFA8vWdoUoHLWnqWU3dCCyFG1r
# oSrgHjSHlq8xymLnjCbSLZ49kPmk8iyyizNDIXj//cOgrY7rlRyTlaCCfw7aSURO
# wnu7zER6EaJ+AliL7ojTdS5PWPsWeupWs7NpChUk555K096V1hE0yZIXe+giAwW0
# 0aHzrDchIc2bQhpp0IoKRR7YufAkprxMiXAJQ1XCmnCfgPf8+3mnAgMBAAGjggGV
# MIIBkTAMBgNVHRMBAf8EAjAAMB0GA1UdDgQWBBTkO/zyMe39/dfzkXFjGVBDz2GM
# 6DAfBgNVHSMEGDAWgBTvb1NK6eQGfHrK4pBW9i/USezLTjAOBgNVHQ8BAf8EBAMC
# B4AwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwgZUGCCsGAQUFBwEBBIGIMIGFMCQG
# CCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wXQYIKwYBBQUHMAKG
# UWh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNFRp
# bWVTdGFtcGluZ1JTQTQwOTZTSEEyNTYyMDI1Q0ExLmNydDBfBgNVHR8EWDBWMFSg
# UqBQhk5odHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRU
# aW1lU3RhbXBpbmdSU0E0MDk2U0hBMjU2MjAyNUNBMS5jcmwwIAYDVR0gBBkwFzAI
# BgZngQwBBAIwCwYJYIZIAYb9bAcBMA0GCSqGSIb3DQEBCwUAA4ICAQBlKq3xHCcE
# ua5gQezRCESeY0ByIfjk9iJP2zWLpQq1b4URGnwWBdEZD9gBq9fNaNmFj6Eh8/Ym
# RDfxT7C0k8FUFqNh+tshgb4O6Lgjg8K8elC4+oWCqnU/ML9lFfim8/9yJmZSe2F8
# AQ/UdKFOtj7YMTmqPO9mzskgiC3QYIUP2S3HQvHG1FDu+WUqW4daIqToXFE/JQ/E
# ABgfZXLWU0ziTN6R3ygQBHMUBaB5bdrPbF6MRYs03h4obEMnxYOX8VBRKe1uNnzQ
# VTeLni2nHkX/QqvXnNb+YkDFkxUGtMTaiLR9wjxUxu2hECZpqyU1d0IbX6Wq8/gV
# utDojBIFeRlqAcuEVT0cKsb+zJNEsuEB7O7/cuvTQasnM9AWcIQfVjnzrvwiCZ85
# EE8LUkqRhoS3Y50OHgaY7T/lwd6UArb+BOVAkg2oOvol/DJgddJ35XTxfUlQ+8Hg
# gt8l2Yv7roancJIFcbojBcxlRcGG0LIhp6GvReQGgMgYxQbV1S3CrWqZzBt1R9xJ
# gKf47CdxVRd/ndUlQ05oxYy2zRWVFjF7mcr4C34Mj3ocCVccAvlKV9jEnstrniLv
# UxxVZE/rptb7IRE2lskKPIJgbaP5t2nGj/ULLi49xTcBZU8atufk+EMF/cWuiC7P
# OGT75qaL6vdCvHlshtjdNXOCIUjsarfNZzCCBrQwggScoAMCAQICEA3HrFcF/yGZ
# LkBDIgw6SYYwDQYJKoZIhvcNAQELBQAwYjELMAkGA1UEBhMCVVMxFTATBgNVBAoT
# DERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEhMB8GA1UE
# AxMYRGlnaUNlcnQgVHJ1c3RlZCBSb290IEc0MB4XDTI1MDUwNzAwMDAwMFoXDTM4
# MDExNDIzNTk1OVowaTELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJ
# bmMuMUEwPwYDVQQDEzhEaWdpQ2VydCBUcnVzdGVkIEc0IFRpbWVTdGFtcGluZyBS
# U0E0MDk2IFNIQTI1NiAyMDI1IENBMTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCC
# AgoCggIBALR4MdMKmEFyvjxGwBysddujRmh0tFEXnU2tjQ2UtZmWgyxU7UNqEY81
# FzJsQqr5G7A6c+Gh/qm8Xi4aPCOo2N8S9SLrC6Kbltqn7SWCWgzbNfiR+2fkHUil
# jNOqnIVD/gG3SYDEAd4dg2dDGpeZGKe+42DFUF0mR/vtLa4+gKPsYfwEu7EEbkC9
# +0F2w4QJLVSTEG8yAR2CQWIM1iI5PHg62IVwxKSpO0XaF9DPfNBKS7Zazch8NF5v
# p7eaZ2CVNxpqumzTCNSOxm+SAWSuIr21Qomb+zzQWKhxKTVVgtmUPAW35xUUFREm
# DrMxSNlr/NsJyUXzdtFUUt4aS4CEeIY8y9IaaGBpPNXKFifinT7zL2gdFpBP9qh8
# SdLnEut/GcalNeJQ55IuwnKCgs+nrpuQNfVmUB5KlCX3ZA4x5HHKS+rqBvKWxdCy
# QEEGcbLe1b8Aw4wJkhU1JrPsFfxW1gaou30yZ46t4Y9F20HHfIY4/6vHespYMQmU
# iote8ladjS/nJ0+k6MvqzfpzPDOy5y6gqztiT96Fv/9bH7mQyogxG9QEPHrPV6/7
# umw052AkyiLA6tQbZl1KhBtTasySkuJDpsZGKdlsjg4u70EwgWbVRSX1Wd4+zoFp
# p4Ra+MlKM2baoD6x0VR4RjSpWM8o5a6D8bpfm4CLKczsG7ZrIGNTAgMBAAGjggFd
# MIIBWTASBgNVHRMBAf8ECDAGAQH/AgEAMB0GA1UdDgQWBBTvb1NK6eQGfHrK4pBW
# 9i/USezLTjAfBgNVHSMEGDAWgBTs1+OC0nFdZEzfLmc/57qYrhwPTzAOBgNVHQ8B
# Af8EBAMCAYYwEwYDVR0lBAwwCgYIKwYBBQUHAwgwdwYIKwYBBQUHAQEEazBpMCQG
# CCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wQQYIKwYBBQUHMAKG
# NWh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRSb290
# RzQuY3J0MEMGA1UdHwQ8MDowOKA2oDSGMmh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNv
# bS9EaWdpQ2VydFRydXN0ZWRSb290RzQuY3JsMCAGA1UdIAQZMBcwCAYGZ4EMAQQC
# MAsGCWCGSAGG/WwHATANBgkqhkiG9w0BAQsFAAOCAgEAF877FoAc/gc9EXZxML2+
# C8i1NKZ/zdCHxYgaMH9Pw5tcBnPw6O6FTGNpoV2V4wzSUGvI9NAzaoQk97frPBtI
# j+ZLzdp+yXdhOP4hCFATuNT+ReOPK0mCefSG+tXqGpYZ3essBS3q8nL2UwM+NMvE
# uBd/2vmdYxDCvwzJv2sRUoKEfJ+nN57mQfQXwcAEGCvRR2qKtntujB71WPYAgwPy
# WLKu6RnaID/B0ba2H3LUiwDRAXx1Neq9ydOal95CHfmTnM4I+ZI2rVQfjXQA1WSj
# jf4J2a7jLzWGNqNX+DF0SQzHU0pTi4dBwp9nEC8EAqoxW6q17r0z0noDjs6+BFo+
# z7bKSBwZXTRNivYuve3L2oiKNqetRHdqfMTCW/NmKLJ9M+MtucVGyOxiDf06VXxy
# KkOirv6o02OoXN4bFzK0vlNMsvhlqgF2puE6FndlENSmE+9JGYxOGLS/D284NHNb
# oDGcmWXfwXRy4kbu4QFhOm0xJuF2EZAOk5eCkhSxZON3rGlHqhpB/8MluDezooIs
# 8CVnrpHMiD2wL40mm53+/j7tFaxYKIqL0Q4ssd8xHZnIn/7GELH3IdvG2XlM9q7W
# P/UwgOkw/HQtyRN62JK4S1C8uw3PdBunvAZapsiI5YKdvlarEvf8EA+8hcpSM9LH
# JmyrxaFtoza2zNaQ9k+5t1wwggWNMIIEdaADAgECAhAOmxiO+dAt5+/bUOIIQBha
# MA0GCSqGSIb3DQEBDAUAMGUxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2Vy
# dCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xJDAiBgNVBAMTG0RpZ2lD
# ZXJ0IEFzc3VyZWQgSUQgUm9vdCBDQTAeFw0yMjA4MDEwMDAwMDBaFw0zMTExMDky
# MzU5NTlaMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAX
# BgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0IFRydXN0
# ZWQgUm9vdCBHNDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAL/mkHNo
# 3rvkXUo8MCIwaTPswqclLskhPfKK2FnC4SmnPVirdprNrnsbhA3EMB/zG6Q4FutW
# xpdtHauyefLKEdLkX9YFPFIPUh/GnhWlfr6fqVcWWVVyr2iTcMKyunWZanMylNEQ
# RBAu34LzB4TmdDttceItDBvuINXJIB1jKS3O7F5OyJP4IWGbNOsFxl7sWxq868nP
# zaw0QF+xembud8hIqGZXV59UWI4MK7dPpzDZVu7Ke13jrclPXuU15zHL2pNe3I6P
# gNq2kZhAkHnDeMe2scS1ahg4AxCN2NQ3pC4FfYj1gj4QkXCrVYJBMtfbBHMqbpEB
# fCFM1LyuGwN1XXhm2ToxRJozQL8I11pJpMLmqaBn3aQnvKFPObURWBf3JFxGj2T3
# wWmIdph2PVldQnaHiZdpekjw4KISG2aadMreSx7nDmOu5tTvkpI6nj3cAORFJYm2
# mkQZK37AlLTSYW3rM9nF30sEAMx9HJXDj/chsrIRt7t/8tWMcCxBYKqxYxhElRp2
# Yn72gLD76GSmM9GJB+G9t+ZDpBi4pncB4Q+UDCEdslQpJYls5Q5SUUd0viastkF1
# 3nqsX40/ybzTQRESW+UQUOsxxcpyFiIJ33xMdT9j7CFfxCBRa2+xq4aLT8LWRV+d
# IPyhHsXAj6KxfgommfXkaS+YHS312amyHeUbAgMBAAGjggE6MIIBNjAPBgNVHRMB
# Af8EBTADAQH/MB0GA1UdDgQWBBTs1+OC0nFdZEzfLmc/57qYrhwPTzAfBgNVHSME
# GDAWgBRF66Kv9JLLgjEtUYunpyGd823IDzAOBgNVHQ8BAf8EBAMCAYYweQYIKwYB
# BQUHAQEEbTBrMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20w
# QwYIKwYBBQUHMAKGN2h0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2Vy
# dEFzc3VyZWRJRFJvb3RDQS5jcnQwRQYDVR0fBD4wPDA6oDigNoY0aHR0cDovL2Ny
# bDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENBLmNybDARBgNV
# HSAECjAIMAYGBFUdIAAwDQYJKoZIhvcNAQEMBQADggEBAHCgv0NcVec4X6CjdBs9
# thbX979XB72arKGHLOyFXqkauyL4hxppVCLtpIh3bb0aFPQTSnovLbc47/T/gLn4
# offyct4kvFIDyE7QKt76LVbP+fT3rDB6mouyXtTP0UNEm0Mh65ZyoUi0mcudT6cG
# AxN3J0TU53/oWajwvy8LpunyNDzs9wPHh6jSTEAZNUZqaVSwuKFWjuyk1T3osdz9
# HNj0d1pcVIxv76FQPfx2CWiEn2/K2yCNNWAcAgPLILCsWKAOQGPFmCLBsln1VWvP
# J6tsds5vIy30fnFqI2si/xK4VC0nftg62fC2h5b9W9FcrBjDTZ9ztwGpn1eqXiji
# uZQxggN8MIIDeAIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2Vy
# dCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1lU3RhbXBp
# bmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEFgtHEdqeVdGgwDQYJ
# YIZIAWUDBAIBBQCggdEwGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMBwGCSqG
# SIb3DQEJBTEPFw0yNjA4MzExMzU4MzdaMCsGCyqGSIb3DQEJEAIMMRwwGjAYMBYE
# FN1iMKyGCi0wa9o4sWh5UjAH+0F+MC8GCSqGSIb3DQEJBDEiBCBsj2LSwZ3xGENb
# 3u7wfW4qdYum7lTN4PK9E67IckThujA3BgsqhkiG9w0BCRACLzEoMCYwJDAiBCBK
# oD+iLNdchMVck4+CjmdrnK7Ksz/jbSaaozTxRhEKMzANBgkqhkiG9w0BAQEFAASC
# AgB1rOGMmnUAbgzRdUIucJd/dUBbwxmnVYRq5eFP8ISBi6+uEx+DlhzFIE3wzHs5
# mKtPmBIQqDyy7KWpYFIZ2Ew6oiuDnO1SbWHWaNpShB0Ft2kqNblyls5e8iXRBYNZ
# 8RSSIonALRbJzNsVORRSDZes/ZY+mf1dBAAlXMAOmaf59Go6/PAdrYFoFzeSnySz
# 06MBtSPdEopS3gvHtlgGCk+H6auQ7P15sMthqmwkmFh0J5plgKIhncjfeIbKbH6Y
# yDKYEFg+YNHApXRYWvFZGAxFPj0TXj0ax68u9CPlzGx3LMcbaVCjvMspDqYTMkmn
# v1lFwcaN4SeHjH1a339owr0LQVeHifRgsuXLAHZ4vC4z/TieD+JV5RNMxfgPez4d
# 06M46zLn+fcLddJHbAUvAIm13Cfi0NMxxMLstlAddakn9yu2NCnWFXxyHZ1Ik93l
# YhbHZAaBz5aQ8aJxTF8MKOrhffzJMnwvQ1FJT3zpTSOvsUaawliPa5cchCmqYxrH
# sVqwKDfzsxu0/37oo4O83EWQkY/TzjIycCB2cbtWrBRVm6/GVor1Jq6QhcPiVrPB
# DejUrMXddBgtaamiRbCJslh/D8muUQI+Vs7FCwm+3Q9G4e8d+mKB8zeGSeACWIaa
# EXgkYCqhs4BlI98UKEbr/fAOCsl3oobZdjnm51MpdM64Yg==
# SIG # End signature block
