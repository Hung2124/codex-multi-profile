# ShareLive AuthSwap launcher
# Data luon o %USERPROFILE%\.codex; chi HOAN DOI auth.json theo profile.
# Tranh loi app-server bo qua CODEX_HOME -> hien nham acc goc.
param(
    [string]$Name = 'codex1',
    [string]$SourceHome = (Join-Path $env:USERPROFILE '.codex'),
    [switch]$BootstrapLogin  # force login screen for secondary account
)

$ErrorActionPreference = 'Stop'
$ParallelRoot = Join-Path $env:LOCALAPPDATA 'CodexParallelDesktop'
$key = ($Name.Trim().ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
if (-not $key) { throw 'Ten profile khong hop le.' }

$root = Join-Path $ParallelRoot "profiles\$key"
$profileAuth = Join-Path $root 'auth.json'              # canonical profile account
$profileAuthMirror = Join-Path $root '.codex\auth.json' # mirror (optional)
$profileAuthBak = Join-Path $root 'auth.json.secondary.bak'
$mainAuth = Join-Path $SourceHome 'auth.json'
$mainAuthBak = Join-Path $SourceHome 'auth.json.__main__'
$swapLock = Join-Path $ParallelRoot '.authswap-active'
$log = Join-Path $ParallelRoot 'launch-trace.log'
$ElectronData = $root

function L([string]$m) { Add-Content -LiteralPath $log -Value "$(Get-Date -Format HH:mm:ss.fff) $m" -EA SilentlyContinue }

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

function Stop-AllCodex {
    Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'" -EA SilentlyContinue | ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue
    }
    Get-CimInstance Win32_Process -EA SilentlyContinue |
        Where-Object { $_.ExecutablePath -like '*CodexParallelDesktop*' -and $_.Name -match 'ChatGPT|codex' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue }
}

function Restore-MainAuth {
    if (Test-Path -LiteralPath $mainAuthBak) {
        Copy-Item -LiteralPath $mainAuthBak -Destination $mainAuth -Force
        Remove-Item -LiteralPath $mainAuthBak -Force -EA SilentlyContinue
        L "restored main auth -> $(EmailOf $mainAuth)"
    }
    Remove-Item -LiteralPath $swapLock -Force -EA SilentlyContinue
}

