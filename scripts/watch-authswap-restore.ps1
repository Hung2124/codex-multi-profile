# AuthSwap close watcher — NEVER overwrite profile auth with main account.
param(
    [string]$ProfileKey,
    [string]$SourceHome,
    [string]$ProfileAuth,
    [string]$MainAuth,
    [string]$MainAuthBak,
    [string]$SwapLock,
    [string]$LogPath
)

$ErrorActionPreference = 'Continue'

function L([string]$m) {
    if ($LogPath) {
        Add-Content -LiteralPath $LogPath -Value "$(Get-Date -Format HH:mm:ss.fff) [watch] $m" -EA SilentlyContinue
    }
}

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

Start-Sleep -Seconds 8
while ($true) {
    $running = @(Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'" -EA SilentlyContinue |
        Where-Object { $_.ExecutablePath -like '*CodexParallelDesktop*' -or $_.CommandLine -like "*profiles\$ProfileKey*" })
    if ($running.Count -eq 0) { break }
    Start-Sleep -Seconds 3
}

$activeEmail = EmailOf $MainAuth
$mainEmail = EmailOf $MainAuthBak
$prevProfileEmail = EmailOf $ProfileAuth
L "close detected active=$activeEmail mainBak=$mainEmail prevProfile=$prevProfileEmail"

# Only save back to profile if active auth is a DIFFERENT account than main backup.
# This prevents Codex Goc / Store restore from poisoning profile auth.
$shouldSave = $false
if ((Test-Path -LiteralPath $MainAuth) -and $activeEmail -ne 'MISSING' -and $activeEmail -ne 'PARSE_ERR') {
    if ($mainEmail -eq 'MISSING' -or $activeEmail -ne $mainEmail) {
        $shouldSave = $true
    }
}

if ($shouldSave) {
    $bak = "$ProfileAuth.secondary.bak"
    if (Test-Path -LiteralPath $ProfileAuth) {
        Copy-Item -LiteralPath $ProfileAuth -Destination $bak -Force -EA SilentlyContinue
    }
    Copy-Item -LiteralPath $MainAuth -Destination $ProfileAuth -Force -EA SilentlyContinue
    $mirror = Join-Path (Split-Path $ProfileAuth) '.codex\auth.json'
    New-Item -ItemType Directory -Force -Path (Split-Path $mirror) -EA SilentlyContinue | Out-Null
    Copy-Item -LiteralPath $MainAuth -Destination $mirror -Force -EA SilentlyContinue
    Copy-Item -LiteralPath $MainAuth -Destination $bak -Force -EA SilentlyContinue
    L "saved profile auth -> $activeEmail"
} else {
    L "SKIP save profile (active looks like main or invalid) — keep prev=$prevProfileEmail"
}

# Restore main account
if (Test-Path -LiteralPath $MainAuthBak) {
    Copy-Item -LiteralPath $MainAuthBak -Destination $MainAuth -Force -EA SilentlyContinue
    Remove-Item -LiteralPath $MainAuthBak -Force -EA SilentlyContinue
    L "restored main -> $(EmailOf $MainAuth)"
}
Remove-Item -LiteralPath $SwapLock -Force -EA SilentlyContinue
L 'swap lock cleared'
