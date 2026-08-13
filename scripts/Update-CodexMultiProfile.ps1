#Requires -Version 5.1
<#
.SYNOPSIS
  Pull the repo if it is a git clone, then re-run the installer.
#>
[CmdletBinding()]
param(
    [string]$Name = 'codex1'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $repoRoot

if (Test-Path -LiteralPath (Join-Path $repoRoot '.git')) {
    git pull --ff-only
}

$installer = Join-Path $PSScriptRoot 'Install-CodexMultiProfile.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -Name $Name
$manager = Join-Path $env:LOCALAPPDATA 'CodexParallelDesktop\CodexProfile.ps1'
if (Test-Path -LiteralPath $manager) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $manager -Action verify
}
