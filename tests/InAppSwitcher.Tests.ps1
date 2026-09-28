#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repo 'scripts\CodexRouter.psm1') -Force
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

function Assert-NoBom([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        throw "UTF-8 BOM written: $Path"
    }
}

$tmp = Join-Path $env:TEMP ('cmp-switcher-' + [guid]::NewGuid().ToString('n'))
$parallel = Join-Path $tmp 'root'
$shared = Join-Path $tmp 'home'
New-Item -ItemType Directory -Force -Path $parallel, $shared | Out-Null
New-FakeAuth -Dir (Join-Path $parallel 'profiles\codex1') -Email 'alt@example.com'
New-FakeAuth -Dir (Join-Path $parallel 'profiles\codex2') -Email 'work@example.com'
New-Item -ItemType Directory -Force -Path (Join-Path $parallel 'profiles\codex3') | Out-Null
New-FakeAuth -Dir $shared -Email 'alt@example.com'
New-FakeAuth -Dir (Join-Path $tmp 'mainbak') -Email 'main@example.com'
Copy-Item -LiteralPath (Join-Path $tmp 'mainbak\auth.json') -Destination (Join-Path $shared 'auth.json.__main__')

# --- opt-in state: off by default, one loopback port, layer wins when both are on ---
$sw = Get-CodexSwitcherState -ParallelRoot $parallel
if ($sw.Enabled) { throw 'in-app switcher must be off by default' }
if ((Get-CodexCdpLaunchPort -ParallelRoot $parallel) -ne 0) { throw 'no CDP port when layer and switcher are off' }

$on = Set-CodexSwitcherEnabled -ParallelRoot $parallel -Lang 'vi'
if (-not $on.Enabled) { throw 'switcher enable' }
if ($on.Lang -ne 'vi') { throw 'switcher lang' }
Assert-NoBom (Get-CodexSwitcherStatePath -ParallelRoot $parallel)
if ((Get-CodexCdpLaunchPort -ParallelRoot $parallel) -ne $on.CdpPort) { throw 'switcher port must be used when only the switcher is on' }
$null = Set-CodexLayerEnabled -ParallelRoot $parallel -CdpPort 9555
if ((Get-CodexCdpLaunchPort -ParallelRoot $parallel) -ne 9555) { throw 'layer port must win when both are on' }
$null = Set-CodexLayerEnabled -ParallelRoot $parallel -Disable
$again = Set-CodexSwitcherEnabled -ParallelRoot $parallel
if ($again.Lang -ne 'vi') { throw 're-enable must keep the language' }
$off = Set-CodexSwitcherEnabled -ParallelRoot $parallel -Disable
if ($off.Enabled) { throw 'switcher disable' }
if ((Get-CodexCdpLaunchPort -ParallelRoot $parallel) -ne 0) { throw 'port must be 0 after disable' }
$badLang = $false
try { $null = Set-CodexSwitcherEnabled -ParallelRoot $parallel -Lang 'xx' } catch { $badLang = $true }
if (-not $badLang) { throw 'unknown language must be rejected' }

# --- email leak guard ---
foreach ($leak in @('alt@example.com', 'x a@b.co y', '"account":"alice.smith@corp.example.org"')) {
    if (-not (Test-CodexTextHasFullEmail -Text $leak)) { throw "leak not detected: $leak" }
}
foreach ($safe in @('al***@example.com', '"account":"a***@x.io"', 'MISSING', 'PARSE_ERR', '')) {
    if (Test-CodexTextHasFullEmail -Text $safe) { throw "false leak: $safe" }
}

# --- snapshot pushed into the Codex window ---
Set-Content -LiteralPath (Join-Path $parallel '.authswap-active') -Value 'codex1' -Encoding ASCII
$null = Set-CodexProfileDepleted -Name 'codex2' -ParallelRoot $parallel
$null = Set-CodexProfileSticky -Name 'codex1' -Workspace $tmp -ParallelRoot $parallel
$snap = Get-CodexSwitcherSnapshot -ParallelRoot $parallel -SourceHome $shared
if ($snap.active -ne 'codex1') { throw "snapshot active $($snap.active)" }
if ($snap.activeAccount -ne 'al***@example.com') { throw "snapshot activeAccount $($snap.activeAccount)" }
if ($snap.mainAccount -ne 'ma***@example.com') { throw "snapshot mainAccount $($snap.mainAccount)" }
if (@($snap.profiles).Count -ne 3) { throw 'snapshot profile count' }
$p1 = @($snap.profiles | Where-Object { $_.name -eq 'codex1' })[0]
$p2 = @($snap.profiles | Where-Object { $_.name -eq 'codex2' })[0]
$p3 = @($snap.profiles | Where-Object { $_.name -eq 'codex3' })[0]
if (-not $p1.active -or $p2.active) { throw 'active flag' }
if (-not $p2.depleted) { throw 'depleted flag' }
if (-not $p3.needsLogin) { throw 'needsLogin flag for a profile without auth' }
if ($p1.stickyCount -ne 1) { throw 'stickyCount' }
if ($snap.suggestion) { throw "suggestion must skip active, depleted and not-signed-in profiles, got $($snap.suggestion)" }
$null = Set-CodexProfileDepleted -Name 'codex2' -ParallelRoot $parallel -Clear
$snap2 = Get-CodexSwitcherSnapshot -ParallelRoot $parallel -SourceHome $shared
if ($snap2.suggestion -ne 'codex2') { throw "suggestion should be the saved, non-depleted login, got $($snap2.suggestion)" }
$snapJson = $snap | ConvertTo-Json -Depth 8 -Compress
if (Test-CodexTextHasFullEmail -Text $snapJson) { throw 'snapshot leaked a full email' }
if ($snapJson -match 'id_token' -or $snapJson -match [regex]::Escape($parallel)) { throw 'snapshot leaked tokens or paths' }

