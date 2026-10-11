# Vencord Auto Repair

A Windows background watcher that runs the official Vencord repair command when Discord starts without its Vencord patch. It checks standard Discord, PTB, and Canary installations for the current Windows user.

This is an independent script maintained by [w-rakeeb](https://github.com/w-rakeeb), not an official Vencord project.

## Install

1. Download `Vencord-Auto-Repair-Windows.zip` from [Releases](https://github.com/w-rakeeb/vencord-auto-repair/releases/latest).
2. Extract the whole ZIP. Install and open Discord at least once.
3. Double-click **Enable Auto-Repair.cmd** using the Windows account that runs Discord. Do not use **Run as administrator**.
4. Wait for **ACTIVE**. When a repair is needed, allow roughly 30 seconds plus download time. Discord closes and reopens during repair.

Internet access is required to download Vencord's runtime files. The release ZIP includes the official GUI and CLI installers.

## Controls

| File | Action |
| --- | --- |
| `Enable Auto-Repair.cmd` | Install the watcher, start it, and add a per-user Startup shortcut. |
| `Disable Auto-Repair.cmd` | Stop monitoring and remove the Startup shortcut. Vencord stays installed. |
| `Check Status.cmd` | Show watcher count, patch state, and the last 25 log entries. |
| `Manual Repair.cmd` | Pause monitoring and open the official GUI installer. Monitoring resumes after it closes. |
| `VencordInstaller.exe` | A direct copy of the official GUI installer included in the ZIP. |

For manual repair, select Discord and click **Reinstall / Repair**, then fully quit and reopen Discord. If the GUI will not open, disable the watcher, run `Installers/VencordInstallerCli.exe`, choose **Repair Vencord**, and enable monitoring afterward.

## What the watcher does

The watcher polls every three seconds. It follows the version of Discord actually running, so an unfinished newer `app-*` directory does not hide an already patched session.

When the patch or required Vencord files are missing, it waits for Discord's files to remain unchanged for 20 seconds. It verifies the bundled CLI's SHA-256 hash and checks access to Vencord's release metadata before closing Discord. The CLI then runs with `--repair --location` for the detected installation.

A zero installer exit code is not enough: the watcher also checks the injector, backup archive, and required runtime files. It attempts to reopen Discord after a repair failure. A repair times out after four minutes; retries are spaced 30 minutes apart and limited to three attempts per Discord version. Retry state survives watcher restarts.

Enable reports success only after the background process confirms startup. A per-installation mutex prevents duplicate watchers. Disable and upgrades request a graceful stop; a stuck watcher can be terminated after 12 seconds when no Vencord CLI process is running.

## Status and troubleshooting

`Running watchers: 1` means a watcher process is running. `Discord: Patched` means the expected injector and Vencord files were found on disk. It does not prove every plugin loaded in Discord.

- **UpdatingOrMissing:** Discord's selected version lacks an executable, resources directory, or archive. Let its update finish. If this persists, use the official installer or repair Discord itself.
- **Missing / MissingFiles:** the watcher can attempt a repair while Discord is running.
- **NeedsManualRepair:** inconsistent archives require manual inspection. The watcher does not guess which archive to overwrite.
- **Patched but Vencord is absent:** use Manual Repair, then fully restart Discord.

If Discord is running from an older version while the official installer selects a different version directory, automatic repair stops with a version-selection error. Use Manual Repair rather than repeatedly restarting Discord.

Logs and installed scripts are stored in `%LOCALAPPDATA%\VencordAutoRepair`. Old failures remain in the log after a successful upgrade; check their timestamps. Nothing is uploaded. Logs can include local paths and your Windows username.

Windows **Startup apps** must allow the shortcut for sign-in startup. Run Enable once for each Windows user.

## Compatibility

The scripts use Windows PowerShell 5.1 and Windows APIs available on Windows 10 and 11. Automated checks were run on Windows 11 x64; Windows 10 was not separately tested in a VM. A Windows 10 user reported a running watcher and a detected patch, which is a narrower check than an end-to-end repair.

Automatic discovery covers the normal per-user Discord, PTB, and Canary desktop installations in LocalAppData. Custom installation paths can be selected through the manual installer. Browser Discord, Vesktop, development builds, and third-party Discord distributions are outside automatic detection. Windows on ARM, 32-bit Windows, and managed-device restrictions have not been verified.

## Build and test

From a source checkout, fetch the pinned installers first:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-Installers.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Vencord.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-WatcherLoop.ps1
```

The optional integration test downloads actual Vencord files and repairs a synthetic installation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-RepairFlow.ps1
```

That test refuses to run its official-installer step when real Discord Canary is open. The official installer kills processes by branch name; the test uses a uniquely named process and an isolated user-data directory.

Build the distributable ZIP with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build-Package.ps1
```

The package is written to `dist/`. Test fixtures are ignored by Git. See [testing notes](docs/testing.md) for the checks and remaining limits.

## License and provenance

The scripts are distributed under [GPL-3.0](LICENSE). Bundled Vencord installers are unmodified official v1.4.0 binaries, also GPL-3.0, with their source archive and license in the release ZIP. [Installer provenance](Installers/SOURCES.txt) records the URLs and checksums.

Codex assisted with implementation, documentation, and test preparation. The history of this tool includes fixes made after user-reported failures; no claim of universal Windows compatibility is made.
