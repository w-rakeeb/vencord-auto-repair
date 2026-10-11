@echo off
setlocal DisableDelayedExpansion
title Disable Vencord Auto-Repair
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup.ps1" -Action Disable
if errorlevel 1 echo Disable did not complete. Read the error above.
echo.
pause
