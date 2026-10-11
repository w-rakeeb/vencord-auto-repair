@echo off
setlocal DisableDelayedExpansion
title Vencord Auto-Repair Status
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup.ps1" -Action Status
echo.
pause
