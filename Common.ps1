# Vencord Auto Repair 2.0. Functions only; loading this file changes nothing.
Set-StrictMode -Version 2.0

function Initialize-RepairPaths {
    param([string] $StateDirectory = (Join-Path $env:LOCALAPPDATA 'VencordAutoRepair'))
    $script:StateDirectory = [IO.Path]::GetFullPath($StateDirectory)
    $script:EnabledFile = Join-Path $script:StateDirectory 'enabled.flag'
    $script:StopFile = Join-Path $script:StateDirectory 'stop.flag'
    $script:LogFile = Join-Path $script:StateDirectory 'AutoRepair.log'
    $script:CliHash = '466d2a0be1f380ddffed052df3cc132125fa34dc1af29312e14f13f358c8d2a2'
    $script:GuiHash = 'dc0826657a005009f43bdc3a0933d08352f8b22b2b9b961697a2db6e9913e871'
}

function Write-RepairLog {
    param([string] $Message)
    # A log failure must never prevent reopening Discord.
    try {
        [void][IO.Directory]::CreateDirectory($script:StateDirectory)
        if ((Test-Path -LiteralPath $script:LogFile) -and (Get-Item -LiteralPath $script:LogFile).Length -gt 2MB) {
            Move-Item -LiteralPath $script:LogFile -Destination ($script:LogFile + '.old') -Force
        }
        [IO.File]::AppendAllText($script:LogFile, ('{0:u} {1}{2}' -f [DateTime]::Now, $Message, [Environment]::NewLine))
    } catch { }
}

function Get-WindowsPowerShell {
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $psExe)) { throw 'Windows PowerShell 5.1 could not be found.' }
    return $psExe
}

function Test-OfficialBinary {
    param([string] $Path, [string] $ExpectedHash)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing installer: $Path. Extract the entire ZIP again." }
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $ExpectedHash) {
        throw "Installer checksum mismatch: $Path. Extract a fresh copy of this package."
    }
}

function Invoke-ExternalProgram {
    param([string] $FilePath, [string] $Arguments, [int] $TimeoutSeconds = 240)
    # PowerShell 5.1 turns native stderr into exceptions with 2>&1 and
    # ErrorActionPreference=Stop. Use .NET and drain both streams asynchronously.
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $FilePath
    $info.Arguments = $Arguments
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.RedirectStandardInput = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    try {
        if (-not $process.Start()) { throw 'Could not start the installer.' }
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill()
            $process.WaitForExit()
            throw "Installer timed out after $TimeoutSeconds seconds. Check your connection and use Manual Repair.cmd."
        }
        $process.WaitForExit()
        return [pscustomobject]@{ ExitCode = $process.ExitCode; Stdout = $stdout.GetAwaiter().GetResult(); Stderr = $stderr.GetAwaiter().GetResult() }
    } finally { $process.Dispose() }
}

function Get-DiscordClients {
    foreach ($entry in @(@('stable','Discord'), @('ptb','DiscordPTB'), @('canary','DiscordCanary'))) {
        $root = Join-Path $env:LOCALAPPDATA $entry[1]
        if (Test-Path -LiteralPath $root -PathType Container) {
            [pscustomobject]@{ Branch = $entry[0]; Name = $entry[1]; Root = $root }
        }
    }
}

