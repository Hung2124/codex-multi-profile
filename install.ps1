#Requires -Version 5.1
<#
.SYNOPSIS
  Download this repo and run the Windows installer.

.EXAMPLE
  irm https://raw.githubusercontent.com/Hung2124/codex-multi-profile/main/install.ps1 | iex

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Ref v0.3.0

.EXAMPLE
  # Install and turn on the in-app account switcher in one go
  $env:CODEX_MP_INAPP = '1'; irm https://raw.githubusercontent.com/Hung2124/codex-multi-profile/main/install.ps1 | iex
#>
[CmdletBinding()]
param(
    [string]$Repo = 'Hung2124/codex-multi-profile',
    [string]$Ref = 'main',
    [string]$Name = 'codex1',
    [switch]$KeepDownload,
    [switch]$InApp
)

$ErrorActionPreference = 'Stop'
if (-not $PSBoundParameters.ContainsKey('Ref') -and $env:CODEX_MP_REF) {
    $Ref = $env:CODEX_MP_REF
}
if (-not $PSBoundParameters.ContainsKey('InApp') -and $env:CODEX_MP_INAPP -in @('1', 'true', 'yes', 'on')) {
    $InApp = $true
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

    $installArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer, '-Name', $Name)
    if ($InApp) { $installArgs += '-EnableInAppSwitcher' }
    & powershell.exe @installArgs

    Write-Host ""
    Write-Host "Desktop: Codex Accounts (pick a login). One Codex window."
    if ($InApp) { Write-Host "In-app switcher ON: open a profile, then click the account pill or press Ctrl+Alt+A inside Codex." }
    else { Write-Host "Switch inside Codex: click 'Trong Codex' in Codex Accounts (or CodexProfile.ps1 -Action switcher)." }
    Write-Host "Router CLI (agents): pool / stick / route / depleted - docs/router.md"
}

finally {
    if (-not $KeepDownload -and (Test-Path -LiteralPath $tmp)) {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
    elseif ($KeepDownload) {
        Write-Host "Kept download at $tmp"
    }
}
