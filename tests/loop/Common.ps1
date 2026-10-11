. (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Common.ps1')
function Get-ClientProcesses {
    param($Client)
    if (Test-Path -LiteralPath (Join-Path $Client.Root 'simulated-running')) { [pscustomobject]@{ Id = 12345 } }
}
function Invoke-ClientRepair {
    param($Client)
    Write-RepairLog 'TEST: automatic repair invoked'
    throw 'TEST: simulated repair failure'
}
