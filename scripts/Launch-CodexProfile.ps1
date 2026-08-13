#Requires -Version 5.1
# AuthSwap launcher: shared ~/.codex data, per-profile ChatGPT auth.
param(
    [string]$Name = 'codex1',
    [string]$SourceHome = (Join-Path $env:USERPROFILE '.codex'),
    [switch]$BootstrapLogin
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'CodexMultiProfile.psm1'
if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "Missing $modulePath. Re-run Install-CodexMultiProfile.ps1."
}
Import-Module $modulePath -Force

$ParallelRoot = Get-CodexParallelRoot
$key = ConvertTo-ProfileKey -ProfileName $Name
$root = Join-Path $ParallelRoot "profiles\$key"
$profileAuth = Join-Path $root 'auth.json'
$profileAuthMirror = Join-Path $root '.codex\auth.json'
$profileAuthBak = Join-Path $root 'auth.json.secondary.bak'
$mainAuth = Join-Path $SourceHome 'auth.json'
$mainAuthBak = Join-Path $SourceHome 'auth.json.__main__'
$swapLock = Join-Path $ParallelRoot '.authswap-active'
$log = Join-Path $ParallelRoot 'launch-trace.log'

function Write-LaunchLog([string]$Message) {
    Add-Content -LiteralPath $log -Value "$(Get-Date -Format HH:mm:ss.fff) $Message" -ErrorAction SilentlyContinue
}

function Stop-AllCodex {
    Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'" -ErrorAction SilentlyContinue |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ExecutablePath -like '*CodexParallelDesktop*' -and $_.Name -match 'ChatGPT|codex' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

function Restore-MainAuth {
    if (Test-Path -LiteralPath $mainAuthBak) {
        Copy-Item -LiteralPath $mainAuthBak -Destination $mainAuth -Force
        Remove-Item -LiteralPath $mainAuthBak -Force -ErrorAction SilentlyContinue
        Write-LaunchLog "restored main auth -> $(Hide-AuthEmail -Email (Get-AuthEmailFromFile -Path $mainAuth))"
    }
    Remove-Item -LiteralPath $swapLock -Force -ErrorAction SilentlyContinue
}

try {
    Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
    Write-LaunchLog "authswap launch $key bootstrap=$BootstrapLogin"
    New-Item -ItemType Directory -Force -Path $root, (Join-Path $root '.codex') | Out-Null

    if (-not (Test-Path -LiteralPath $profileAuth)) {
        if (Test-Path -LiteralPath $profileAuthBak) {
            Copy-Item -LiteralPath $profileAuthBak -Destination $profileAuth -Force
            Write-LaunchLog 'recovered profile auth from secondary.bak'
        }
        elseif (Test-Path -LiteralPath $profileAuthMirror) {
            Copy-Item -LiteralPath $profileAuthMirror -Destination $profileAuth -Force
            Write-LaunchLog 'recovered profile auth from .codex mirror'
        }
    }

    $mainEmailNow = Get-AuthEmailFromFile -Path $mainAuth
    $profileEmail = Get-AuthEmailFromFile -Path $profileAuth
    $needBootstrap = Test-NeedBootstrapLogin -ProfileEmail $profileEmail -MainEmail $mainEmailNow -Force:$BootstrapLogin

    if ($needBootstrap -and -not $BootstrapLogin -and $profileEmail -ne 'MISSING' -and $profileEmail -eq $mainEmailNow) {
        Write-LaunchLog "WARN profile auth same as main ($(Hide-AuthEmail -Email $profileEmail)) -> bootstrap"
        if (Test-Path -LiteralPath $profileAuth) {
            Move-Item -LiteralPath $profileAuth -Destination "$profileAuth.corrupted-same-as-main-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force
        }
        Remove-Item -LiteralPath $profileAuthMirror -Force -ErrorAction SilentlyContinue
        $needBootstrap = $true
    }

    if (-not $needBootstrap) {
        Copy-Item -LiteralPath $profileAuth -Destination $profileAuthMirror -Force
        if ($profileEmail -ne $mainEmailNow) {
            Copy-Item -LiteralPath $profileAuth -Destination $profileAuthBak -Force
        }
    }

    Write-LaunchLog "profile auth=$(Hide-AuthEmail -Email (Get-AuthEmailFromFile -Path $profileAuth)) needBootstrap=$needBootstrap"
    Write-LaunchLog "main auth before=$(Hide-AuthEmail -Email $mainEmailNow)"

    Stop-AllCodex
    Start-Sleep -Seconds 2

    if ((Test-Path -LiteralPath $swapLock) -and (Test-Path -LiteralPath $mainAuthBak)) {
        Write-LaunchLog 'stale swap lock -> restore main first'
        Restore-MainAuth
    }

    if (-not (Test-Path -LiteralPath $mainAuthBak)) {
        if (-not (Test-Path -LiteralPath $mainAuth)) { throw "Missing main auth: $mainAuth" }
        Copy-Item -LiteralPath $mainAuth -Destination $mainAuthBak -Force
    }

    if ($needBootstrap) {
        Remove-Item -LiteralPath $mainAuth -Force -ErrorAction SilentlyContinue
        Write-LaunchLog 'bootstrap: cleared ~/.codex/auth.json for secondary login'
        try {
            Add-Type -AssemblyName System.Windows.Forms
            [System.Windows.Forms.MessageBox]::Show(
                "Sign in with the SECONDARY ChatGPT account (not the main one).`n`nAfter login, CLOSE this Codex window — auth is saved for next launch.`n`nDo not open Codex Main while this login is in progress.",
                'Codex profile — secondary account login',
                'OK',
                'Information'
            ) | Out-Null
        }
        catch { }
    }
    else {
        Copy-Item -LiteralPath $profileAuth -Destination $mainAuth -Force
        Write-LaunchLog "swapped in profile auth -> $(Hide-AuthEmail -Email (Get-AuthEmailFromFile -Path $mainAuth))"
    }

    Set-Content -LiteralPath $swapLock -Value $key -Encoding ASCII

    $cloneExe = Get-CodexCloneExe -ParallelRoot $ParallelRoot
    $cloneApp = Split-Path -Parent $cloneExe
    $cmdPath = Join-Path $ParallelRoot ("launch-{0}-env.cmd" -f $key)
    New-CodexEnvCmd -CmdPath $cmdPath -CodexHome $SourceHome -UserDataDir $root -CloneApp $cloneApp -CloneExe $cloneExe
    Start-Process -FilePath $cmdPath -WindowStyle Hidden | Out-Null
    Start-Sleep -Seconds 5

    $proc = Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.ExecutablePath -like '*CodexParallelDesktop*' -or $_.CommandLine -like "*profiles\$key*" } |
        Select-Object -First 1
    if (-not $proc) { throw 'Codex profile did not start. Is Codex Desktop installed?' }

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

    Write-LaunchLog 'DONE ok authswap'
    $msg = if ($needBootstrap) { 'BOOTSTRAP login — sign in with the secondary account, then close the app' } else { "AuthSwap activeAuth=$(Hide-AuthEmail -Email (Get-AuthEmailFromFile -Path $mainAuth))" }
    Write-Output "Launched $key $msg pid=$($proc.ProcessId)"
}
catch {
    Write-LaunchLog ("ERROR: " + $_.Exception.Message)
    try { Restore-MainAuth } catch { }
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, $key, 'OK', 'Error') | Out-Null
    }
    catch { }
    throw
}
