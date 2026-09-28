#Requires -Version 5.1
# Host target discovery (Windows PowerShell 5.1 JSON arrays) and the injected script's safety rules.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

function Assert([bool]$Cond, [string]$Msg) { if (-not $Cond) { throw "FAIL: $Msg" } }

# Dot-sourcing the host loads its functions without starting Codex.
. (Join-Path $repo 'scripts\Start-CodexAccounts.ps1')

# What Codex 26.9xx answers on /json/list: main window + a hidden detached (Mini) window.
$json = @'
[ {
   "id": "D1", "type": "page", "title": "ChatGPT",
   "url": "app://-/detached-window.html?initialRoute=%2Fdetached-window",
   "webSocketDebuggerUrl": "ws://127.0.0.1:9333/devtools/page/D1"
}, {
   "id": "M1", "type": "page", "title": "Codex",
   "url": "app://-/index.html",
   "webSocketDebuggerUrl": "ws://127.0.0.1:9333/devtools/page/M1"
}, {
   "id": "O1", "type": "page", "title": "ChatGPT",
   "url": "app://-/index.html?initialRoute=%2Favatar-overlay",
   "webSocketDebuggerUrl": "ws://127.0.0.1:9333/devtools/page/O1"
}, {
   "id": "X1", "type": "page", "title": "evil",
   "url": "app://-/index.html",
   "webSocketDebuggerUrl": "ws://10.0.0.5:9333/devtools/page/X1"
} ]
'@
$pages = @(Select-CdpMainPages -Json $json -CdpPort 9333)
Assert ($pages.Count -eq 1) "exactly one main page found (got $($pages.Count)) - PS 5.1 array unrolling"
Assert ($pages[0].id -eq 'M1') 'main window picked; Mini, avatar-overlay and non-loopback pages skipped'
$single = @(Select-CdpMainPages -Json '[{"id":"M1","type":"page","url":"app://-/index.html","webSocketDebuggerUrl":"ws://127.0.0.1:9333/devtools/page/M1"}]' -CdpPort 9333)
Assert ($single.Count -eq 1) 'single-element array'

$js = Get-Content -LiteralPath (Join-Path $repo 'scripts\switcher-inject.js') -Raw -Encoding UTF8
foreach ($bad in @('innerHTML', 'outerHTML', 'insertAdjacentHTML', 'eval(', 'new Function', 'fetch(', 'XMLHttpRequest', 'WebSocket', 'document.write')) {
    Assert (-not $js.Contains($bad)) "switcher-inject.js must not use $bad"
}
Import-Module (Join-Path $repo 'scripts\CodexAccounts.psm1') -Force
Assert ($js.Contains("var BINDING = '" + (Get-CodexSwitcherBindingName) + "'")) 'binding name matches the host'
foreach ($type in @("type: 'switch'", "type: 'add'", "type: 'remove'", "type: 'rename'", "type: 'cancel-add'", "type: 'depleted'")) {
    Assert ($js.Contains($type)) "page sends $type"
}
Assert (-not $js.Contains("type: 'main'")) 'no clone-era main row'
Assert ($js.Contains("'data-codex-character-input-boundary'")) 'dialog inputs opt out of Codex type-to-focus'

# The page script must be read as a plain string: a Get-Content string carries PSProvider/PSDrive note properties
# that ConvertTo-Json -Depth 8 serializes into GBs (the helper hung after every Codex reload).
$hostText = Get-Content -LiteralPath (Join-Path $repo 'scripts\Start-CodexAccounts.ps1') -Raw
Assert ($hostText -notmatch "Get-Content[^
]*switcher-inject\.js") 'helper reads switcher-inject.js with ReadAllText'
Assert ($hostText.Contains("[string]`$Params['expression']")) 'CDP expressions are sent as plain strings'

# Watcher: compiles with the .NET Framework compiler and looks for the helper under the mutex the helper holds.
$watcherSrc = Get-Content -LiteralPath (Join-Path $repo 'scripts\CodexAccountsWatcher.cs') -Raw
$hostSrc = Get-Content -LiteralPath (Join-Path $repo 'scripts\Start-CodexAccounts.ps1') -Raw
Assert ($watcherSrc.Contains('@"Local\CodexMultiProfileHost"') -and $hostSrc.Contains("'Local\CodexMultiProfileHost'")) 'watcher and helper use the same mutex'
$exe = Join-Path $env:TEMP ('cmp-watcher-' + [guid]::NewGuid().ToString('n') + '.exe')
try { Add-Type -TypeDefinition $watcherSrc -OutputAssembly $exe -OutputType WindowsApplication; Assert (Test-Path -LiteralPath $exe) 'watcher compiles' }
finally { Remove-Item -LiteralPath $exe -ErrorAction SilentlyContinue }

$node = Get-Command node -ErrorAction SilentlyContinue
if ($node) {
    & $node.Source --check (Join-Path $repo 'scripts\switcher-inject.js')
    if ($LASTEXITCODE) { throw 'FAIL: switcher-inject.js syntax' }
}
Write-Output 'OK: host picks the Codex main window on PS 5.1, injected script stays DOM-only, watcher compiles and matches the helper.'
