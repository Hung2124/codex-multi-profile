#Requires -Version 5.1
# Restore main Codex auth, then open Store Codex.
# If AuthSwap is active, save secondary auth FIRST so restore cannot poison the profile.
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'CodexMultiProfile.psm1'
if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "Missing $modulePath. Re-run Install-CodexMultiProfile.ps1."
}
Import-Module $modulePath -Force

$SourceHome = Join-Path $env:USERPROFILE '.codex'
$ParallelRoot = Get-CodexParallelRoot
$mainAuth = Join-Path $SourceHome 'auth.json'
$mainAuthBak = Join-Path $SourceHome 'auth.json.__main__'
$swapLock = Join-Path $ParallelRoot '.authswap-active'
$log = Join-Path $ParallelRoot 'launch-trace.log'

function Write-LaunchLog([string]$Message) {
    Add-Content -LiteralPath $log -Value "$(Get-Date -Format HH:mm:ss.fff) [main] $Message" -ErrorAction SilentlyContinue
}

Write-LaunchLog 'Launch-CodexMain start'

if (Test-Path -LiteralPath $swapLock) {
    $key = (Get-Content -LiteralPath $swapLock -Raw -ErrorAction SilentlyContinue).Trim()
    if ($key) {
        $profileAuth = Join-Path $ParallelRoot "profiles\$key\auth.json"
        $profileBak = Join-Path $ParallelRoot "profiles\$key\auth.json.secondary.bak"
        $active = Get-AuthEmailFromFile -Path $mainAuth
        $mainEmail = Get-AuthEmailFromFile -Path $mainAuthBak
        Write-LaunchLog "swap active key=$key active=$(Hide-AuthEmail -Email $active) mainBak=$(Hide-AuthEmail -Email $mainEmail)"
        if ((Test-Path -LiteralPath $mainAuth) -and (Test-ShouldSaveProfileAuth -ActiveEmail $active -MainBackupEmail $mainEmail)) {
            New-Item -ItemType Directory -Force -Path (Split-Path $profileAuth) | Out-Null
            Copy-Item -LiteralPath $mainAuth -Destination $profileAuth -Force
            Copy-Item -LiteralPath $mainAuth -Destination $profileBak -Force
            $mirror = Join-Path $ParallelRoot "profiles\$key\.codex\auth.json"
            New-Item -ItemType Directory -Force -Path (Split-Path $mirror) | Out-Null
            Copy-Item -LiteralPath $mainAuth -Destination $mirror -Force
            Write-LaunchLog "saved secondary to profile before restore -> $(Hide-AuthEmail -Email $active)"
        }
        else {
            Write-LaunchLog 'skip profile save (active is main or invalid)'
        }
    }
}

Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -like '*CodexParallelDesktop*' -and $_.Name -match '^(ChatGPT|codex)(-code-mode-host)?\.exe$' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 1

if (Test-Path -LiteralPath $mainAuthBak) {
    Copy-Item -LiteralPath $mainAuthBak -Destination $mainAuth -Force
    Remove-Item -LiteralPath $mainAuthBak -Force -ErrorAction SilentlyContinue
    Write-LaunchLog "restored main -> $(Hide-AuthEmail -Email (Get-AuthEmailFromFile -Path $mainAuth))"
}
Remove-Item -LiteralPath $swapLock -Force -ErrorAction SilentlyContinue

Start-Process explorer.exe 'shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App'
Write-Output 'Main auth restored; clones closed; launching Store Codex.'
