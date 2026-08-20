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

$tmp = Join-Path $env:TEMP ('cmp-router-' + [guid]::NewGuid().ToString('n'))
$parallel = Join-Path $tmp 'root'
$wsGit = Join-Path $tmp 'proj'
$wsOther = Join-Path $tmp 'other'
New-Item -ItemType Directory -Force -Path $wsGit, $wsOther, (Join-Path $wsGit '.git') | Out-Null
$wsGit = (Get-Item -LiteralPath $wsGit).FullName.TrimEnd('\')
$wsOther = (Get-Item -LiteralPath $wsOther).FullName.TrimEnd('\')
New-FakeAuth -Dir (Join-Path $parallel 'profiles\codex1') -Email 'alt@example.com'
New-FakeAuth -Dir (Join-Path $parallel 'profiles\codex2') -Email 'work@example.com'

$layer = Get-CodexLayerState -ParallelRoot $parallel
if ($layer.Enabled) { throw 'layer must be off by default' }

$dir = Join-Path $tmp 'cmd'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$cmdPath = Join-Path $dir 'launch-codex1-env.cmd'
New-CodexEnvCmd -CmdPath $cmdPath -CodexHome 'C:\Users\me\.codex' -UserDataDir 'C:\p\codex1' -CloneApp 'C:\clone\app' -CloneExe 'C:\clone\app\ChatGPT.exe'
$cmdText = Get-Content -LiteralPath $cmdPath -Raw -Encoding UTF8
if ($cmdText -match 'remote-debugging') { throw 'default env cmd must not enable CDP' }
Assert-NoBom $cmdPath

New-CodexEnvCmd -CmdPath $cmdPath -CodexHome 'C:\Users\me\.codex' -UserDataDir 'C:\p\codex1' -CloneApp 'C:\clone\app' -CloneExe 'C:\clone\app\ChatGPT.exe' -RemoteDebuggingPort 9222
$cmdOn = Get-Content -LiteralPath $cmdPath -Raw -Encoding UTF8
if ($cmdOn -notmatch 'remote-debugging-address=127.0.0.1') { throw 'layer cmd must bind to 127.0.0.1' }
if ($cmdOn -notmatch 'remote-debugging-port=9222') { throw 'layer cmd missing port' }
if ($cmdOn -match 'WindowsApps') { throw 'env cmd must never point at WindowsApps' }

$js = Get-Content -LiteralPath (Join-Path $repo 'scripts\layer-inject.js') -Raw -Encoding UTF8
if ($js -notmatch 'cmp-layer-badge') { throw 'layer JS missing badge' }
if ($js -notmatch 'details') { throw 'layer JS must keep details open' }
if ($js -notmatch '1200px') { throw 'layer JS missing wider transcript' }

$gitKey = Get-CodexWorkspaceKey -Path (Join-Path $wsGit 'src')
if ($gitKey -ne $wsGit) { throw "git key $gitKey" }
$plainKey = Get-CodexWorkspaceKey -Path $wsOther
if ($plainKey -ne $wsOther) { throw "plain key $plainKey" }

$set = Set-CodexProfileSticky -Name 'codex1' -Workspace $wsGit -ParallelRoot $parallel
if ($set.Profile -ne 'codex1') { throw 'stick name' }
$pool = @(Get-CodexProfilePool -ParallelRoot $parallel)
if ($pool.Count -ne 2) { throw 'pool size' }
$p1 = $pool | Where-Object { $_.Name -eq 'codex1' } | Select-Object -First 1
if ($p1.Account -ne 'al***@example.com') { throw "masked $($p1.Account)" }
if ($p1.Depleted) { throw 'fresh profile must not be depleted' }
$poolJson = $pool | ConvertTo-Json -Depth 6 -Compress
if ($poolJson -match 'alt@example.com' -or $poolJson -match 'work@example.com') {
    throw 'pool leaked a full email'
}

$r1 = Resolve-CodexRoute -Workspace $wsGit -ParallelRoot $parallel
if ($r1.Profile -ne 'codex1') { throw "sticky pick $($r1.Profile)" }
if ($r1.Reason -ne 'sticky') { throw "reason $($r1.Reason)" }

$r2 = Resolve-CodexRoute -Workspace $wsOther -ParallelRoot $parallel
if ($r2.Reason -ne 'lru') { throw 'expected lru without sticky' }
if ($r2.Profile -notin @('codex1', 'codex2')) { throw 'lru must pick a known profile' }

Set-CodexProfileLastUsed -Name 'codex1' -ParallelRoot $parallel -When ([datetime]'2020-01-01T00:00:00Z')
Set-CodexProfileLastUsed -Name 'codex2' -ParallelRoot $parallel -When ([datetime]'2024-01-01T00:00:00Z')
$r3 = Resolve-CodexRoute -Workspace $wsOther -ParallelRoot $parallel
if ($r3.Profile -ne 'codex1') { throw "LRU should pick oldest lastUsed (codex1), got $($r3.Profile)" }

$null = Set-CodexProfileDepleted -Name 'codex1' -ParallelRoot $parallel
$r4 = Resolve-CodexRoute -Workspace $wsGit -ParallelRoot $parallel
if ($r4.Profile -ne 'codex2') { throw "failover $($r4.Profile)" }
if ($r4.Reason -ne 'failover') { throw "failover reason $($r4.Reason)" }
if (-not $r4.Failover) { throw 'Failover flag' }
if ($r4.DepletedOwner -ne 'codex1') { throw 'DepletedOwner' }

$null = Set-CodexProfileDepleted -Name 'codex2' -ParallelRoot $parallel
$r5 = Resolve-CodexRoute -Workspace $wsGit -ParallelRoot $parallel
if ($r5.Reason -ne 'all-depleted') { throw "all-depleted $($r5.Reason)" }
if ($r5.Profile) { throw 'all-depleted must not pick' }
if ($r5.Message -notmatch 'All profiles') { throw 'combined depleted message' }
if ($r5.Message -match 'alt@example.com') { throw 'depleted message leaked email' }

$null = Set-CodexProfileDepleted -Name 'codex2' -ParallelRoot $parallel -Clear
if (Test-CodexProfileDepleted -Name 'codex2' -State (Get-CodexRouterState -ParallelRoot $parallel)) {
    throw 'cleared profile still depleted'
}

Assert-NoBom (Get-CodexRouterStatePath -ParallelRoot $parallel)

$layerOn = Set-CodexLayerEnabled -ParallelRoot $parallel
if (-not $layerOn.Enabled) { throw 'layer enable' }
Assert-NoBom (Join-Path $parallel 'layer-state.json')
$layerOff = Set-CodexLayerEnabled -ParallelRoot $parallel -Disable
if ($layerOff.Enabled) { throw 'layer disable' }

$cfg = Join-Path $tmp 'config.toml'
$before = "model = `"gpt`"`n"
Write-Utf8NoBom -Path $cfg -Text $before
$result = Update-CodexChatGptWebModels -ConfigPath $cfg -BridgeUrl 'http://127.0.0.1:1455/v1'
if (-not $result.Enabled) { throw 'models enable' }
Assert-NoBom $cfg
$toml = Get-Content -LiteralPath $cfg -Raw -Encoding UTF8
foreach ($id in @(Get-CodexChatGptWebModelIds)) {
    if ($toml -notlike "*$id*") { throw "missing model $id" }
}
if ($toml -notmatch 'model_providers.chatgpt-web') { throw 'missing provider' }
if ($toml -notmatch '127.0.0.1:1455') { throw 'missing local bridge' }
if ($toml -notmatch 'model = "gpt"') { throw 'must preserve existing config' }
if (-not (Test-CodexChatGptWebModelsEnabled -ConfigPath $cfg)) { throw 'models enabled detect' }

$off = Update-CodexChatGptWebModels -ConfigPath $cfg -Disable
if ($off.Enabled) { throw 'models disable' }
$after = Get-Content -LiteralPath $cfg -Raw -Encoding UTF8
if ($after -match 'chatgpt-web/luna') { throw 'disable must remove model block' }
if ($after -notmatch 'model = "gpt"') { throw 'disable must keep other config' }
Assert-NoBom $cfg

$pack = @(Get-CodexPackagedScriptNames)
foreach ($need in @('CodexRouter.psm1', 'Start-CodexLayer.ps1', 'layer-inject.js', 'Show-CodexAccountApp.ps1')) {
    if ($pack -notcontains $need) { throw "Get-CodexPackagedScriptNames missing $need" }
}

Write-Output 'OK: sticky, LRU, depleted failover, no BOM, masked email, models, layer-off-by-default.'
