#requires -Version 5.1
[CmdletBinding()]
param([ValidateSet('Enable','Disable','Status','Manual')][string] $Action = 'Status')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
Initialize-RepairPaths
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'Vencord Auto Repair.lnk'
try {
    if ($Action -eq 'Status') {
        Write-Host ('Windows: ' + [Environment]::OSVersion.VersionString)
        Write-Host ('PowerShell: ' + $PSVersionTable.PSVersion)
        Write-Host ('Enabled: ' + (Test-Path -LiteralPath $script:EnabledFile))
        Write-Host ('Startup shortcut: ' + (Test-Path -LiteralPath $shortcutPath))
        Write-Host ('Running watchers: ' + @(Get-WatcherProcesses).Count)
        $clients = @(Get-DiscordClients)
        if ($clients.Count -eq 0) { Write-Host 'No standard Discord installation found. Install/open Discord first, or use Manual Repair.cmd for a custom location.' }
        foreach ($client in $clients) { Write-Host ($client.Name + ': ' + (Get-PatchState $client)) }
        Write-Host ('Log: ' + $script:LogFile)
        if (Test-Path -LiteralPath $script:LogFile) { Get-Content -LiteralPath $script:LogFile -Tail 25 | Out-Host }
        exit 0
    }
    if ($Action -eq 'Disable') {
        Disable-RepairInstallation $shortcutPath
        Write-Host 'Auto-repair is INACTIVE. Vencord remains installed.' -ForegroundColor Yellow
        exit 0
    }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Close this window and double-click the button normally, using the same Windows account as Discord. Do not use Run as administrator.'
    }
    if ($env:VENCORD_DEV_INSTALL -eq '1') { throw 'A development Vencord installation was detected. Use its development installer instead.' }
    if ($Action -eq 'Manual') {
        $gui = Join-Path $PSScriptRoot 'Installers\VencordInstaller.exe'
        Test-OfficialBinary $gui $script:GuiHash
        $wasEnabled = Test-Path -LiteralPath $script:EnabledFile
        $installedWatcher = Join-Path $script:StateDirectory 'Watcher.ps1'
        $legacyWasRunning = (-not $wasEnabled) -and (@(Get-WatcherProcesses).Count -gt 0) -and
            (Test-Path -LiteralPath $installedWatcher) -and
            (-not [IO.File]::ReadAllText($installedWatcher).Contains('# AutoRepair-Version: 2.0'))
        Stop-RepairWatcher
        try {
            Write-Host 'Select Discord and click Reinstall / Repair. After success, fully quit and reopen Discord.'
            Start-Process -FilePath $gui -Wait
        } finally {
            if ($wasEnabled) { Start-RepairWatcher }
            elseif ($legacyWasRunning) {
                $arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $installedWatcher + '"'
                Start-Process -FilePath (Get-WindowsPowerShell) -ArgumentList $arguments -WindowStyle Hidden
            }
        }
        exit 0
    }
    Enable-RepairInstallation $PSScriptRoot $shortcutPath
    Write-Host 'Auto-repair is ACTIVE. The background watcher confirmed startup.' -ForegroundColor Green
    Write-Host 'When Vencord is missing, allow about 30 seconds plus download time. Discord may restart once.'
    Write-Host 'Run Check Status.cmd for errors, or Manual Repair.cmd for the official installer.'
    exit 0
} catch {
    Write-RepairLog ('Setup ' + $Action + ': ' + $_.Exception.Message)
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
