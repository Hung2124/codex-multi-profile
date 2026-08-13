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

foreach ($name in @('Codex1.lnk', 'codex1.lnk', 'Codex Main.lnk', 'Codex Profiles.lnk')) {
    Remove-Item -LiteralPath (Join-Path $desktop $name) -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path -LiteralPath $root)) {
    Write-Output 'Nothing installed.'
    return
}

Get-ChildItem -LiteralPath $root -File | Where-Object {
    $_.Extension -in '.ps1', '.psm1', '.vbs', '.cmd', '.log' -or $_.Name -eq '.authswap-active'
} | Remove-Item -Force -ErrorAction SilentlyContinue

if ($PurgeProfiles) {
    Remove-Item -LiteralPath (Join-Path $root 'profiles') -Recurse -Force -ErrorAction SilentlyContinue
    Write-Output 'Removed launcher files and local profile auth copies.'
}
else {
    Write-Output "Removed launcher files. Profile folders kept under $root\profiles (auth stays local)."
    Write-Output 'Pass -PurgeProfiles to delete those too. ~/.codex is never touched.'
}
