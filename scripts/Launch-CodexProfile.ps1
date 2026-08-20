#Requires -Version 5.1
# AuthSwap launcher: shared ~/.codex data, per-profile ChatGPT auth.
param(
    [string]$Name = 'codex1',
    [string]$SourceHome = (Join-Path $env:USERPROFILE '.codex'),
    [switch]$BootstrapLogin,
    [switch]$FastSwitch
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'CodexMultiProfile.psm1'
if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "Missing $modulePath. Re-run Install-CodexMultiProfile.ps1."
}
Import-Module $modulePath -Force
$routerMod = Join-Path $PSScriptRoot 'CodexRouter.psm1'
if (Test-Path -LiteralPath $routerMod) {
    Import-Module $routerMod -Force
}

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
    $mainBackupEmail = Get-AuthEmailFromFile -Path $mainAuthBak
    $poisonRef = $mainBackupEmail
    if ($poisonRef -eq 'MISSING') { $poisonRef = $mainEmailNow }
    $needBootstrap = Test-NeedBootstrapLogin -ProfileEmail $profileEmail -MainEmail $poisonRef -Force:$BootstrapLogin

    if ($needBootstrap -and -not $BootstrapLogin -and $profileEmail -ne 'MISSING' -and $profileEmail -eq $poisonRef) {
        Write-LaunchLog "WARN profile auth same as main backup ($(Hide-AuthEmail -Email $profileEmail)) -> bootstrap"
        if (Test-Path -LiteralPath $profileAuth) {
            Move-Item -LiteralPath $profileAuth -Destination "$profileAuth.corrupted-same-as-main-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force
        }
        Remove-Item -LiteralPath $profileAuthMirror -Force -ErrorAction SilentlyContinue
        $needBootstrap = $true
    }
    if (-not $needBootstrap -and (Test-Path -LiteralPath $profileAuth)) {
        Write-LaunchLog 'saved profile auth present and not poisoned - no password prompt'
    }

    if (-not $needBootstrap) {
        Copy-Item -LiteralPath $profileAuth -Destination $profileAuthMirror -Force
        if ($profileEmail -ne $mainEmailNow) {
            Copy-Item -LiteralPath $profileAuth -Destination $profileAuthBak -Force
        }
    }

    Write-LaunchLog "profile auth=$(Hide-AuthEmail -Email (Get-AuthEmailFromFile -Path $profileAuth)) needBootstrap=$needBootstrap"
    Write-LaunchLog "main auth before=$(Hide-AuthEmail -Email $mainEmailNow)"

    if (Get-Command Stop-CodexAuthSwapWatchers -ErrorAction SilentlyContinue) {
        $killed = Stop-CodexAuthSwapWatchers
        Write-LaunchLog ("stopped {0} authswap watcher(s)" -f $killed)
    }
    if (Test-Path -LiteralPath $swapLock) {
        $outgoing = (Get-Content -LiteralPath $swapLock -Raw -ErrorAction SilentlyContinue)
        if ($outgoing) { $outgoing = $outgoing.Trim() }
        if ($outgoing -and $outgoing -ne $key -and (Test-Path -LiteralPath $mainAuth)) {
            $activeNow = Get-AuthEmailFromFile -Path $mainAuth
            $bakNow = Get-AuthEmailFromFile -Path $mainAuthBak
            if (Test-ShouldSaveProfileAuth -ActiveEmail $activeNow -MainBackupEmail $bakNow) {
                $outAuth = Join-Path $ParallelRoot "profiles\$outgoing\auth.json"
                New-Item -ItemType Directory -Force -Path (Split-Path $outAuth) | Out-Null
                Copy-Item -LiteralPath $mainAuth -Destination $outAuth -Force
                Write-LaunchLog ("saved outgoing {0} before switch -> {1}" -f $outgoing, (Hide-AuthEmail -Email $activeNow))
            }
        }
    }

    Stop-AllCodex
    if ($FastSwitch) { Start-Sleep -Milliseconds 300 }
    else { Start-Sleep -Seconds 2 }

    if ((Test-Path -LiteralPath $swapLock) -and (Test-Path -LiteralPath $mainAuthBak) -and -not $FastSwitch) {
        Write-LaunchLog 'stale swap lock -> restore main first'
        Restore-MainAuth
    }
    elseif ((Test-Path -LiteralPath $swapLock) -and $FastSwitch) {
        Write-LaunchLog 'fast switch: keep main backup, overwrite active auth with chosen profile'
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
                "Sign in with the SECONDARY ChatGPT account (not the main one).`n`nAfter login, CLOSE this Codex window - auth is saved for next launch.`n`nDo not open Codex Main while this login is in progress.",
                'Codex profile - secondary account login',
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
    $cdpPort = 0
    if (Get-Command Get-CodexLayerState -ErrorAction SilentlyContinue) {
        $layerState = Get-CodexLayerState -ParallelRoot $ParallelRoot
        if ($layerState.Enabled) { $cdpPort = [int]$layerState.CdpPort }
    }
    New-CodexEnvCmd -CmdPath $cmdPath -CodexHome $SourceHome -UserDataDir $root -CloneApp $cloneApp -CloneExe $cloneExe -RemoteDebuggingPort $cdpPort
    Start-Process -FilePath $cmdPath -WindowStyle Hidden | Out-Null
    if (Get-Command Set-CodexProfileLastUsed -ErrorAction SilentlyContinue) {
        Set-CodexProfileLastUsed -Name $key -ParallelRoot $ParallelRoot | Out-Null
    }
    if ($cdpPort -gt 0) {
        $layerScript = Join-Path $ParallelRoot 'Start-CodexLayer.ps1'
        if (-not (Test-Path -LiteralPath $layerScript)) { $layerScript = Join-Path $PSScriptRoot 'Start-CodexLayer.ps1' }
        if (Test-Path -LiteralPath $layerScript) {
            Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $layerScript,
                '-Port', "$cdpPort", '-ParallelRoot', $ParallelRoot
            ) | Out-Null
        }
    }
    if ($FastSwitch) {
        $deadline = (Get-Date).AddSeconds(4)
        $proc = $null
        while ((Get-Date) -lt $deadline) {
            $proc = Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'" -ErrorAction SilentlyContinue |
                Where-Object { $_.ExecutablePath -like '*CodexParallelDesktop*' -or $_.CommandLine -like "*profiles\$key*" } |
                Select-Object -First 1
            if ($proc) { break }
            Start-Sleep -Milliseconds 250
        }
    }
    else {
        Start-Sleep -Seconds 5
        $proc = Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.ExecutablePath -like '*CodexParallelDesktop*' -or $_.CommandLine -like "*profiles\$key*" } |
            Select-Object -First 1
    }
    if (-not $proc) { throw 'Codex profile did not start. Is Codex Desktop installed?' }

    $watcher = Join-Path $ParallelRoot 'watch-authswap-restore.ps1'
    $watchArgs = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $watcher,
        '-ProfileKey', $key,
        '-SourceHome', $SourceHome,
        '-ProfileAuth', $profileAuth,
        '-MainAuth', $mainAuth,
        '-MainAuthBak', $mainAuthBak,
        '-SwapLock', $swapLock,
        '-LogPath', $log
    )
    if ($FastSwitch) { $watchArgs += @('-InitialSleepSeconds', '0') }
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList $watchArgs | Out-Null

    Write-LaunchLog 'DONE ok authswap'
    $msg = if ($needBootstrap) { 'BOOTSTRAP login - sign in with the secondary account, then close the app' } else { "AuthSwap activeAuth=$(Hide-AuthEmail -Email (Get-AuthEmailFromFile -Path $mainAuth))" }
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
