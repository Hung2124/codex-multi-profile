#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repo 'scripts\CodexMultiProfile.psm1') -Force

function ConvertTo-Base64Url([string]$Text) {
    [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Text)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function New-FakeAuth([string]$Dir, [string]$Email) {
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    $header = ConvertTo-Base64Url '{"alg":"none"}'
    $payload = ConvertTo-Base64Url ('{"email":"' + $Email + '"}')
    $json = '{"tokens":{"id_token":"' + $header + '.' + $payload + '.x"}}'
    [System.IO.File]::WriteAllText((Join-Path $Dir 'auth.json'), $json, [System.Text.UTF8Encoding]::new($false))
}

$tmp = Join-Path $env:TEMP ("cmp-repair-" + [guid]::NewGuid().ToString('n'))
$source = Join-Path $tmp 'home'
$parallel = Join-Path $tmp 'root'
New-Item -ItemType Directory -Force -Path $parallel | Out-Null
New-FakeAuth -Dir $source -Email 'alt@example.com'
# main backup is the real main account
$header = ConvertTo-Base64Url '{"alg":"none"}'
$payload = ConvertTo-Base64Url '{"email":"main@example.com"}'
$bakJson = '{"tokens":{"id_token":"' + $header + '.' + $payload + '.x"}}'
[System.IO.File]::WriteAllText((Join-Path $source 'auth.json.__main__'), $bakJson, [System.Text.UTF8Encoding]::new($false))
Set-Content -LiteralPath (Join-Path $parallel '.authswap-active') -Value 'codex1' -Encoding ASCII

$result = Clear-StaleAuthSwapLock -SourceHome $source -ParallelRoot $parallel
if (-not $result.RestoredMain) { throw 'expected RestoredMain' }
if (-not $result.ClearedLock) { throw 'expected ClearedLock' }
if ($result.MainAccount -ne 'ma***@example.com') { throw "MainAccount $($result.MainAccount)" }
if (Test-Path -LiteralPath (Join-Path $parallel '.authswap-active')) { throw 'lock should be gone' }
if (Test-Path -LiteralPath (Join-Path $source 'auth.json.__main__')) { throw 'backup should be consumed' }
if ((Get-AuthEmailFromFile -Path (Join-Path $source 'auth.json')) -ne 'main@example.com') {
    throw 'active auth should be main after repair'
}

# sync-check: copy one file, leave others missing
$scriptSrc = Join-Path $repo 'scripts'
Copy-Item (Join-Path $scriptSrc 'CodexMultiProfile.psm1') (Join-Path $parallel 'CodexMultiProfile.psm1') -Force
$rows = @(Test-CodexInstallSync -SourceDir $scriptSrc -ParallelRoot $parallel)
$mod = $rows | Where-Object { $_.Name -eq 'CodexMultiProfile.psm1' } | Select-Object -First 1
if (-not $mod.InSync) { throw 'module should be in sync after copy' }
$missing = @($rows | Where-Object { $_.Name -eq 'Launch-CodexProfile.ps1' })[0]
if ($missing.InSync) { throw 'missing launcher must not report InSync' }
if (-not $missing.InRepo) { throw 'Launch-CodexProfile.ps1 should exist in repo' }
if ($missing.Installed) { throw 'Launch-CodexProfile.ps1 should be missing from parallel root' }

Write-Output 'OK: repair restores main and sync-check detects drift.'
