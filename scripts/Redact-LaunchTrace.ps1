#Requires -Version 5.1
<#
.SYNOPSIS
  Copy launch-trace.log with emails and home paths scrubbed for bug reports.

.EXAMPLE
  .\Redact-LaunchTrace.ps1
  .\Redact-LaunchTrace.ps1 -OutFile .\safe-launch-trace.txt
#>
[CmdletBinding()]
param(
    [string]$LogPath = (Join-Path $env:LOCALAPPDATA 'CodexParallelDesktop\launch-trace.log'),
    [string]$OutFile
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'CodexMultiProfile.psm1'
if (Test-Path -LiteralPath $modulePath) {
    Import-Module $modulePath -Force
}

if (-not (Test-Path -LiteralPath $LogPath)) {
    throw "Log not found: $LogPath"
}

$text = Get-Content -LiteralPath $LogPath -Raw -Encoding UTF8
if ($null -eq $text) { $text = '' }

# Mask emails (including already-partial ones that still look like addresses)
$text = [regex]::Replace($text, '[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}', {
    param($m)
    if (Get-Command Hide-AuthEmail -ErrorAction SilentlyContinue) {
        return Hide-AuthEmail -Email $m.Value
    }
    return 'u***@redacted.example'
})

if (Get-Command ConvertTo-CodexRedactedText -ErrorAction SilentlyContinue) {
    $text = ConvertTo-CodexRedactedText -Text $text
}
else {
    $ladEsc = [regex]::Escape($env:LOCALAPPDATA)
    $text = [regex]::Replace($text, $ladEsc, '%LOCALAPPDATA%', 'IgnoreCase')
    $homeEsc = [regex]::Escape($env:USERPROFILE)
    $text = [regex]::Replace($text, $homeEsc, '%USERPROFILE%', 'IgnoreCase')
}

if (-not $OutFile) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutFile = Join-Path (Split-Path -Parent $LogPath) ("launch-trace.redacted-$stamp.txt")
}

if (Get-Command Write-Utf8NoBom -ErrorAction SilentlyContinue) {
    Write-Utf8NoBom -Path $OutFile -Text $text
}
else {
    [System.IO.File]::WriteAllText($OutFile, $text, [System.Text.UTF8Encoding]::new($false))
}

Write-Output "Wrote $OutFile"
Write-Output 'Safe to paste into a GitHub issue (still review for private project paths).'
