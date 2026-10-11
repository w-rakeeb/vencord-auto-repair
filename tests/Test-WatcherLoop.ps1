$ErrorActionPreference = 'Stop'
$env:LOCALAPPDATA = Join-Path $PSScriptRoot ('loop-profile-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
$env:APPDATA = Join-Path $env:LOCALAPPDATA 'Roaming'
$clientRoot = Join-Path $env:LOCALAPPDATA 'Discord'
$resources = Join-Path $clientRoot 'app-1.0.1\resources'
[void][IO.Directory]::CreateDirectory($resources)
[IO.File]::WriteAllText((Join-Path $resources 'app.asar'), 'original')
[IO.File]::WriteAllText((Join-Path $clientRoot 'app-1.0.1\Discord.exe'), 'fixture')
[IO.File]::WriteAllText((Join-Path $clientRoot 'simulated-running'), 'yes')
. (Join-Path $PSScriptRoot 'loop\Common.ps1')
Initialize-RepairPaths
[void][IO.Directory]::CreateDirectory($script:StateDirectory)
[IO.File]::WriteAllText($script:EnabledFile, 'test')
$watcher = Join-Path $PSScriptRoot 'loop\Watcher.ps1'
Copy-Item -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'Watcher.ps1') -Destination $watcher -Force
$proc = Start-Process -FilePath (Get-WindowsPowerShell) -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $watcher + '"') -WindowStyle Hidden -PassThru
try {
    Start-Sleep -Seconds 8
    $log = [IO.File]::ReadAllText($script:LogFile)
    if ($log.Contains('automatic repair invoked')) { throw 'Repaired before settling delay.' }
    Write-Output 'PASS: Watcher waits for file settling before repair'
    Start-Sleep -Seconds 20
    $log = [IO.File]::ReadAllText($script:LogFile)
    if ([Regex]::Matches($log, 'automatic repair invoked').Count -ne 1) { throw ('Expected exactly one automatic attempt. Log: ' + $log) }
    if ($log.Contains('Watcher check failed')) { throw $log }
    Write-Output 'PASS: Running Discord with missing patch triggers one automatic attempt'
    $history = Get-Content -LiteralPath (Join-Path $script:StateDirectory 'retries.json') -Raw | ConvertFrom-Json
    if ($history.Count -ne 1 -or [DateTime]$history.Next -lt [DateTime]::UtcNow) { throw 'Retry persistence failed.' }
    Write-Output 'PASS: Failed attempt persists its cooldown on disk'
    [IO.File]::WriteAllText($script:StopFile, 'stop')
    if (-not $proc.WaitForExit(10000)) { throw 'Stop signal ignored.' }
    Remove-Item -LiteralPath $script:StopFile -Force
    $proc = Start-Process -FilePath (Get-WindowsPowerShell) -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $watcher + '"') -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 26
    $log = [IO.File]::ReadAllText($script:LogFile)
    if ([Regex]::Matches($log, 'automatic repair invoked').Count -ne 1) { throw 'Restart bypassed retry cooldown.' }
    if ($log.Contains('Watcher check failed') -or $log.Contains('could not be read')) { throw $log }
    Write-Output 'PASS: Restarted watcher honors persisted cooldown without repeat repair'
} finally {
    [IO.File]::WriteAllText($script:StopFile, 'stop')
    if (-not $proc.WaitForExit(10000)) { $proc.Kill() }
}
