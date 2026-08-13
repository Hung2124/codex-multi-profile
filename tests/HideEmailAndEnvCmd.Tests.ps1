#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$module = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\CodexMultiProfile.psm1'
Import-Module $module -Force

if ((Hide-AuthEmail -Email 'alt@example.com') -ne 'al***@example.com') {
    throw 'Hide-AuthEmail should keep two characters of the local-part'
}
if ((Hide-AuthEmail -Email 'a@x.io') -ne 'a***@x.io') {
    throw 'Hide-AuthEmail should keep a single-character local-part'
}
if ((Hide-AuthEmail -Email 'MISSING') -ne 'MISSING') {
    throw 'Hide-AuthEmail should pass through MISSING'
}
if ((Hide-AuthEmail -Email 'PARSE_ERR') -ne 'PARSE_ERR') {
    throw 'Hide-AuthEmail should pass through PARSE_ERR'
}
if ((Hide-AuthEmail -Email '') -ne 'MISSING') {
    throw 'Hide-AuthEmail should treat empty as MISSING'
}
if ((Hide-AuthEmail -Email 'not-an-email') -ne '***') {
    throw 'Hide-AuthEmail should mask non-emails'
}

$dir = Join-Path $env:TEMP ("cmp-cmd-" + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$cmdPath = Join-Path $dir 'launch-codex1-env.cmd'
New-CodexEnvCmd -CmdPath $cmdPath -CodexHome 'C:\Users\me\.codex' -UserDataDir 'C:\p\codex1' -CloneApp 'C:\clone\app' -CloneExe 'C:\clone\app\ChatGPT.exe'
$text = Get-Content -LiteralPath $cmdPath -Raw -Encoding UTF8
if ($text.Length -ge 1 -and [int][char]$text[0] -eq 0xFEFF) { throw 'env cmd must not start with BOM' }
if ($text -notmatch 'set "CODEX_HOME=C:\\Users\\me\\.codex"') { throw 'env cmd missing CODEX_HOME' }
if ($text -notmatch 'set "CODEX_ELECTRON_USER_DATA_PATH=C:\\p\\codex1"') { throw 'env cmd missing user-data path' }
if ($text -notmatch '--user-data-dir="C:\\p\\codex1"') { throw 'env cmd missing --user-data-dir' }
if ($text -notmatch 'ChatGPT\.exe') { throw 'env cmd must launch ChatGPT.exe' }
if ($text -match 'Codex\.exe') { throw 'env cmd must not launch Codex.exe' }

if ((Get-CodexParallelRoot) -notlike '*CodexParallelDesktop') {
    throw 'Get-CodexParallelRoot should point at CodexParallelDesktop'
}

Write-Output 'OK: email mask and env-cmd contents.'
