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
function Assert-Throws([scriptblock] $Action, [string] $Message) {
    $caught = $false
    try { & $Action } catch { $caught = $true }
    Assert-True $caught $Message
}
function Encoded([string] $Command) { '-NoProfile -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Command)) }
$originalLocal = $env:LOCALAPPDATA
$originalRoaming = $env:APPDATA
$originalVc = $env:VENCORD_USER_DATA_DIR
$originalDiscordData = $env:DISCORD_USER_DATA_DIR
$fixture = Join-Path $PSScriptRoot ('fixture space & ! [x] ' + [char]0x00e9 + [char]0x09ac + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
[void][IO.Directory]::CreateDirectory($fixture)
$env:LOCALAPPDATA = Join-Path $fixture 'Local'
$env:APPDATA = Join-Path $fixture 'Roaming'
$env:VENCORD_USER_DATA_DIR = $null
$env:DISCORD_USER_DATA_DIR = $null
[void][IO.Directory]::CreateDirectory($env:LOCALAPPDATA)
[void][IO.Directory]::CreateDirectory($env:APPDATA)
Initialize-RepairPaths
$shortcutPath = Join-Path $fixture 'Startup test.lnk'
try {
    foreach ($file in Get-ChildItem -LiteralPath $PackageRoot -Filter '*.ps1') {
        $tokens = $null; $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
        Assert-True ($errors.Count -eq 0) ('PS5.1 syntax: ' + $file.Name)
    }
    $psExe = Get-WindowsPowerShell
    Assert-True (Test-Path -LiteralPath $psExe) 'Finds built-in Windows PowerShell'
    $cli = Join-Path $PackageRoot 'Installers\VencordInstallerCli.exe'
    Test-OfficialBinary $cli $script:CliHash
    Test-OfficialBinary (Join-Path $PackageRoot 'Installers\VencordInstaller.exe') $script:GuiHash
    Assert-True $true 'Both bundled official installer checksums match'
    Assert-Throws { Test-OfficialBinary $cli ('0' * 64) } 'Wrong binary checksum rejected'
    $help = Invoke-ExternalProgram $cli '--help' 15
    Assert-True ($help.ExitCode -eq 0 -and $help.Stderr.Contains('repair')) 'Official help stderr does not throw under PS5.1'
    $version = Invoke-ExternalProgram $cli '--version' 15
    Assert-True ($version.Stdout.Contains('v1.4.0')) 'Bundled CLI runs and reports version'
    $result = Invoke-ExternalProgram $psExe (Encoded '[Console]::Error.WriteLine("Normal message"); [Console]::WriteLine("Done"); exit 0') 15
    Assert-True ($result.ExitCode -eq 0 -and $result.Stderr.Contains('Normal message') -and $result.Stdout.Contains('Done')) 'stderr and stdout captured with successful exit'
    $result = Invoke-ExternalProgram $psExe (Encoded '[Console]::Error.WriteLine("Failure"); exit 7') 15
    Assert-True ($result.ExitCode -eq 7) 'Nonzero exit preserved'
    $result = Invoke-ExternalProgram $psExe (Encoded 'for ($i=0;$i -lt 3000;$i++) { [Console]::WriteLine(("a" * 100)); [Console]::Error.WriteLine(("b" * 100)) }') 15
    Assert-True ($result.Stdout.Length -gt 300000 -and $result.Stderr.Length -gt 300000) 'Large simultaneous output streams do not deadlock'
    Assert-Throws { Invoke-ExternalProgram $psExe (Encoded 'Start-Sleep -Seconds 60') 1 } 'Hung installer is terminated at timeout'
    Assert-Throws { Enable-RepairInstallation $PackageRoot $shortcutPath } 'Enable fails clearly without Discord'
    Assert-True (-not (Test-Path -LiteralPath $shortcutPath)) 'Failed enable does not create startup shortcut'
    $root = Join-Path $env:LOCALAPPDATA 'Discord'
    $client = [pscustomobject]@{ Name = 'Discord'; Branch = 'stable'; Root = $root }
    foreach ($versionNumber in @('1.0.9','1.0.10')) {
        $appDir = Join-Path $root ('app-' + $versionNumber)
        [void][IO.Directory]::CreateDirectory((Join-Path $appDir 'resources'))
        [IO.File]::WriteAllText((Join-Path $appDir 'Discord.exe'), 'fixture - not executable')
        [IO.File]::WriteAllText((Join-Path $appDir 'resources\app.asar'), 'original fixture archive')
    }
    Assert-True ((Get-DiscordApp $client).Directory.EndsWith('app-1.0.10')) 'Versions selected numerically, not alphabetically'
    Assert-True ((Get-PatchState $client) -eq 'Missing') 'Unpatched Discord detected'
    $app = Get-DiscordApp $client
    [IO.File]::WriteAllText((Join-Path $app.Resources '_app.asar'), 'original')
    Assert-True ((Get-PatchState $client) -eq 'NeedsManualRepair') 'Stale backup not mistaken for Vencord'
    [IO.File]::WriteAllText((Join-Path $app.Resources 'app.asar'), 'require("patcher.js")')
    Assert-True ((Get-PatchState $client) -eq 'MissingFiles') 'Missing Vencord runtime files detected'
    $dist = Get-VencordDist
    [void][IO.Directory]::CreateDirectory($dist)
    foreach ($name in @('patcher.js','preload.js','renderer.js','renderer.css')) { [IO.File]::WriteAllText((Join-Path $dist $name),'fixture') }
    Assert-True ((Get-PatchState $client) -eq 'Patched') 'Valid injector and files detected'
    [IO.File]::WriteAllText((Join-Path $dist 'renderer.js'),'')
    Assert-True ((Get-PatchState $client) -eq 'MissingFiles') 'Zero-byte runtime files detected'
    [IO.File]::WriteAllText((Join-Path $dist 'renderer.js'),'fixture')
    [void][IO.Directory]::CreateDirectory((Join-Path $root 'app-1.0.11'))
    Assert-True ((Get-PatchState $client) -eq 'UpdatingOrMissing') 'Incomplete newest app does not fall back to old app'
    $runningClient = [pscustomobject]@{Name='VencordDetectionFixture';Branch='stable';Root=$root}
    $runningExe = Join-Path $app.Directory 'VencordDetectionFixture.exe'
    $compiledExe = Join-Path $PSScriptRoot ('DetectionFixture-' + [Guid]::NewGuid().ToString('N') + '.exe')
    Add-Type -TypeDefinition 'public class DetectionFixture { public static void Main() { System.Threading.Thread.Sleep(30000); } }' -OutputAssembly $compiledExe -OutputType ConsoleApplication
    Move-Item -LiteralPath $compiledExe -Destination $runningExe
    $fixtureProcess = Start-Process -FilePath $runningExe -WindowStyle Hidden -PassThru
    try {
        Start-Sleep -Milliseconds 300
        Assert-True ((Get-DiscordApp $runningClient).Directory -eq $app.Directory) 'Running version preferred over incomplete update folder'
        Assert-True ((Get-PatchState $runningClient) -eq 'Patched') 'Running patched version not masked by unfinished update'
    } finally { Stop-Process -Id $fixtureProcess.Id -Force -ErrorAction SilentlyContinue }
    $env:VENCORD_USER_DATA_DIR = Join-Path $fixture 'Custom Vencord'
    Assert-True ((Get-VencordDist) -eq (Join-Path $env:VENCORD_USER_DATA_DIR 'dist')) 'Custom Vencord data directory respected'
    $env:VENCORD_USER_DATA_DIR = $null
    Assert-True (Test-CanAttemptRepair @{Count=0;Next=[DateTime]::MinValue}) 'First repair attempt allowed'
    Assert-True (-not (Test-CanAttemptRepair @{Count=1;Next=[DateTime]::UtcNow.AddMinutes(30)})) 'Retry cooldown enforced'
    Assert-True (-not (Test-CanAttemptRepair @{Count=3;Next=[DateTime]::MinValue})) 'Maximum attempt count enforced'
    foreach ($name in @('DiscordPTB','DiscordCanary')) { [void][IO.Directory]::CreateDirectory((Join-Path $env:LOCALAPPDATA $name)) }
    Assert-True (@(Get-DiscordClients).Count -eq 3) 'Stable, PTB, Canary discovered in current user profile'
    Assert-True (@(Get-ClientProcesses $client).Count -eq 0) 'Real Discord excluded from isolated profile'
    Write-RepairLog 'Fixture log entry'
    Assert-True ([IO.File]::ReadAllText($script:LogFile).Contains('Fixture log entry')) 'Logging works with Unicode and special characters in path'
    Enable-RepairInstallation $PackageRoot $shortcutPath
    Assert-True ((Test-Path -LiteralPath $script:EnabledFile) -and @(Get-WatcherProcesses).Count -eq 1) 'Enable starts and confirms exactly one background watcher'
    $shortcutArguments = [VencordAutoRepair.Shortcut]::ReadArguments($shortcutPath)
    Assert-True ($shortcutArguments.Contains($script:StateDirectory)) 'Startup shortcut preserves Unicode path to installed copy'
    Enable-RepairInstallation $PackageRoot $shortcutPath
    Assert-True (@(Get-WatcherProcesses).Count -eq 1) 'Enabling twice does not duplicate the watcher'
    $duplicate = Invoke-ExternalProgram $psExe ('-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $script:StateDirectory 'Watcher.ps1') + '"') 15
    Assert-True ($duplicate.ExitCode -eq 0 -and @(Get-WatcherProcesses).Count -eq 1) 'Mutex rejects duplicate watcher'
    Disable-RepairInstallation $shortcutPath
    Assert-True (@(Get-WatcherProcesses).Count -eq 0 -and -not (Test-Path -LiteralPath $shortcutPath) -and -not (Test-Path -LiteralPath $script:EnabledFile)) 'Disable stops watcher and removes startup entry'
    Disable-RepairInstallation $shortcutPath
    Assert-True $true 'Disabling twice is harmless'
    # Exercise the same shortcut executable and arguments used at actual sign-in.
    Enable-RepairInstallation $PackageRoot $shortcutPath
    Stop-RepairWatcher
    Remove-Item -LiteralPath $script:StopFile -Force
    $startupProc = Start-Process -FilePath $psExe -ArgumentList $shortcutArguments -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 2
    Assert-True (@(Get-WatcherProcesses).Count -eq 1) 'Sign-in shortcut command starts watcher'
    Disable-RepairInstallation $shortcutPath
    Write-Output ('TOTAL PASSED: ' + $passed)
    Write-Output ('TEST PROFILE: ' + $fixture)
} finally {
    try { Disable-RepairInstallation $shortcutPath } catch { Write-Warning $_.Exception.Message }
    $env:LOCALAPPDATA = $originalLocal
    $env:APPDATA = $originalRoaming
    $env:VENCORD_USER_DATA_DIR = $originalVc
    $env:DISCORD_USER_DATA_DIR = $originalDiscordData
}