# --- page -> host message validation ---
$known = @('codex1', 'codex2', 'codex3')
$ok = ConvertFrom-CodexSwitcherMessage -Payload '{"type":"switch","profile":"codex2"}' -KnownProfiles $known
if ($ok.Error -or $ok.Type -ne 'switch' -or $ok.Profile -ne 'codex2') { throw 'valid switch rejected' }
$dep = ConvertFrom-CodexSwitcherMessage -Payload '{"type":"depleted","profile":"codex1","value":false}' -KnownProfiles $known
if ($dep.Error -or $dep.Value -ne $false) { throw 'depleted false' }
$depStr = ConvertFrom-CodexSwitcherMessage -Payload '{"type":"depleted","profile":"codex1","value":"false"}' -KnownProfiles $known
if ($depStr.Value -ne $true) { throw 'non-boolean value must not clear depleted' }
$rm = ConvertFrom-CodexSwitcherMessage -Payload '{"type":"remove","profile":"codex3"}' -KnownProfiles $known
if ($rm.Error -or $rm.Type -ne 'remove' -or $rm.Profile -ne 'codex3') { throw 'valid remove rejected' }
$add = ConvertFrom-CodexSwitcherMessage -Payload '{"type":"add","name":"Work Laptop"}' -KnownProfiles $known
if ($add.Error -or $add.Name -ne 'work-laptop') { throw "add name $($add.Name) $($add.Error)" }
$cases = @(
    @{ P = ''; E = 'empty' },
    @{ P = 'not json'; E = 'bad-json' },
    @{ P = '{"nope":1}'; E = 'no-type' },
    @{ P = '{"type":"exec","cmd":"calc"}'; E = 'unknown-type' },
    @{ P = '{"type":"switch"}'; E = 'no-profile' },
    @{ P = '{"type":"switch","profile":"..\\..\\x"}'; E = 'bad-profile' },
    @{ P = '{"type":"switch","profile":"codex1 & calc"}'; E = 'bad-profile' },
    @{ P = '{"type":"switch","profile":"codex9"}'; E = 'unknown-profile' },
    @{ P = '{"type":"remove","profile":"..\\codex1"}'; E = 'bad-profile' },
    @{ P = '{"type":"remove","profile":"ghost"}'; E = 'unknown-profile' },
    @{ P = '{"type":"add","name":"codex2"}'; E = 'exists' },
    @{ P = '{"type":"add","name":"!!!"}'; E = 'bad-name' },
    @{ P = ('{"type":"hello","pad":"' + ('x' * 5000) + '"}'); E = 'too-large' }
)
foreach ($c in $cases) {
    $r = ConvertFrom-CodexSwitcherMessage -Payload $c.P -KnownProfiles $known
    if ($r.Error -ne $c.E) { throw ("expected {0} for {1}, got '{2}'" -f $c.E, $c.P.Substring(0, [Math]::Min(40, $c.P.Length)), $r.Error) }
}

# --- remove a saved profile: never the active one, cleans router state ---
New-Item -ItemType Directory -Force -Path (Join-Path $parallel 'profiles\codex4') | Out-Null
$null = Set-CodexProfileSticky -Name 'codex4' -Workspace (Join-Path $tmp 'mainbak') -ParallelRoot $parallel
$null = Set-CodexProfileDepleted -Name 'codex4' -ParallelRoot $parallel
$desk = Join-Path $tmp 'desk'
New-Item -ItemType Directory -Force -Path $desk | Out-Null
[IO.File]::WriteAllText((Join-Path $desk 'Codex4.lnk'), 'x')
$refused = $false
try { $null = Remove-CodexProfile -Name 'codex1' -ParallelRoot $parallel -DesktopDir $desk } catch { $refused = $true }
if (-not $refused) { throw 'must refuse removing the active profile' }
if (-not (Test-Path -LiteralPath (Join-Path $parallel 'profiles\codex1'))) { throw 'active profile folder was touched' }
$unknown = $false
try { $null = Remove-CodexProfile -Name 'ghost' -ParallelRoot $parallel -DesktopDir $desk } catch { $unknown = $true }
if (-not $unknown) { throw 'must refuse unknown profile' }
$gone = Remove-CodexProfile -Name 'codex4' -ParallelRoot $parallel -DesktopDir $desk
if (-not $gone.Removed) { throw 'remove result' }
if (Test-Path -LiteralPath (Join-Path $parallel 'profiles\codex4')) { throw 'profile folder still there' }
if (Test-Path -LiteralPath (Join-Path $desk 'Codex4.lnk')) { throw 'desktop shortcut still there' }
$rs = Get-CodexRouterState -ParallelRoot $parallel
if ($rs.profiles.ContainsKey('codex4')) { throw 'router meta not cleaned' }
if (@($rs.stickies.Values | Where-Object { $_ -eq 'codex4' }).Count -gt 0) { throw 'sticky not cleaned' }
if (@(Get-CodexKnownProfileNames -ParallelRoot $parallel) -contains 'codex4') { throw 'still listed' }
if (-not (Test-Path -LiteralPath (Join-Path $shared 'auth.json'))) { throw 'remove must never touch the shared home' }

