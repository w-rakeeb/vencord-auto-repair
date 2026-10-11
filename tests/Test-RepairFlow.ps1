#requires -Version 5.1
param([string] $PackageRoot = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference = 'Stop'
. (Join-Path $PackageRoot 'Common.ps1')
$passed = 0
function Assert-True($Value, [string] $Message) {
    if (-not $Value) { throw ('FAIL: ' + $Message) }
    $script:passed++
    Write-Output ('PASS: ' + $Message)
}
$fixture = Join-Path $PSScriptRoot ('repair-flow-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
$env:LOCALAPPDATA = Join-Path $fixture 'Local'
$env:APPDATA = Join-Path $fixture 'Roaming'
$env:VENCORD_USER_DATA_DIR = Join-Path $fixture ('Runtime ' + [char]0x00e9 + [char]0x09ac)
$env:DISCORD_USER_DATA_DIR = $null
$env:VENCORD_DEV_INSTALL = $null
Initialize-RepairPaths
[void][IO.Directory]::CreateDirectory((Join-Path $script:StateDirectory 'Installers'))
Copy-Item -LiteralPath (Join-Path $PackageRoot 'Installers\VencordInstallerCli.exe') -Destination (Join-Path $script:StateDirectory 'Installers\VencordInstallerCli.exe')
[IO.File]::WriteAllText($script:EnabledFile, 'test')
$root = Join-Path $env:LOCALAPPDATA 'DiscordCanary'
$appDir = Join-Path $root 'app-1.0.9999'
[void][IO.Directory]::CreateDirectory((Join-Path $appDir 'resources'))
# A unique process name ensures the user's existing watcher will not touch it.
$client = [pscustomobject]@{ Name = 'VencordRepairFixture'; Branch = 'canary'; Root = $root }
$exe = Join-Path $appDir 'VencordRepairFixture.exe'
Add-Type -TypeDefinition 'public class RepairFixture { public static void Main() { System.Threading.Thread.Sleep(240000); } }' -OutputAssembly $exe -OutputType ConsoleApplication
$asar = Join-Path $appDir 'resources\app.asar'
$backup = Join-Path $appDir 'resources\_app.asar'
[IO.File]::WriteAllText($asar, 'ORIGINAL TEST ARCHIVE - NOT A REAL DISCORD INSTALLATION')
$originalHash = (Get-FileHash -LiteralPath $asar).Hash
$originalNetwork = (Get-Item Function:\Test-RepairNetwork).ScriptBlock
$originalRunner = (Get-Item Function:\Invoke-ExternalProgram).ScriptBlock
$testProcess = $null
try {
    $testProcess = Start-Process -FilePath $exe -WindowStyle Hidden -PassThru
    Start-Sleep -Milliseconds 300
    Assert-True (@(Get-ClientProcesses $client).Count -eq 1) 'Only fixture process selected for repair'
    function Test-RepairNetwork { throw 'Simulated network outage' }
    $failed = $false
    try { Invoke-ClientRepair $client } catch { $failed = $true }
    $testProcess.Refresh()
    Assert-True ($failed -and -not $testProcess.HasExited) 'Network failure leaves running client open'
    function Test-RepairNetwork { }
    function Invoke-ExternalProgram { param($FilePath, $Arguments); [pscustomobject]@{ExitCode=7;Stdout='';Stderr='simulated error'} }
    $failed = $false
    try { Invoke-ClientRepair $client } catch { $failed = $_.Exception.Message.Contains('exit code 7') }
    Start-Sleep -Milliseconds 300
    Assert-True ($failed -and @(Get-ClientProcesses $client).Count -eq 1) 'Installer failure reported and fixture reopened'
    function Invoke-ExternalProgram { param($FilePath, $Arguments); [pscustomobject]@{ExitCode=0;Stdout='Success';Stderr=''} }
    $failed = $false
    try { Invoke-ClientRepair $client } catch { $failed = $_.Exception.Message.Contains('did not restore') }
    Start-Sleep -Milliseconds 300
    Assert-True ($failed -and @(Get-ClientProcesses $client).Count -eq 1) 'Exit zero without patch is rejected and fixture reopened'
    function Invoke-ExternalProgram { param($FilePath, $Arguments); throw 'Simulated installer timeout' }
    $failed = $false
    try { Invoke-ClientRepair $client } catch { $failed = $true }
    Start-Sleep -Milliseconds 300
    Assert-True ($failed -and @(Get-ClientProcesses $client).Count -eq 1) 'Timeout path reopens fixture'
    Set-Item Function:\Test-RepairNetwork $originalNetwork
    Set-Item Function:\Invoke-ExternalProgram $originalRunner
    # The official CLI identifies a branch by folder name and kills by branch.
    # Never run this fixture repair if a real Canary client is open.
    if (@(Get-Process -Name DiscordCanary -ErrorAction SilentlyContinue).Count -gt 0) {
        throw 'Real Canary is running; the official fixture repair was deliberately not started.'
    }
    Invoke-ClientRepair $client
    Start-Sleep -Milliseconds 500
    Assert-True ((Get-PatchState $client) -eq 'Patched') 'Real official CLI repairs isolated fixture and downloads Vencord files'
    Assert-True ((Get-FileHash -LiteralPath $backup).Hash -eq $originalHash) 'Official installer preserves original archive as backup'
    Assert-True (@(Get-ClientProcesses $client).Count -eq 1) 'Successful repair reopens fixture client'
    $processBefore = @(Get-ClientProcesses $client)[0].Id
    Invoke-ClientRepair $client
    Assert-True (@(Get-ClientProcesses $client)[0].Id -eq $processBefore) 'Already patched client is not restarted'
    Write-Output ('TOTAL PASSED: ' + $passed)
    Write-Output ('TEST PROFILE: ' + $fixture)
} finally {
    Get-ClientProcesses $client | Stop-Process -Force -ErrorAction SilentlyContinue
}