try {
    Remove-Item -LiteralPath $log -Force -EA SilentlyContinue
    L "authswap launch $key bootstrap=$BootstrapLogin"

    New-Item -ItemType Directory -Force -Path $root, (Join-Path $root '.codex') | Out-Null

    # Recover from secondary.bak if canonical profile auth missing
    if (-not (Test-Path -LiteralPath $profileAuth)) {
        if (Test-Path -LiteralPath $profileAuthBak) {
            Copy-Item -LiteralPath $profileAuthBak -Destination $profileAuth -Force
            L 'recovered profile auth from secondary.bak'
        } elseif (Test-Path -LiteralPath $profileAuthMirror) {
            Copy-Item -LiteralPath $profileAuthMirror -Destination $profileAuth -Force
            L 'recovered profile auth from .codex mirror'
        }
    }

    $mainEmailNow = EmailOf $mainAuth
    $profileEmail = EmailOf $profileAuth

    # If profile auth is missing OR same as main -> need bootstrap login
    $needBootstrap = $BootstrapLogin -or ($profileEmail -eq 'MISSING') -or ($profileEmail -eq $mainEmailNow -and $mainEmailNow -ne 'MISSING')
    if ($needBootstrap -and -not $BootstrapLogin -and $profileEmail -ne 'MISSING' -and $profileEmail -eq $mainEmailNow) {
        L "WARN profile auth same as main ($profileEmail) -> bootstrap login"
        # Quarantine poisoned auth
        if (Test-Path -LiteralPath $profileAuth) {
            Move-Item -LiteralPath $profileAuth -Destination "$profileAuth.corrupted-same-as-main-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force
        }
        Remove-Item -LiteralPath $profileAuthMirror -Force -EA SilentlyContinue
        $needBootstrap = $true
    }

    if (-not $needBootstrap) {
        Copy-Item -LiteralPath $profileAuth -Destination $profileAuthMirror -Force
        # Keep a durable secondary backup whenever profile differs from main
        if ($profileEmail -ne $mainEmailNow) {
            Copy-Item -LiteralPath $profileAuth -Destination $profileAuthBak -Force
        }
    }

    L "profile auth=$(EmailOf $profileAuth) needBootstrap=$needBootstrap"
    L "main auth before=$mainEmailNow"

    Stop-AllCodex
    Start-Sleep -Seconds 2

    # If previous swap crashed, restore first
    if ((Test-Path -LiteralPath $swapLock) -and (Test-Path -LiteralPath $mainAuthBak)) {
        L 'found stale swap lock -> restore main first'
        Restore-MainAuth
    }

    # Backup main auth
    if (-not (Test-Path -LiteralPath $mainAuthBak)) {
        if (-not (Test-Path -LiteralPath $mainAuth)) { throw "Thieu main auth: $mainAuth" }
        Copy-Item -LiteralPath $mainAuth -Destination $mainAuthBak -Force
    }

    if ($needBootstrap) {
        # Clear active auth so Codex shows login for secondary account
        Remove-Item -LiteralPath $mainAuth -Force -EA SilentlyContinue
        L 'bootstrap: cleared ~/.codex/auth.json for secondary login'
        try {
            Add-Type -AssemblyName System.Windows.Forms
            [System.Windows.Forms.MessageBox]::Show(
                "Sign in with the SECONDARY ChatGPT account (not the main one).`n`nAfter login, CLOSE this Codex window — auth is saved for next launch.`n`nDo not open the main Codex shortcut while this login is in progress.",
                'Codex profile — secondary account login',
                'OK',
                'Information'
            ) | Out-Null
        } catch { }
    } else {
        Copy-Item -LiteralPath $profileAuth -Destination $mainAuth -Force
        L "swapped in profile auth -> $(EmailOf $mainAuth)"
    }

    Set-Content -LiteralPath $swapLock -Value $key -Encoding ASCII

    # Find clone
    $versionsRoot = Join-Path $ParallelRoot 'versions'
    $cloneExe = Get-ChildItem -LiteralPath $versionsRoot -Directory -EA SilentlyContinue |
        Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName 'app\ChatGPT.exe' } |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
    if (-not $cloneExe) { throw "Khong tim thay clone ChatGPT.exe trong $versionsRoot" }
    $cloneApp = Split-Path -Parent $cloneExe

    $cmd = @"
@echo off
set "CODEX_HOME=$SourceHome"
set "CODEX_ELECTRON_USER_DATA_PATH=$ElectronData"
set "OPENAI_BASE_URL="
set "OPENAI_API_KEY="
set "ANTHROPIC_BASE_URL="
set "ANTHROPIC_API_KEY="
set "CODEX_THREAD_ID="
start "" /D "$cloneApp" "$cloneExe" --user-data-dir="$root"
"@
    $cmdPath = Join-Path $ParallelRoot ("launch-{0}-env.cmd" -f $key)
    [IO.File]::WriteAllText($cmdPath, $cmd, (New-Object System.Text.UTF8Encoding $false))
    Start-Process -FilePath $cmdPath -WindowStyle Hidden | Out-Null
    Start-Sleep -Seconds 5

    $proc = Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'" -EA SilentlyContinue |
        Where-Object { $_.ExecutablePath -like '*CodexParallelDesktop*' -or $_.CommandLine -like "*profiles\$key*" } |
        Select-Object -First 1
    if (-not $proc) { throw 'Codex profile khong start.' }
    L "started pid=$($proc.ProcessId) sharedHome=$SourceHome activeAuth=$(EmailOf $mainAuth)"

    $watcher = Join-Path $ParallelRoot 'watch-authswap-restore.ps1'
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $watcher,
        '-ProfileKey', $key,
        '-SourceHome', $SourceHome,
        '-ProfileAuth', $profileAuth,
        '-MainAuth', $mainAuth,
        '-MainAuthBak', $mainAuthBak,
        '-SwapLock', $swapLock,
        '-LogPath', $log
    ) | Out-Null

    L 'DONE ok authswap'
    $msg = if ($needBootstrap) { "BOOTSTRAP login — dang nhap ACC PHU roi dong app" } else { "AuthSwap activeAuth=$(EmailOf $mainAuth)" }
    Write-Output "Launched $key $msg pid=$($proc.ProcessId)"
}
catch {
    L ("ERROR: " + $_.Exception.Message)
    try { Restore-MainAuth } catch { }
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, $key, 'OK', 'Error') | Out-Null
    } catch { }
    throw
}
