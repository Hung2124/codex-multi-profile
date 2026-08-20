#Requires -Version 5.1
# AuthSwap close watcher — never overwrite profile auth with the main account.
param(
    [string]$ProfileKey,
    [string]$SourceHome,
    [string]$ProfileAuth,
    [string]$MainAuth,
    [string]$MainAuthBak,
    [string]$SwapLock,
    [string]$LogPath,
    [int]$InitialSleepSeconds = 8
)

$ErrorActionPreference = 'Continue'
$modulePath = Join-Path $PSScriptRoot 'CodexMultiProfile.psm1'
if (Test-Path -LiteralPath $modulePath) {
    Import-Module $modulePath -Force
}

function Write-WatchLog([string]$Message) {
    if ($LogPath) {
        Add-Content -LiteralPath $LogPath -Value "$(Get-Date -Format HH:mm:ss.fff) [watch] $Message" -ErrorAction SilentlyContinue
    }
}

function Get-EmailFallback([string]$Path) {
    if (Get-Command Get-AuthEmailFromFile -ErrorAction SilentlyContinue) {
        return Get-AuthEmailFromFile -Path $Path
    }
    return 'PARSE_ERR'
}

function Get-MaskedEmailFallback([string]$Path) {
    $email = Get-EmailFallback -Path $Path
    if (Get-Command Hide-AuthEmail -ErrorAction SilentlyContinue) {
        return Hide-AuthEmail -Email $email
    }
    return $email
}

if ($InitialSleepSeconds -gt 0) { Start-Sleep -Seconds $InitialSleepSeconds }
while ($true) {
    $running = @(Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.ExecutablePath -like '*CodexParallelDesktop*' -or $_.CommandLine -like "*profiles\$ProfileKey*" })
    if ($running.Count -eq 0) { break }
    Start-Sleep -Seconds 3
}

$activeEmail = Get-EmailFallback $MainAuth
$mainEmail = Get-EmailFallback $MainAuthBak
$prevProfileEmail = Get-EmailFallback $ProfileAuth
Write-WatchLog "close detected active=$(Get-MaskedEmailFallback $MainAuth) mainBak=$(Get-MaskedEmailFallback $MainAuthBak) prevProfile=$(Get-MaskedEmailFallback $ProfileAuth)"

$shouldSave = $false
if (Get-Command Test-ShouldSaveProfileAuth -ErrorAction SilentlyContinue) {
    $shouldSave = Test-ShouldSaveProfileAuth -ActiveEmail $activeEmail -MainBackupEmail $mainEmail
}

if ($shouldSave -and (Test-Path -LiteralPath $MainAuth)) {
    $bak = "$ProfileAuth.secondary.bak"
    if (Test-Path -LiteralPath $ProfileAuth) {
        Copy-Item -LiteralPath $ProfileAuth -Destination $bak -Force -ErrorAction SilentlyContinue
    }
    Copy-Item -LiteralPath $MainAuth -Destination $ProfileAuth -Force -ErrorAction SilentlyContinue
    $mirror = Join-Path (Split-Path $ProfileAuth) '.codex\auth.json'
    New-Item -ItemType Directory -Force -Path (Split-Path $mirror) -ErrorAction SilentlyContinue | Out-Null
    Copy-Item -LiteralPath $MainAuth -Destination $mirror -Force -ErrorAction SilentlyContinue
    Copy-Item -LiteralPath $MainAuth -Destination $bak -Force -ErrorAction SilentlyContinue
    Write-WatchLog "saved profile auth -> $(Get-MaskedEmailFallback $MainAuth)"
}
else {
    Write-WatchLog "SKIP save profile (active looks like main or invalid) — keep prev=$(Get-MaskedEmailFallback $ProfileAuth)"
}

if (Test-Path -LiteralPath $MainAuthBak) {
    Copy-Item -LiteralPath $MainAuthBak -Destination $MainAuth -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $MainAuthBak -Force -ErrorAction SilentlyContinue
    Write-WatchLog "restored main -> $(Get-MaskedEmailFallback $MainAuth)"
}
Remove-Item -LiteralPath $SwapLock -Force -ErrorAction SilentlyContinue
Write-WatchLog 'swap lock cleared'
