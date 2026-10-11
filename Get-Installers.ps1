#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
Initialize-RepairPaths
$directory = Join-Path $PSScriptRoot 'Installers'
[void][IO.Directory]::CreateDirectory($directory)
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
foreach ($file in @(
    @{Name='VencordInstallerCli.exe'; Hash=$script:CliHash},
    @{Name='VencordInstaller.exe'; Hash=$script:GuiHash}
)) {
    $target = Join-Path $directory $file.Name
    if ((Test-Path -LiteralPath $target) -and (Get-FileHash -LiteralPath $target).Hash -eq $file.Hash) { continue }
    $download = $target + '.download'
    try {
        Invoke-WebRequest -Uri ('https://github.com/Vencord/Installer/releases/download/v1.4.0/' + $file.Name) -OutFile $download -UseBasicParsing -TimeoutSec 90
        Test-OfficialBinary $download $file.Hash
        Move-Item -LiteralPath $download -Destination $target -Force
    } finally { Remove-Item -LiteralPath $download -Force -ErrorAction SilentlyContinue }
}
$source = Join-Path $directory 'VencordInstaller-source-8ca86e5.zip'
if (-not (Test-Path -LiteralPath $source)) {
    Invoke-WebRequest -Uri 'https://codeload.github.com/Vencord/Installer/zip/8ca86e5' -OutFile $source -UseBasicParsing -TimeoutSec 90
}
Write-Host 'Official installer binaries verified.'