function Get-DiscordApp {
    param($Client)
    $apps = @(Get-ChildItem -LiteralPath $Client.Root -Directory -Filter 'app-*' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^app-\d+(\.\d+){1,3}$' } |
        Sort-Object @{ Expression = { [version]$_.Name.Substring(4) } } -Descending)
    if ($apps.Count -eq 0) { return $null }

    # During an update Discord can leave a newer, incomplete app-* directory
    # beside the older version that is still running. Follow the executable that
    # owns the live Discord session so an abandoned update cannot hide a valid
    # Vencord patch indefinitely.
    $runningDirectories = @()
    foreach ($proc in @(Get-Process -Name $Client.Name -ErrorAction SilentlyContinue)) {
        try {
            if ($proc.SessionId -eq [Diagnostics.Process]::GetCurrentProcess().SessionId -and
                $proc.Path -and $proc.Path.StartsWith($Client.Root + '\', [StringComparison]::OrdinalIgnoreCase)) {
                $runningDirectories += (Split-Path $proc.Path -Parent)
            }
        } catch { }
    }
    foreach ($runningDirectory in @($runningDirectories | Select-Object -Unique)) {
        $runningApp = $apps | Where-Object {
            $_.FullName.Equals($runningDirectory, [StringComparison]::OrdinalIgnoreCase)
        } | Select-Object -First 1
        if ($null -ne $runningApp) {
            $runningResources = Join-Path $runningApp.FullName 'resources'
            $runningExe = Join-Path $runningApp.FullName ($Client.Name + '.exe')
            if ((Test-Path -LiteralPath $runningExe) -and (Test-Path -LiteralPath $runningResources)) {
                return [pscustomobject]@{ Directory = $runningApp.FullName; Resources = $runningResources; Exe = $runningExe }
            }
        }
    }

    # Never patch an older app just because the newest is still being extracted.
    $app = $apps[0]
    $resources = Join-Path $app.FullName 'resources'
    $exe = Join-Path $app.FullName ($Client.Name + '.exe')
    if (-not (Test-Path -LiteralPath $exe) -or -not (Test-Path -LiteralPath $resources)) { return $null }
    [pscustomobject]@{ Directory = $app.FullName; Resources = $resources; Exe = $exe }
}

function Get-VencordDist {
    if ($env:VENCORD_USER_DATA_DIR) { return (Join-Path $env:VENCORD_USER_DATA_DIR 'dist') }
    if ($env:DISCORD_USER_DATA_DIR) { return (Join-Path (Split-Path $env:DISCORD_USER_DATA_DIR -Parent) 'VencordData\dist') }
    return (Join-Path $env:APPDATA 'Vencord\dist')
}

function Get-PatchState {
    param($Client)
    $app = Get-DiscordApp $Client
    if ($null -eq $app) { return 'UpdatingOrMissing' }
    $asar = Join-Path $app.Resources 'app.asar'
    $backup = Join-Path $app.Resources '_app.asar'
    if (-not (Test-Path -LiteralPath $asar -PathType Leaf)) { return 'UpdatingOrMissing' }
    if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) { return 'Missing' }
    if ((Get-Item -LiteralPath $backup).Length -eq 0) { return 'NeedsManualRepair' }
    # A stale backup is not proof that the injector is installed.
    if ((Get-Item -LiteralPath $asar).Length -gt 1MB) { return 'NeedsManualRepair' }
    $text = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($asar))
    if ($text -notmatch 'patcher\.js') { return 'NeedsManualRepair' }
    $dist = Get-VencordDist
    foreach ($name in @('patcher.js','preload.js','renderer.js','renderer.css')) {
        $file = Join-Path $dist $name
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return 'MissingFiles' }
        if ((Get-Item -LiteralPath $file).Length -eq 0) { return 'MissingFiles' }
    }
    return 'Patched'
}

