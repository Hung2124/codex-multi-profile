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

$tmp = Join-Path $env:TEMP ("cmp-status-" + [guid]::NewGuid().ToString('n'))
$source = Join-Path $tmp 'home'
$parallel = Join-Path $tmp 'root'
New-FakeAuth -Dir $source -Email 'main@example.com'
New-FakeAuth -Dir (Join-Path $parallel 'profiles\codex1') -Email 'alt@example.com'
Set-Content -LiteralPath (Join-Path $parallel '.authswap-active') -Value "codex1`n" -Encoding ASCII

$info = Get-CodexInstallStatus -SourceHome $source -ParallelRoot $parallel
if ($info.MainAccount -ne 'ma***@example.com') { throw "MainAccount $($info.MainAccount)" }
if ($info.SwapActive.Trim() -ne 'codex1') { throw "SwapActive $($info.SwapActive)" }
if ($info.Profiles.Count -ne 1) { throw 'expected one profile' }
if ($info.Profiles[0].Account -ne 'al***@example.com') { throw "profile account $($info.Profiles[0].Account)" }

$json = $info | ConvertTo-Json -Depth 6 -Compress
if ($json -match 'main@example.com' -or $json -match 'alt@example.com') {
    throw 'JSON status leaked a full email'
}
if ($json -notmatch 'ma\*\*\*@example.com') { throw 'JSON missing masked main' }

$manager = Join-Path $repo 'scripts\CodexProfile.ps1'
$p = Start-Process -FilePath powershell.exe -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $manager,
    '-Action', 'remove', '-Name', 'nosuchprofile'
) -Wait -PassThru -WindowStyle Hidden
if ($p.ExitCode -eq 0) { throw 'remove without -Force must fail' }

Write-Output 'OK: status object/JSON stay masked; remove requires -Force.'
