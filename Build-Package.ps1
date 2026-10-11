#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'Get-Installers.ps1')
$dist = Join-Path $PSScriptRoot 'dist'
$stage = Join-Path $dist ('stage-' + [Guid]::NewGuid().ToString('N'))
$package = Join-Path $stage 'Vencord Auto Repair'
[void][IO.Directory]::CreateDirectory((Join-Path $package 'Installers'))
[void][IO.Directory]::CreateDirectory((Join-Path $package 'docs'))
foreach ($name in @('Common.ps1','Setup.ps1','Watcher.ps1','Enable Auto-Repair.cmd','Disable Auto-Repair.cmd','Check Status.cmd','Manual Repair.cmd','README.md','LICENSE')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $package
}
foreach ($name in @('VencordInstallerCli.exe','VencordInstaller.exe','VencordInstaller-source-8ca86e5.zip','LICENSE-Vencord.txt','SOURCES.txt','checksums.sha256')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('Installers\' + $name)) -Destination (Join-Path $package 'Installers')
}
Copy-Item -LiteralPath (Join-Path $package 'Installers\VencordInstaller.exe') -Destination $package
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'docs\testing.md') -Destination (Join-Path $package 'docs')
$archive = Join-Path $dist 'Vencord-Auto-Repair-Windows.zip'
Compress-Archive -LiteralPath $package -DestinationPath $archive -Force
Write-Host ('Package: ' + $archive)