function Get-ClientProcesses {
    param($Client)
    foreach ($proc in @(Get-Process -Name $Client.Name -ErrorAction SilentlyContinue)) {
        try {
            if ($proc.SessionId -eq [Diagnostics.Process]::GetCurrentProcess().SessionId -and
                $proc.Path -and $proc.Path.StartsWith($Client.Root + '\', [StringComparison]::OrdinalIgnoreCase)) { $proc }
        } catch { }
    }
}

function Get-AppFingerprint {
    param($Client)
    $app = Get-DiscordApp $Client
    if ($null -eq $app) { return '' }
    $parts = @($app.Directory)
    foreach ($name in @('app.asar', '_app.asar')) {
        $file = Get-Item -LiteralPath (Join-Path $app.Resources $name) -ErrorAction SilentlyContinue
        if ($null -ne $file) { $parts += ('{0}:{1}:{2}' -f $name, $file.Length, $file.LastWriteTimeUtc.Ticks) }
    }
    return ($parts -join '|')
}

function Test-CanAttemptRepair {
    param($Attempt, [DateTime] $Now = [DateTime]::UtcNow)
    return ($Attempt.Count -lt 3 -and $Now -ge [DateTime]$Attempt.Next)
}

function Test-RepairNetwork {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    foreach ($url in @('https://api.github.com/repos/Vendicated/Vencord/releases/latest', 'https://vencord.dev/releases/vencord')) {
        try {
            $release = Invoke-RestMethod -Uri $url -UseBasicParsing -TimeoutSec 15 -Headers @{ 'User-Agent' = 'VencordAutoRepair/2.0' }
            if (@($release.assets).Count -gt 0) { return }
        } catch { }
    }
    throw 'Vencord release servers are unreachable. Discord was left running. Check internet access and try later.'
}

function Start-DiscordClient {
    param($Client)
    if (@(Get-ClientProcesses $Client).Count -gt 0) { return }
    $update = Join-Path $Client.Root 'Update.exe'
    if (Test-Path -LiteralPath $update) {
        Start-Process -FilePath $update -ArgumentList ('--processStart ' + $Client.Name + '.exe') -WindowStyle Hidden
    } else {
        $app = Get-DiscordApp $Client
        if ($null -eq $app) { throw 'Discord could not be reopened; launch it from your normal shortcut.' }
        Start-Process -FilePath $app.Exe -WindowStyle Hidden
    }
}

function Invoke-ClientRepair {
    param($Client)
    $cli = Join-Path $script:StateDirectory 'Installers\VencordInstallerCli.exe'
    Test-OfficialBinary $cli $script:CliHash
    Test-RepairNetwork
    if ((Test-Path -LiteralPath $script:StopFile) -or -not (Test-Path -LiteralPath $script:EnabledFile)) { return }
    $before = Get-AppFingerprint $Client
    if (-not $before) { throw 'Discord is still updating.' }
    $state = Get-PatchState $Client
    if ($state -eq 'Patched') { return }
    if ($state -notin @('Missing','MissingFiles')) { throw "Patch state is $state. Use Manual Repair.cmd." }
    $officialApp = Get-ChildItem -LiteralPath $Client.Root -Directory -Filter 'app-*' |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'resources') } |
        Sort-Object Name -Descending | Select-Object -First 1
    if ($officialApp.FullName -ne (Get-DiscordApp $Client).Directory) {
        throw 'Discord version folders are ambiguous to the official installer. Use Manual Repair.cmd.'
    }
    $running = @(Get-ClientProcesses $Client)
    if ($running.Count -eq 0) { return }
    Write-RepairLog "Repairing $($Client.Name). Discord will close and reopen."
    $reopen = $false
    try {
        $reopen = $true
        $running | Stop-Process -Force -ErrorAction Stop
        $deadline = [DateTime]::UtcNow.AddSeconds(10)
        while (@(Get-ClientProcesses $Client).Count -gt 0) {
            if ([DateTime]::UtcNow -gt $deadline) { throw 'Discord did not fully close. Use Manual Repair.cmd.' }
            Start-Sleep -Milliseconds 250
        }
        if ($before -ne (Get-AppFingerprint $Client)) { throw 'Discord updated during the repair check; retry later.' }
        $result = Invoke-ExternalProgram $cli ('--repair --location "' + $Client.Root + '"')
        Write-RepairLog ("Installer exit $($result.ExitCode)`n" + $result.Stdout + $result.Stderr)
        if ($result.ExitCode -ne 0) { throw "Vencord installer returned exit code $($result.ExitCode). See AutoRepair.log." }
        if ((Get-PatchState $Client) -ne 'Patched') { throw 'Installer did not restore all required patch files. Use Manual Repair.cmd.' }
        Write-RepairLog "Verified the Vencord patch and required files for $($Client.Name)."
    } finally {
        if ($reopen) {
            try { Start-DiscordClient $Client }
            catch { Write-RepairLog $_.Exception.Message }
        }
    }
}

