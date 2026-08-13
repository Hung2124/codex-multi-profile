# Restore main Codex account auth then open Store Codex.
# CRITICAL: if AuthSwap is active, save secondary auth FIRST (before restore),
# otherwise watcher / restore poisons profiles/<name>/auth.json with the main account.
$ErrorActionPreference = 'Stop'
$SourceHome = Join-Path $env:USERPROFILE '.codex'
$ParallelRoot = Join-Path $env:LOCALAPPDATA 'CodexParallelDesktop'
$mainAuth = Join-Path $SourceHome 'auth.json'
$mainAuthBak = Join-Path $SourceHome 'auth.json.__main__'
$swapLock = Join-Path $ParallelRoot '.authswap-active'
$log = Join-Path $ParallelRoot 'launch-trace.log'

function L([string]$m) { Add-Content -LiteralPath $log -Value "$(Get-Date -Format HH:mm:ss.fff) [main] $m" -EA SilentlyContinue }
function EmailOf([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return 'MISSING' }
    try {
        $j = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $payload = $j.tokens.id_token.Split('.')[1].Replace('-', '+').Replace('_', '/')
        while ($payload.Length % 4) { $payload += '=' }
        $c = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
        return [string]$c.email
    } catch { return 'PARSE_ERR' }
}

L 'Launch-CodexMain start'

# If swap active: save current (~ secondary) auth to profile BEFORE restoring main
if (Test-Path -LiteralPath $swapLock) {
    $key = (Get-Content -LiteralPath $swapLock -Raw -EA SilentlyContinue).Trim()
    if ($key) {
        $profileAuth = Join-Path $ParallelRoot "profiles\$key\auth.json"
        $profileBak = Join-Path $ParallelRoot "profiles\$key\auth.json.secondary.bak"
        $active = EmailOf $mainAuth
        $mainEmail = EmailOf $mainAuthBak
        L "swap active key=$key active=$active mainBak=$mainEmail"
        if ((Test-Path -LiteralPath $mainAuth) -and $active -ne 'MISSING' -and $active -ne $mainEmail) {
            New-Item -ItemType Directory -Force -Path (Split-Path $profileAuth) | Out-Null
            Copy-Item -LiteralPath $mainAuth -Destination $profileAuth -Force
            Copy-Item -LiteralPath $mainAuth -Destination $profileBak -Force
            $mirror = Join-Path $ParallelRoot "profiles\$key\.codex\auth.json"
            New-Item -ItemType Directory -Force -Path (Split-Path $mirror) | Out-Null
            Copy-Item -LiteralPath $mainAuth -Destination $mirror -Force
            L "saved secondary to profile before restore -> $active"
        } else {
            L "skip profile save (active is main or missing)"
        }
    }
}

# Close clones so Store activation is not redirected to clone
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -like '*CodexParallelDesktop*' -and $_.Name -match '^(ChatGPT|codex)(-code-mode-host)?\.exe$' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 1

if (Test-Path -LiteralPath $mainAuthBak) {
    Copy-Item -LiteralPath $mainAuthBak -Destination $mainAuth -Force
    Remove-Item -LiteralPath $mainAuthBak -Force -EA SilentlyContinue
    L "restored main -> $(EmailOf $mainAuth)"
}
Remove-Item -LiteralPath $swapLock -Force -EA SilentlyContinue

$appId = 'shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App'
Start-Process explorer.exe $appId
Write-Output 'Main auth restored; clones closed; launching the real Store Codex.'
