#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$exporter = Join-Path $repo 'scripts\Export-CodexDiagnostics.ps1'
Import-Module (Join-Path $repo 'scripts\CodexMultiProfile.psm1') -Force

$tmp = Join-Path $env:TEMP ("cmp-diag-" + [guid]::NewGuid().ToString('n'))
$sourceHome = Join-Path $tmp 'home'
$root = Join-Path $tmp 'root'
New-Item -ItemType Directory -Force -Path $sourceHome, $root | Out-Null
# Minimal install copies so sync-check + doctor have something to say
Copy-Item (Join-Path $repo 'scripts\CodexMultiProfile.psm1') (Join-Path $root 'CodexMultiProfile.psm1')
Copy-Item (Join-Path $repo 'scripts\Redact-LaunchTrace.ps1') (Join-Path $root 'Redact-LaunchTrace.ps1')
Copy-Item (Join-Path $repo 'scripts\Export-CodexDiagnostics.ps1') (Join-Path $root 'Export-CodexDiagnostics.ps1')
'0.1.4-test' | Set-Content -LiteralPath (Join-Path $root 'VERSION') -Encoding ASCII
$fakeLog = "user alice@secret.example opened $env:USERPROFILE\.codex"
Set-Content -LiteralPath (Join-Path $root 'launch-trace.log') -Value $fakeLog -Encoding UTF8

$out = Join-Path $tmp 'bundle'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $exporter -ParallelRoot $root -SourceHome $sourceHome -OutDir $out
if (-not (Test-Path -LiteralPath (Join-Path $out 'doctor.json'))) { throw 'doctor.json missing' }
if (-not (Test-Path -LiteralPath (Join-Path $out 'status.json'))) { throw 'status.json missing' }
if (-not (Test-Path -LiteralPath (Join-Path $out 'meta.json'))) { throw 'meta.json missing' }
if (-not (Test-Path -LiteralPath (Join-Path $out 'sync-check.json'))) { throw 'sync-check.json missing' }
$redacted = Join-Path $out 'launch-trace.redacted.txt'
if (-not (Test-Path -LiteralPath $redacted)) { throw 'redacted log missing' }
$txt = Get-Content -LiteralPath $redacted -Raw
if ($txt -match 'alice@secret\.example') { throw 'email leaked into diagnostics' }
if ($txt -like "*$env:USERPROFILE*") { throw 'home path leaked into diagnostics' }
if (Get-ChildItem -LiteralPath $out -Recurse -Filter 'auth.json') { throw 'auth.json must never be exported' }

Write-Output 'OK: diagnostics bundle redacts secrets.'
