#Requires -Version 5.1
<#
.SYNOPSIS
  Remove the Codex shortcut, the menu helper and the scripts. Saved accounts are kept unless -RemoveAccounts.
  ~/.codex (chats, settings, the login in use) is never touched.
#>
[CmdletBinding()]
param(
    [switch]$RemoveAccounts,
    [string]$Root = (Join-Path $env:LOCALAPPDATA 'CodexMultiProfile')
)

$ErrorActionPreference = 'Stop'
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { [string]$_.CommandLine -like '*Start-CodexAccounts.ps1*' -and $_.ProcessId -ne $PID } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

$hostScript = Join-Path $Root 'Start-CodexAccounts.ps1'
foreach ($lnk in @((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Codex.lnk'), (Join-Path ([Environment]::GetFolderPath('Programs')) 'Codex (accounts).lnk'))) {
    if ((Test-Path -LiteralPath $lnk) -and (New-Object -ComObject WScript.Shell).CreateShortcut($lnk).Arguments -like "*$hostScript*") {
        Remove-Item -LiteralPath $lnk -Force
    }
}
foreach ($name in @('CodexAccounts.psm1', 'Start-CodexAccounts.ps1', 'switcher-inject.js', 'CodexAccounts.ps1', 'codex.ico', 'VERSION', 'settings.json')) {
    Remove-Item -LiteralPath (Join-Path $Root $name) -Force -ErrorAction SilentlyContinue
}
if ($RemoveAccounts) {
    Remove-Item -LiteralPath (Join-Path $Root 'accounts') -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $Root 'accounts.json') -Force -ErrorAction SilentlyContinue
}
Write-Output ("Uninstalled. Saved accounts {0}. Uninstall script left in {1}." -f $(if ($RemoveAccounts) { 'removed' } else { "kept in $Root\accounts" }), $Root)
