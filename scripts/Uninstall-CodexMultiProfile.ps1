#Requires -Version 5.1
<#
.SYNOPSIS
  Remove Desktop shortcuts and launcher scripts. Does not delete ~/.codex or profile auth unless -PurgeProfiles.
#>
[CmdletBinding()]
param([switch]$PurgeProfiles)

$ErrorActionPreference = 'Stop'
$root = Join-Path $env:LOCALAPPDATA 'CodexParallelDesktop'
$desktop = [Environment]::GetFolderPath('Desktop')
$shell = New-Object -ComObject WScript.Shell

Get-ChildItem -LiteralPath $desktop -Filter '*.lnk' -ErrorAction SilentlyContinue | ForEach-Object {
    $shortcut = $shell.CreateShortcut($_.FullName)
    $blob = "$($shortcut.Arguments) $($shortcut.WorkingDirectory) $($shortcut.TargetPath)"
    if ($blob -like '*CodexParallelDesktop*') {
        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
    }
}

if (-not (Test-Path -LiteralPath $root)) {
    Write-Output 'Removed matching Desktop shortcuts. Nothing else was installed.'
    return
}

Get-ChildItem -LiteralPath $root -File | Where-Object {
    $_.Extension -in '.ps1', '.psm1', '.vbs', '.cmd', '.log' -or $_.Name -in @('.authswap-active', 'VERSION')
} | Remove-Item -Force -ErrorAction SilentlyContinue

if ($PurgeProfiles) {
    Remove-Item -LiteralPath (Join-Path $root 'profiles') -Recurse -Force -ErrorAction SilentlyContinue
    Write-Output 'Removed launcher files, Desktop shortcuts, and local profile auth copies.'
}
else {
    Write-Output "Removed launcher files and Desktop shortcuts. Profile folders kept under $root\profiles."
    Write-Output 'Pass -PurgeProfiles to delete those too. ~/.codex is never touched.'
}
