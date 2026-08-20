#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repo 'scripts\CodexMultiProfile.psm1') -Force
Import-Module (Join-Path $repo 'scripts\CodexRouter.psm1') -Force

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

function Assert-NoBom([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        throw "UTF-8 BOM written: $Path"
    }
}

$app = Join-Path $repo 'scripts\Show-CodexAccountApp.ps1'
if (-not (Test-Path -LiteralPath $app)) { throw 'Show-CodexAccountApp.ps1 missing' }
Assert-NoBom $app

$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($app, [ref]$tokens, [ref]$errors)
if ($errors -and $errors.Count -gt 0) {
    throw ('Parse failed: ' + (($errors | ForEach-Object { $_.ToString() }) -join '; '))
}

$src = Get-Content -LiteralPath $app -Raw -Encoding UTF8
foreach ($bad in @('??', '?.', ' && ', ' || ')) {
    if ($src.Contains($bad)) { throw "Show-CodexAccountApp.ps1 uses PowerShell 7 operator: $bad" }
}
if ($src -match 'Start-Process[^\n]*ChatGPT\.exe') {
    throw 'Account app must not Start-Process ChatGPT.exe'
}
if ($src -match 'WindowsApps') { throw 'Account app must not mention WindowsApps' }
if ($src -match 'Codex\.exe') { throw 'Account app must not mention Codex.exe' }
if ($src -match 'miuuyy') { throw 'forbidden project name' }

$pack = @(Get-CodexPackagedScriptNames)
if ($pack -notcontains 'Show-CodexAccountApp.ps1') {
    throw 'Get-CodexPackagedScriptNames missing Show-CodexAccountApp.ps1'
}

$tmp = Join-Path $env:TEMP ('cmp-accounts-' + [guid]::NewGuid().ToString('n'))
$parallel = Join-Path $tmp 'root'
New-Item -ItemType Directory -Force -Path $parallel | Out-Null
New-FakeAuth -Dir (Join-Path $parallel 'profiles\codex1') -Email 'alt@example.com'
New-FakeAuth -Dir (Join-Path $parallel 'profiles\codex2') -Email 'work@example.com'
$null = Set-CodexProfileSticky -Name 'codex1' -Workspace $tmp -ParallelRoot $parallel
$null = Set-CodexProfileDepleted -Name 'codex2' -ParallelRoot $parallel

$raw = & $app -Headless -ParallelRoot $parallel
if (-not $raw) { throw 'headless produced no output' }
$text = ($raw | Out-String)
if ($text -match 'alt@example.com' -or $text -match 'work@example.com') {
    throw 'headless leaked a full email'
}
if ($text -notmatch 'al\*\*\*@example.com') { throw "headless missing masked email: $text" }
if ($text -notmatch '"ui":\s*false' -and $text -notmatch '"ui": false') {
    if ($text -notmatch 'ui') { throw 'headless JSON missing ui=false' }
}
$obj = $text | ConvertFrom-Json
if (-not $obj.ok) { throw 'headless ok=false' }
if ([int]$obj.count -ne 2) { throw "headless count $($obj.count)" }
$names = @($obj.accounts | ForEach-Object { $_.Name })
if ($names -notcontains 'codex1' -or $names -notcontains 'codex2') { throw 'headless missing profile names' }
$p2 = @($obj.accounts | Where-Object { $_.Name -eq 'codex2' })[0]
if (-not $p2.Depleted) { throw 'headless depleted flag missing' }


if ($src -match 'Close it, then') { throw 'app must switch now, not ask the user to close Codex' }
if ($src -notmatch 'FastSwitch') { throw 'app must pass -FastSwitch to the launcher' }

$launch = Join-Path $repo 'scripts\Launch-CodexProfile.ps1'
$ls = Get-Content -LiteralPath $launch -Raw -Encoding UTF8
if ($ls -notmatch 'FastSwitch') { throw 'Launch-CodexProfile.ps1 missing -FastSwitch' }
if ($ls -notmatch 'mainAuthBak') { throw 'launcher must use main backup for poison/bootstrap' }
if ($ls -notmatch 'Stop-CodexAuthSwapWatchers') { throw 'launcher must stop the outgoing watcher' }

$watch = Get-Content -LiteralPath (Join-Path $repo 'scripts\watch-authswap-restore.ps1') -Raw -Encoding UTF8
if ($watch -notmatch 'InitialSleepSeconds') { throw 'watcher missing InitialSleepSeconds' }

# Swapped session: profile email == current main, backup is real main -> no bootstrap
if (Test-NeedBootstrapLogin -ProfileEmail 'alt@example.com' -MainEmail 'main@example.com') {
    throw 'must not bootstrap when profile != main backup'
}

Write-Output 'OK: Codex Accounts parsed, packaged, headless pool, one-click FastSwitch.'
