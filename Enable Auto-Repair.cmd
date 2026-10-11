@echo off
setlocal DisableDelayedExpansion
title Enable Vencord Auto-Repair
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup.ps1" -Action Enable
if errorlevel 1 echo Enable did not complete. Read the error above.
echo.
pause