# --- injected UI: CSP / Trusted Types safe, no network, same binding as the host ---
$jsPath = Join-Path $repo 'scripts\switcher-inject.js'
Assert-NoBom $jsPath
$js = Get-Content -LiteralPath $jsPath -Raw -Encoding UTF8
$binding = Get-CodexSwitcherBindingName
if ($js -notmatch ("'" + $binding + "'")) { throw 'switcher JS must call the host binding' }
foreach ($bad in @('innerHTML', 'outerHTML', 'insertAdjacentHTML', 'eval(', 'new Function', 'fetch(', 'XMLHttpRequest', 'new WebSocket', 'sendBeacon', 'WindowsApps')) {
    if ($js.Contains($bad)) { throw "switcher JS must not use $bad" }
}
foreach ($need in @('attachShadow', '__cmpSwitcher', 'Ctrl+Alt+A', 'AltGraph', 'receive', '[role="menu"]', "type: 'remove'", "type: 'add'", 'data-codex-multi-profile')) {
    if (-not $js.Contains($need)) { throw "switcher JS missing $need" }
}

# --- host bridge ---
$hostPath = Join-Path $repo 'scripts\Start-CodexSwitcherHost.ps1'
Assert-NoBom $hostPath
$hs = Get-Content -LiteralPath $hostPath -Raw -Encoding UTF8
foreach ($bad in @('??', ' && ', ' || ', 'HttpListener', 'TcpListener')) {
    if ($hs.Contains($bad)) { throw "host must not use $bad" }
}
if ($hs -match 'Start-Process[^\n]*ChatGPT\.exe') { throw 'host must never Start-Process ChatGPT.exe' }
foreach ($need in @('Remove-CodexProfile', 'remove-active', 'New-SwitcherProfile', 'Test-CodexCdpOwnerIsClone', 'Runtime.addBinding', 'Runtime.bindingCalled', 'Launch-CodexProfile.ps1', '-FastSwitch', 'ConvertFrom-CodexSwitcherMessage', 'Test-CodexTextHasFullEmail', 'Test-CodexStoreRunning')) {
    if (-not $hs.Contains($need)) { throw "host missing $need" }
}
. $hostPath
if (-not (Test-LoopbackWsUrl 'ws://127.0.0.1:9333/devtools/page/AB')) { throw 'loopback ws rejected' }
foreach ($remote in @('ws://10.0.0.5:9333/devtools/page/AB', 'ws://evil.example/devtools', 'wss://127.0.0.1.evil.example:1/x')) {
    if (Test-LoopbackWsUrl $remote) { throw "non-loopback ws accepted: $remote" }
}

# --- launcher wiring: host only when enabled, still the .cmd wrapper ---
$ls = Get-Content -LiteralPath (Join-Path $repo 'scripts\Launch-CodexProfile.ps1') -Raw -Encoding UTF8
foreach ($need in @('Start-CodexSwitcherHost.ps1', 'Stop-CodexSwitcherHosts', 'Get-CodexCdpLaunchPort', '$switcherOn', 'New-CodexEnvCmd')) {
    if (-not $ls.Contains($need)) { throw "launcher missing $need" }
}
$pack = @(Get-CodexPackagedScriptNames)
foreach ($need in @('Start-CodexSwitcherHost.ps1', 'switcher-inject.js')) {
    if ($pack -notcontains $need) { throw "Get-CodexPackagedScriptNames missing $need" }
}
$mgr = Get-Content -LiteralPath (Join-Path $repo 'scripts\CodexProfile.ps1') -Raw -Encoding UTF8
if ($mgr -notmatch "'switcher'") { throw 'CodexProfile.ps1 missing -Action switcher' }
$appSrc = Get-Content -LiteralPath (Join-Path $repo 'scripts\Show-CodexAccountApp.ps1') -Raw -Encoding UTF8
if ($appSrc -notmatch 'Set-CodexSwitcherEnabled') { throw 'Codex Accounts must offer the in-app toggle' }

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Output 'OK: in-app switcher off by default, masked snapshot, strict message validation, safe JS, loopback-only host.'