function Get-WatcherProcesses {
    $watcher = Join-Path $script:StateDirectory 'Watcher.ps1'
    $pattern = '(?i)-File\s+"' + [Regex]::Escape($watcher) + '"(?:\s|$)'
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -ErrorAction Stop |
        Where-Object { $_.SessionId -eq [Diagnostics.Process]::GetCurrentProcess().SessionId -and
            $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine -match $pattern }
}

function Stop-RepairWatcher {
    [void][IO.Directory]::CreateDirectory($script:StateDirectory)
    [IO.File]::WriteAllText($script:StopFile, 'stop')
    $running = @(Get-WatcherProcesses)
    if ($running.Count -eq 0) { return }
    $installed = Join-Path $script:StateDirectory 'Watcher.ps1'
    $isV2 = (Test-Path -LiteralPath $installed) -and ([IO.File]::ReadAllText($installed).Contains('# AutoRepair-Version: 2.0'))
    if (-not $isV2) {
        if (@(Get-Process -Name VencordInstallerCli -ErrorAction SilentlyContinue).Count -gt 0) {
            throw 'A Vencord repair is in progress. Let it finish, then run this button again.'
        }
        foreach ($proc in $running) { Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop }
        return
    }
    $deadline = [DateTime]::UtcNow.AddSeconds(12)
    while (@(Get-WatcherProcesses).Count -gt 0) {
        if ([DateTime]::UtcNow -ge $deadline) {
            if (@(Get-Process -Name VencordInstallerCli -ErrorAction SilentlyContinue).Count -gt 0) {
                throw 'A Vencord repair is still running. Let it finish, then run this button again.'
            }
            Write-RepairLog 'Watcher did not stop after 12 seconds; terminating the stuck watcher.'
            foreach ($proc in @(Get-WatcherProcesses)) {
                Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
            }
            return
        }
        Start-Sleep -Milliseconds 250
    }
}

function Start-RepairWatcher {
    Remove-Item -LiteralPath $script:StopFile -Force -ErrorAction SilentlyContinue
    $token = [Guid]::NewGuid().ToString('N')
    $watcher = Join-Path $script:StateDirectory 'Watcher.ps1'
    $arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $watcher + '" -ReadyToken ' + $token
    $proc = Start-Process -FilePath (Get-WindowsPowerShell) -ArgumentList $arguments -WindowStyle Hidden -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while ([DateTime]::UtcNow -lt $deadline) {
        $proc.Refresh()
        if ($proc.HasExited) { throw 'Watcher exited at startup. Run Check Status.cmd for the log.' }
        try {
            $ready = Get-Content -LiteralPath (Join-Path $script:StateDirectory 'ready.json') -Raw -ErrorAction Stop | ConvertFrom-Json
            if ($ready.Token -eq $token -and $ready.Pid -eq $proc.Id) { return }
        } catch { }
        Start-Sleep -Milliseconds 250
    }
    throw 'Watcher did not confirm startup. Run Check Status.cmd for details.'
}

