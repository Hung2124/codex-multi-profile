#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$script = Join-Path $repo 'scripts\Redact-LaunchTrace.ps1'

$tmp = Join-Path $env:TEMP ("cmp-redact-" + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$log = Join-Path $tmp 'launch-trace.log'
$out = Join-Path $tmp 'safe.txt'
$userHome = $env:USERPROFILE
$lad = $env:LOCALAPPDATA
@(
    "12:00:00.000 swapped in profile auth -> secret.user@gmail.com"
    "12:00:01.000 path=$userHome\.codex\auth.json"
    "12:00:02.000 clone=$lad\CodexParallelDesktop\versions\1\app\ChatGPT.exe"
) | Set-Content -LiteralPath $log -Encoding UTF8

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -LogPath $log -OutFile $out
$text = Get-Content -LiteralPath $out -Raw -Encoding UTF8
if ($text -match 'secret\.user@gmail\.com') { throw 'redactor left full email' }
if ($text -notmatch 'se\*\*\*@gmail\.com' -and $text -notmatch 'u\*\*\*@redacted') {
    throw "redactor did not mask email: $text"
}
if ($text -match [regex]::Escape($userHome)) { throw 'redactor left USERPROFILE absolute path' }
if ($text -notmatch '%USERPROFILE%') { throw 'redactor should substitute %USERPROFILE%' }
if ($text -notmatch '%LOCALAPPDATA%') { throw 'redactor should substitute %LOCALAPPDATA%' }

Write-Output 'OK: Redact-LaunchTrace masks emails and home paths.'
