#Requires -Version 5.1
<#
.SYNOPSIS
  Download this repo and run the Windows installer.

.EXAMPLE
  irm https://raw.githubusercontent.com/Hung2124/codex-multi-profile/main/install.ps1 | iex
#>
[CmdletBinding()]
param(
    [string]$Repo = 'Hung2124/codex-multi-profile',
    [string]$Ref = 'main'
)

$ErrorActionPreference = 'Stop'
$tmp = Join-Path $env:TEMP ("codex-multi-profile-" + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$zip = Join-Path $tmp 'src.zip'
$url = "https://github.com/$Repo/archive/refs/heads/$Ref.zip"
Write-Host "Downloading $url"
Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
$inner = Get-ChildItem -LiteralPath $tmp -Directory | Where-Object { $_.Name -like 'codex-multi-profile-*' } | Select-Object -First 1
if (-not $inner) { throw "Unzipped repo folder not found under $tmp" }
$installer = Join-Path $inner.FullName 'scripts\Install-CodexMultiProfile.ps1'
if (-not (Test-Path -LiteralPath $installer)) { throw "Installer missing: $installer" }
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer
