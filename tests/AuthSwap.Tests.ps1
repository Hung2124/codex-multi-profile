#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$module = Join-Path $root 'scripts\CodexMultiProfile.psm1'
Import-Module $module -Force

function ConvertTo-Base64Url([string]$Text) {
    [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Text)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function New-FakeAuthPath([string]$Email) {
    $dir = Join-Path $env:TEMP ("cmp-auth-" + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $header = ConvertTo-Base64Url '{"alg":"none","typ":"JWT"}'
    $payload = ConvertTo-Base64Url ('{"email":"' + $Email + '"}')
    $jwt = "$header.$payload.sig"
    $json = '{"tokens":{"id_token":"' + $jwt + '"}}'
    $path = Join-Path $dir 'auth.json'
    [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))
    return $path
}

$mainPath = New-FakeAuthPath 'main@example.com'
$altPath = New-FakeAuthPath 'alt@example.com'
$missing = Join-Path $env:TEMP 'cmp-auth-does-not-exist.json'

if ((Get-AuthEmailFromFile -Path $mainPath) -ne 'main@example.com') {
    throw 'Get-AuthEmailFromFile failed for main@example.com'
}
if ((Get-AuthEmailFromFile -Path $altPath) -ne 'alt@example.com') {
    throw 'Get-AuthEmailFromFile failed for alt@example.com'
}
if ((Get-AuthEmailFromFile -Path $missing) -ne 'MISSING') {
    throw 'Get-AuthEmailFromFile should return MISSING'
}

$junk = Join-Path $env:TEMP ("cmp-junk-" + [guid]::NewGuid().ToString('n') + '.json')
Set-Content -LiteralPath $junk -Value '{not json' -Encoding ASCII
if ((Get-AuthEmailFromFile -Path $junk) -ne 'PARSE_ERR') {
    throw 'Get-AuthEmailFromFile should return PARSE_ERR for junk'
}

if (Test-ShouldSaveProfileAuth -ActiveEmail 'alt@example.com' -MainBackupEmail 'main@example.com') { }
else { throw 'should save when active != main' }

if (Test-ShouldSaveProfileAuth -ActiveEmail 'main@example.com' -MainBackupEmail 'main@example.com') {
    throw 'must NOT save when active == main (poison guard)'
}

if (Test-ShouldSaveProfileAuth -ActiveEmail 'MISSING' -MainBackupEmail 'main@example.com') {
    throw 'must NOT save MISSING'
}

if (Test-ShouldSaveProfileAuth -ActiveEmail 'PARSE_ERR' -MainBackupEmail 'main@example.com') {
    throw 'must NOT save PARSE_ERR'
}

if (-not (Test-ShouldSaveProfileAuth -ActiveEmail 'alt@example.com' -MainBackupEmail 'MISSING')) {
    throw 'should save when main backup is missing but active is valid'
}

if (-not (Test-NeedBootstrapLogin -ProfileEmail 'MISSING' -MainEmail 'main@example.com')) {
    throw 'bootstrap when profile missing'
}
if (-not (Test-NeedBootstrapLogin -ProfileEmail 'main@example.com' -MainEmail 'main@example.com')) {
    throw 'bootstrap when profile equals main'
}
if (Test-NeedBootstrapLogin -ProfileEmail 'alt@example.com' -MainEmail 'main@example.com') {
    throw 'do not bootstrap when profile is a different account'
}
if (-not (Test-NeedBootstrapLogin -ProfileEmail 'alt@example.com' -MainEmail 'main@example.com' -Force)) {
    throw 'Force should bootstrap'
}

if ((ConvertTo-ProfileKey -ProfileName 'Codex 2') -ne 'codex-2') {
    throw 'ConvertTo-ProfileKey failed'
}

$bomPath = Join-Path $env:TEMP ("cmp-nobom-" + [guid]::NewGuid().ToString('n') + '.toml')
Write-Utf8NoBom -Path $bomPath -Text 'model = "gpt"'
$bytes = [IO.File]::ReadAllBytes($bomPath)
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw 'Write-Utf8NoBom wrote a UTF-8 BOM'
}

if ((Get-CodexMultiProfileVersion) -notmatch '^\d+\.\d+\.\d+$') {
    throw 'version should be semver'
}
$versionFile = Join-Path (Split-Path -Parent $PSScriptRoot) 'VERSION'
if ((Get-CodexMultiProfileVersion) -ne (Get-Content -LiteralPath $versionFile -Raw).Trim()) {
    throw 'Get-CodexMultiProfileVersion should match the VERSION file'
}

Write-Output 'OK: AuthSwap guards, JWT email parse, profile key, UTF-8 no BOM.'
