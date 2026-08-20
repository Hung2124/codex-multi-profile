#Requires -Version 5.1
# Old InputBox menu is gone. This shortcut opens the Accounts window.
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($here)) {
    $here = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$app = Join-Path $here 'Show-CodexAccountApp.ps1'
if (-not (Test-Path -LiteralPath $app)) {
    $app = Join-Path $env:LOCALAPPDATA 'CodexParallelDesktop\Show-CodexAccountApp.ps1'
}
if (-not (Test-Path -LiteralPath $app)) {
    throw 'Missing Show-CodexAccountApp.ps1. Re-run the installer.'
}
$argList = @(
    '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
    '-File', $app
)
Start-Process -FilePath 'powershell.exe' -ArgumentList $argList | Out-Null
