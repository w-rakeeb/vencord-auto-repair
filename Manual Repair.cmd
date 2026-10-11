@echo off
setlocal DisableDelayedExpansion
title Vencord Manual Repair
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup.ps1" -Action Manual
if errorlevel 1 echo Manual repair could not be started. Read the error above.
echo.
pause
