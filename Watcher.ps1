# AutoRepair-Version: 2.0
#requires -Version 5.1
param([string] $ReadyToken = '', [switch] $CheckOnly)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
Initialize-RepairPaths
if ($CheckOnly) {
    foreach ($client in @(Get-DiscordClients)) { Write-Output ($client.Name + ': ' + (Get-PatchState $client)) }
    exit 0
}
if (-not (Test-Path -LiteralPath $script:EnabledFile)) { exit 0 }
$mutex = New-Object Threading.Mutex($false, (Get-RepairMutexName))
$owned = $false
try {
    try { $owned = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $owned = $true }
    if (-not $owned) { exit 0 }
    Write-RepairLog 'Watcher 2.0 started.'
    $retryFile = Join-Path $script:StateDirectory 'retries.json'
    $attempts = @{}
    if (Test-Path -LiteralPath $retryFile) {
        try {
            foreach ($entry in @(Get-Content -LiteralPath $retryFile -Raw | ConvertFrom-Json)) {
                $attempts[$entry.Key] = @{ Count = [int]$entry.Count; Next = [DateTime]$entry.Next }
            }
        } catch { Write-RepairLog 'Retry history could not be read; starting a new retry history.' }
    }
    $seen = @{}
    $reported = @{}
    @{ Token = $ReadyToken; Pid = $PID } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $script:StateDirectory 'ready.json') -Encoding UTF8
    while ((Test-Path -LiteralPath $script:EnabledFile) -and -not (Test-Path -LiteralPath $script:StopFile)) {
        try {
            foreach ($client in @(Get-DiscordClients)) {
                $key = $client.Root
                if (@(Get-ClientProcesses $client).Count -eq 0) { $seen.Remove($key); continue }
                $state = Get-PatchState $client
                if ($state -eq 'Patched') { $seen.Remove($key); continue }
                if ($state -notin @('Missing','MissingFiles')) {
                    if ($reported[$key] -ne $state) {
                        Write-RepairLog "$($client.Name): $state. Waiting, or use Manual Repair.cmd for a damaged install."
                        $reported[$key] = $state
                    }
                    $seen.Remove($key)
                    continue
                }
                $fingerprint = Get-AppFingerprint $client
                if (-not $seen.ContainsKey($key) -or $seen[$key].Fingerprint -ne $fingerprint) {
                    $seen[$key] = @{ Fingerprint = $fingerprint; Since = [DateTime]::UtcNow }
                    continue
                }
                if (([DateTime]::UtcNow - $seen[$key].Since).TotalSeconds -lt 20) { continue }
                $retryKey = $key + '|' + (Get-DiscordApp $client).Directory
                if (-not $attempts.ContainsKey($retryKey)) { $attempts[$retryKey] = @{ Count = 0; Next = [DateTime]::MinValue } }
                if (-not (Test-CanAttemptRepair $attempts[$retryKey])) { continue }
                $attempts[$retryKey].Count++
                $attempts[$retryKey].Next = [DateTime]::UtcNow.AddMinutes(30)
                # Persist before attempting so a terminated watcher cannot restart-loop.
                $entries = @(foreach ($k in $attempts.Keys) { @{ Key = $k; Count = $attempts[$k].Count; Next = $attempts[$k].Next.ToString('o') } })
                ConvertTo-Json -InputObject $entries | Set-Content -LiteralPath $retryFile -Encoding UTF8
                try { Invoke-ClientRepair $client }
                catch {
                    Write-RepairLog ("Repair failed for $($client.Name): " + $_.Exception.Message + ' Retry after 30 minutes, maximum 3 per Discord version. Use Manual Repair.cmd if needed.')
                }
                $seen.Remove($key)
            }
        } catch { Write-RepairLog ('Watcher check failed; it will retry: ' + $_.Exception.Message) }
        Start-Sleep -Seconds 3
    }
    Write-RepairLog 'Watcher stopped.'
} catch {
    Write-RepairLog ('Fatal watcher error: ' + $_.Exception.Message)
    exit 1
} finally {
    if ($owned) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
