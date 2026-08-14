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

$tmp = Join-Path $env:TEMP ("cmp-doctor-" + [guid]::NewGuid().ToString('n'))
$source = Join-Path $tmp 'home'
$parallel = Join-Path $tmp 'root'
New-Item -ItemType Directory -Force -Path $parallel | Out-Null
New-FakeAuth -Dir $source -Email 'main@example.com'
New-FakeAuth -Dir (Join-Path $parallel 'profiles\codex1') -Email 'main@example.com'
Set-Content -LiteralPath (Join-Path $parallel '.authswap-active') -Value 'codex1' -Encoding ASCII

# BOM config
$cfg = Join-Path $source 'config.toml'
$bom = [byte[]](0xEF, 0xBB, 0xBF) + [Text.Encoding]::UTF8.GetBytes("model = `"gpt`"`n")
[System.IO.File]::WriteAllBytes($cfg, $bom)
if (-not (Test-FileHasUtf8Bom -Path $cfg)) { throw 'Test-FileHasUtf8Bom should detect BOM' }

$clean = Join-Path $tmp 'nobom.toml'
Write-Utf8NoBom -Path $clean -Text "model = `"gpt`"`n"
if (Test-FileHasUtf8Bom -Path $clean) { throw 'Write-Utf8NoBom must not write BOM' }

$findings = @(Invoke-CodexDoctor -SourceHome $source -ParallelRoot $parallel)
$codes = @($findings | ForEach-Object { $_.Code })
if ($codes -notcontains 'stale-swap-lock') { throw 'doctor should flag stale-swap-lock when lock set and no clone' }
if ($codes -notcontains 'poisoned-profile') { throw 'doctor should flag poisoned-profile when profile email == main' }
if ($codes -notcontains 'config-bom') { throw 'doctor should flag config-bom' }
if ($codes -notcontains 'missing-launcher') { throw 'doctor should flag missing launchers in empty parallel root' }

$json = $findings | ConvertTo-Json -Depth 5 -Compress
if ($json -match 'main@example.com') { throw 'doctor JSON leaked full email' }

Write-Output 'OK: doctor flags stale lock, poison, BOM, missing launchers.'
