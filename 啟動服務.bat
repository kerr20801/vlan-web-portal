@echo off
title VMware VLAN Web Portal
echo ========================================================
echo  Starting VMware VLAN Web Portal...
echo  Please wait, opening browser: http://localhost:8899/
echo ========================================================
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0server.ps1"
pause
