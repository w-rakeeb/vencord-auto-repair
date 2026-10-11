# Testing

Tests use Windows PowerShell 5.1. They isolate LocalAppData, roaming data, startup shortcuts, and Vencord runtime files in temporary fixture directories inside `tests/`.

On 2026-10-11, all 52 assertions passed locally on Windows 11 x64: 39 compatibility/lifecycle checks, 9 repair-flow checks, and 4 watcher-loop checks. The integration run used the actual pinned Vencord CLI. This is not a separate Windows 10 or GUI validation.

`Test-Vencord.ps1` covers installer checksums, normal stderr, exit-code handling, simultaneous large output streams, timeout termination, patch detection, incomplete update folders, the running-version fallback, retry limits, process scoping, Unicode paths, startup confirmation, duplicate protection, and repeated enable/disable.

`Test-WatcherLoop.ps1` runs the shipped watcher loop with mocked process discovery and a failing repair. It verifies the settling delay, automatic triggering, persisted retry state, and cooldown after restarting the watcher.

`Test-RepairFlow.ps1` exercises failure recovery with a synthetic client process, then invokes the real official CLI against a fixture installation. It checks the injector and downloaded runtime files, archive preservation, reopening, and the already-patched case. It does not run a real Discord interface.

The GUI repair workflow, a physical reboot, Windows on ARM, 32-bit Windows, and managed-device restrictions are not automated tests. Patch detection is a filesystem check and does not verify individual plugins inside Discord.

The GitHub workflow runs the compatibility and watcher-loop tests. Network-dependent installer repair can be run manually with `workflow_dispatch` and the `integration` input.
