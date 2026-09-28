#Requires -Version 5.1
<#
.SYNOPSIS
  Download this repo and run the Windows installer.

.EXAMPLE
  irm https://raw.githubusercontent.com/Hung2124/codex-multi-profile/main/install.ps1 | iex

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Ref v0.4.0

.EXAMPLE
  # Upgrading from the old clone-based version: import its logins and remove it
  $env:CODEX_MP_REMOVE_LEGACY = '1'; irm https://raw.githubusercontent.com/Hung2124/codex-multi-profile/main/install.ps1 | iex
#>
[CmdletBinding()]
param(
    [string]$Repo = 'Hung2124/codex-multi-profile',
    [string]$Ref = 'main',
    [switch]$KeepDownload,
    [switch]$RemoveLegacy
)

$ErrorActionPreference = 'Stop'
if (-not $PSBoundParameters.ContainsKey('Ref') -and $env:CODEX_MP_REF) {
    $Ref = $env:CODEX_MP_REF
}
if (-not $PSBoundParameters.ContainsKey('RemoveLegacy') -and $env:CODEX_MP_REMOVE_LEGACY -in @('1', 'true', 'yes', 'on')) {
    $RemoveLegacy = $true
}
$tmp = Join-Path $env:TEMP ("codex-multi-profile-" + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
    $zip = Join-Path $tmp 'src.zip'
    if ($Ref -match '^(refs/)?tags/') {
        $tag = $Ref -replace '^(refs/)?tags/', ''
        $url = "https://github.com/$Repo/archive/refs/tags/$tag.zip"
    }
    elseif ($Ref -match '^v?\d+\.\d+') {
        $url = "https://github.com/$Repo/archive/refs/tags/$Ref.zip"
    }
    else {
        $url = "https://github.com/$Repo/archive/refs/heads/$Ref.zip"
    }

    Write-Host "Downloading $url"
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
    $inner = Get-ChildItem -LiteralPath $tmp -Directory |
        Where-Object { $_.Name -like 'codex-multi-profile-*' } |
        Select-Object -First 1
    if (-not $inner) { throw "Unzipped repo folder not found under $tmp" }

    $installer = Join-Path $inner.FullName 'scripts\Install-CodexMultiProfile.ps1'
    if (-not (Test-Path -LiteralPath $installer)) { throw "Installer missing: $installer" }

    $installArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer)
    if ($RemoveLegacy) { $installArgs += '-RemoveLegacy' }
    & powershell.exe @installArgs
}

finally {
    if (-not $KeepDownload -and (Test-Path -LiteralPath $tmp)) {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
    elseif ($KeepDownload) {
        Write-Host "Kept download at $tmp"
    }
}
