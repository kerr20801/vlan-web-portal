@echo off
title Download VMware Portable Modules
echo ========================================================
echo  Downloading VMware PowerCLI portable modules...
echo  This may take 1-2 minutes depending on your internet.
echo ========================================================
powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null }; New-Item -ItemType Directory -Force -Path '%~dp0Modules' | Out-Null; Save-Module -Name VMware.VimAutomation.Core -Path '%~dp0Modules' -Force; Write-Host 'Download complete!' -ForegroundColor Green"
pause