function Get-RepairMutexName {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($script:StateDirectory.ToLowerInvariant())
        return ('Local\VencordAutoRepairV2_' + [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-',''))
    } finally { $sha.Dispose() }
}

function Enable-RepairInstallation {
    param([string] $PackageRoot, [string] $ShortcutPath)
    foreach ($name in @('Common.ps1','Watcher.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $PackageRoot $name))) { throw "Missing $name. Extract the entire ZIP before running Enable." }
    }
    Test-OfficialBinary (Join-Path $PackageRoot 'Installers\VencordInstallerCli.exe') $script:CliHash
    if (@(Get-DiscordClients).Count -eq 0) { throw 'No standard Discord installation found. Install/open Discord first, or use Manual Repair.cmd for a custom location.' }
    Stop-RepairWatcher
    [void][IO.Directory]::CreateDirectory((Join-Path $script:StateDirectory 'Installers'))
    foreach ($name in @('Common.ps1','Watcher.ps1','Installers\VencordInstallerCli.exe')) {
        $source = Join-Path $PackageRoot $name
        $target = Join-Path $script:StateDirectory $name
        if ([IO.Path]::GetFullPath($source) -ne [IO.Path]::GetFullPath($target)) { Copy-Item -LiteralPath $source -Destination $target -Force }
    }
    $startupArguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $script:StateDirectory 'Watcher.ps1') + '"'
    New-RepairShortcut $ShortcutPath (Get-WindowsPowerShell) $startupArguments $script:StateDirectory
    [IO.File]::WriteAllText($script:EnabledFile, '2.0')
    try { Start-RepairWatcher }
    catch {
        # A failed setup must not leave an enabled startup entry behind.
        [IO.File]::WriteAllText($script:StopFile, 'stop')
        Remove-Item -LiteralPath $script:EnabledFile -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $ShortcutPath -Force -ErrorAction SilentlyContinue
        throw
    }
}

function Disable-RepairInstallation {
    param([string] $ShortcutPath)
    if (Test-Path -LiteralPath $ShortcutPath) { Remove-Item -LiteralPath $ShortcutPath -Force -ErrorAction Stop }
    if (Test-Path -LiteralPath $script:EnabledFile) { Remove-Item -LiteralPath $script:EnabledFile -Force -ErrorAction Stop }
    Stop-RepairWatcher
}

function New-RepairShortcut {
    param([string] $Path, [string] $Target, [string] $Arguments, [string] $WorkingDirectory)
    # IShellLinkW/IPersistFile keeps Unicode paths intact; WScript.Shell.Save
    # failed the mixed-language profile test on Windows PowerShell 5.1.
    if (-not ('VencordAutoRepair.Shortcut' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
namespace VencordAutoRepair {
    [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
    internal class ShellLink { }
    [ComImport, Guid("000214F9-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IShellLinkW {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder file, int max, IntPtr data, uint flags);
        void GetIDList(out IntPtr list);
        void SetIDList(IntPtr list);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder text, int max);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string text);
        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder dir, int max);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string dir);
        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder args, int max);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string args);
        void GetHotkey(out short key);
        void SetHotkey(short key);
        void GetShowCmd(out int cmd);
        void SetShowCmd(int cmd);
        void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder icon, int max, out int index);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string icon, int index);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string path, uint reserved);
        void Resolve(IntPtr window, uint flags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string path);
    }
    public static class Shortcut {
        public static void Save(string path, string target, string args, string directory) {
            object obj = new ShellLink();
            try {
                var link = (IShellLinkW)obj;
                link.SetPath(target);
                link.SetArguments(args);
                link.SetWorkingDirectory(directory);
                link.SetDescription("Vencord Auto Repair 2.0");
                link.SetShowCmd(7);
                ((IPersistFile)obj).Save(path, true);
            } finally { Marshal.FinalReleaseComObject(obj); }
        }
        public static string ReadArguments(string path) {
            object obj = new ShellLink();
            try {
                ((IPersistFile)obj).Load(path, 0);
                var args = new StringBuilder(32768);
                ((IShellLinkW)obj).GetArguments(args, args.Capacity);
                return args.ToString();
            } finally { Marshal.FinalReleaseComObject(obj); }
        }
    }
}
'@
    }
    [VencordAutoRepair.Shortcut]::Save($Path, $Target, $Arguments, $WorkingDirectory)
}
