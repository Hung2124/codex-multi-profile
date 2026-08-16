#Requires -Version 5.1
<#
.SYNOPSIS
  Bundle doctor/status/processes/sync + a redacted launch-trace for bug reports.
  Never copies auth.json or other secrets.

.EXAMPLE
  .\Export-CodexDiagnostics.ps1
  .\Export-CodexDiagnostics.ps1 -OutDir $env:USERPROFILE\Desktop\codex-diag
#>
[CmdletBinding()]
param(
    [string]$ParallelRoot = (Join-Path $env:LOCALAPPDATA 'CodexParallelDesktop'),
    [string]$SourceHome = (Join-Path $env:USERPROFILE '.codex'),
    [string]$OutDir,
    [switch]$OpenFolder
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'CodexMultiProfile.psm1'
if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "Missing $modulePath"
}
Import-Module $modulePath -Force

if (-not $OutDir) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutDir = Join-Path $env:TEMP ("codex-multi-profile-diag-$stamp")
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Write-RedactedJson {
    param(
        [Parameter(Mandatory)] $Data,
        [Parameter(Mandatory)] [string]$Path,
        [int]$Depth = 5
    )
    $raw = $Data | ConvertTo-Json -Depth $Depth
    if ([string]::IsNullOrWhiteSpace($raw)) {
        $raw = if ($Data -is [System.Array]) { '[]' } else { '{}' }
    }
    $json = ConvertTo-CodexRedactedText -Text $raw -ParallelRoot $ParallelRoot -SourceHome $SourceHome
    Write-Utf8NoBom -Path $Path -Text $json
}

$meta = [ordered]@{
    ExportedAt = (Get-Date).ToString('o')
    Version    = Get-CodexMultiProfileVersion
    OsVersion  = [Environment]::OSVersion.VersionString
    PsVersion  = $PSVersionTable.PSVersion.ToString()
    Note       = 'Emails, usernames, machine names, and local paths are masked. auth.json is never included.'
}
Write-RedactedJson -Data $meta -Path (Join-Path $OutDir 'meta.json') -Depth 4

$status = Get-CodexInstallStatus -SourceHome $SourceHome -ParallelRoot $ParallelRoot
Write-RedactedJson -Data $status -Path (Join-Path $OutDir 'status.json') -Depth 6

$doctor = @(Invoke-CodexDoctor -SourceHome $SourceHome -ParallelRoot $ParallelRoot)
Write-RedactedJson -Data $doctor -Path (Join-Path $OutDir 'doctor.json') -Depth 5

$procs = @(Get-CodexRunningProcesses -ParallelRoot $ParallelRoot)
Write-RedactedJson -Data $procs -Path (Join-Path $OutDir 'processes.json') -Depth 5

$scriptSrc = $PSScriptRoot
$sync = @(Test-CodexInstallSync -SourceDir $scriptSrc -ParallelRoot $ParallelRoot)
Write-RedactedJson -Data $sync -Path (Join-Path $OutDir 'sync-check.json') -Depth 4

$log = Join-Path $ParallelRoot 'launch-trace.log'
if (Test-Path -LiteralPath $log) {
    $redactor = Join-Path $PSScriptRoot 'Redact-LaunchTrace.ps1'
    $safe = Join-Path $OutDir 'launch-trace.redacted.txt'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $redactor -LogPath $log -OutFile $safe
}

$ver = Join-Path $ParallelRoot 'VERSION'
if (Test-Path -LiteralPath $ver) {
    Copy-Item -LiteralPath $ver -Destination (Join-Path $OutDir 'VERSION') -Force
}

$readme = @"
Codex Multi-Profile diagnostic bundle
=====================================
Paste these JSON files into a GitHub issue after a quick review.
Usernames, machine names, emails, and local paths are masked. auth.json and tokens are never included.

Suggested attach order: meta.json, doctor.json, status.json, sync-check.json, launch-trace.redacted.txt
"@
Write-Utf8NoBom -Path (Join-Path $OutDir 'README.txt') -Text $readme

Write-Output "Wrote diagnostics to $OutDir"
if ($OpenFolder) {
    Start-Process explorer.exe -ArgumentList $OutDir
}
