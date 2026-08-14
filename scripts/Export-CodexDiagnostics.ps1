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

$meta = [ordered]@{
    ExportedAt = (Get-Date).ToString('o')
    Version    = Get-CodexMultiProfileVersion
    Machine    = $env:COMPUTERNAME
    User       = $env:USERNAME
    OsVersion  = [Environment]::OSVersion.VersionString
    PsVersion  = $PSVersionTable.PSVersion.ToString()
    Note       = 'Emails and home paths are masked. auth.json is never included.'
}
$meta | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'meta.json') -Encoding UTF8

$status = Get-CodexInstallStatus -SourceHome $SourceHome -ParallelRoot $ParallelRoot
$status | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutDir 'status.json') -Encoding UTF8

$doctor = @(Invoke-CodexDoctor -SourceHome $SourceHome -ParallelRoot $ParallelRoot)
$doctor | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutDir 'doctor.json') -Encoding UTF8

$procs = @(Get-CodexRunningProcesses -ParallelRoot $ParallelRoot)
$procs | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutDir 'processes.json') -Encoding UTF8

$scriptSrc = $PSScriptRoot
$sync = @(Test-CodexInstallSync -SourceDir $scriptSrc -ParallelRoot $ParallelRoot)
$sync | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'sync-check.json') -Encoding UTF8

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
auth.json and tokens are never included.

Suggested attach order: meta.json, doctor.json, status.json, sync-check.json, launch-trace.redacted.txt
"@
Write-Utf8NoBom -Path (Join-Path $OutDir 'README.txt') -Text $readme

Write-Output "Wrote diagnostics to $OutDir"
if ($OpenFolder) {
    Start-Process explorer.exe -ArgumentList $OutDir
}
