#Requires -Version 5.1
Set-StrictMode -Version Latest

$script:ModuleVersion = '0.2.0'

function Get-CodexMultiProfileVersion {
    $candidates = @(
        (Join-Path $PSScriptRoot 'VERSION'),
        (Join-Path (Split-Path -Parent $PSScriptRoot) 'VERSION')
    )
    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path) {
            return ((Get-Content -LiteralPath $path -Raw).Trim())
        }
    }
    return $script:ModuleVersion
}

function Get-CodexParallelRoot {
    return (Join-Path $env:LOCALAPPDATA 'CodexParallelDesktop')
}

function ConvertTo-ProfileKey {
    param([Parameter(Mandatory)] [string]$ProfileName)
    $key = $ProfileName.Trim().ToLowerInvariant()
    $key = [regex]::Replace($key, '[^a-z0-9]+', '-')
    $key = $key.Trim('-')
    if (-not $key) { throw "Invalid profile name: $ProfileName" }
    return $key
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [allowemptystring()] [string]$Text
    )
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}

function ConvertFrom-JwtPayload {
    param([Parameter(Mandatory)] [string]$Jwt)
    $parts = $Jwt.Split('.')
    if ($parts.Count -lt 2) { throw 'JWT missing payload' }
    $payload = $parts[1].Replace('-', '+').Replace('_', '/')
    while ($payload.Length % 4) { $payload += '=' }
    $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload))
    return ($json | ConvertFrom-Json)
}

function Get-AuthEmailFromFile {
    <#
    .SYNOPSIS
      Read the ChatGPT email from a Codex auth.json (id_token payload).
    #>
    param([Parameter(Mandatory)] [string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 'MISSING' }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        $j = $raw | ConvertFrom-Json
        $token = [string]$j.tokens.id_token
        if ([string]::IsNullOrWhiteSpace($token)) { return 'PARSE_ERR' }
        $claims = ConvertFrom-JwtPayload -Jwt $token
        $email = [string]$claims.email
        if ([string]::IsNullOrWhiteSpace($email)) { return 'PARSE_ERR' }
        return $email
    }
    catch {
        return 'PARSE_ERR'
    }
}

function Test-NeedBootstrapLogin {
    <#
    .SYNOPSIS
      True when the profile has no auth, or its auth is the same as the main account.
    #>
    param(
        [Parameter(Mandatory)] [string]$ProfileEmail,
        [Parameter(Mandatory)] [string]$MainEmail,
        [switch]$Force
    )
    if ($Force) { return $true }
    if ($ProfileEmail -eq 'MISSING') { return $true }
    if ($ProfileEmail -eq 'PARSE_ERR') { return $true }
    if ($MainEmail -ne 'MISSING' -and $ProfileEmail -eq $MainEmail) { return $true }
    return $false
}

function Test-ShouldSaveProfileAuth {
    <#
    .SYNOPSIS
      True only when active auth is a real account different from the main backup.
      Prevents restoring the main token into profiles\<name>\auth.json.
    #>
    param(
        [Parameter(Mandatory)] [string]$ActiveEmail,
        [Parameter(Mandatory)] [string]$MainBackupEmail
    )
    if ($ActiveEmail -eq 'MISSING' -or $ActiveEmail -eq 'PARSE_ERR') { return $false }
    if ($MainBackupEmail -eq 'MISSING') { return $true }
    return ($ActiveEmail -ne $MainBackupEmail)
}

function Get-CodexCloneExe {
    param(
        [string]$ParallelRoot = (Get-CodexParallelRoot),
        [switch]$ForceRefresh
    )
    $versionsRoot = Join-Path $ParallelRoot 'versions'
    if (-not $ForceRefresh -and (Test-Path -LiteralPath $versionsRoot)) {
        $existing = Get-ChildItem -LiteralPath $versionsRoot -Directory -ErrorAction SilentlyContinue |
            ForEach-Object {
                $ver = $null
                if ([version]::TryParse($_.Name, [ref]$ver)) {
                    [pscustomobject]@{ Version = $ver; Dir = $_ }
                }
            } |
            Sort-Object Version -Descending |
            ForEach-Object { Join-Path $_.Dir.FullName 'app\ChatGPT.exe' } |
            Where-Object { Test-Path -LiteralPath $_ } |
            Select-Object -First 1
        if ($existing) { return [string]$existing }
    }

    $package = Get-AppxPackage -Name OpenAI.Codex -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending |
        Select-Object -First 1
    $install = if ($package) { [string]$package.InstallLocation } else { '' }
    if ([string]::IsNullOrWhiteSpace($install)) {
        throw 'Codex Desktop clone not found. Install Codex from the Microsoft Store, launch it once, then retry.'
    }
    $sourceApp = Join-Path $install 'app'
    $sourceExe = Join-Path $sourceApp 'ChatGPT.exe'
    if (-not (Test-Path -LiteralPath $sourceExe)) {
        throw "ChatGPT.exe missing at $sourceExe"
    }
    $version = $package.Version.ToString()
    $cloneApp = Join-Path $ParallelRoot "versions\$version\app"
    $cloneExe = Join-Path $cloneApp 'ChatGPT.exe'
    if ($ForceRefresh -and (Test-Path -LiteralPath $cloneApp)) {
        Remove-Item -LiteralPath $cloneApp -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (-not (Test-Path -LiteralPath $cloneExe)) {
        New-Item -ItemType Directory -Force -Path $cloneApp | Out-Null
        & robocopy.exe $sourceApp $cloneApp /E /NFL /NDL /NJH /NJS /NC /NS /R:1 /W:1 | Out-Null
        if ($LASTEXITCODE -gt 7) { throw "Clone failed (robocopy $LASTEXITCODE)" }
    }
    return $cloneExe
}

function New-CodexEnvCmd {
    param(
        [Parameter(Mandatory)] [string]$CmdPath,
        [Parameter(Mandatory)] [string]$CodexHome,
        [Parameter(Mandatory)] [string]$UserDataDir,
        [Parameter(Mandatory)] [string]$CloneApp,
        [Parameter(Mandatory)] [string]$CloneExe,
        [int]$RemoteDebuggingPort = 0
    )
    $extra = ''
    if ($RemoteDebuggingPort -gt 0) {
        $extra = " --" + "remote-debugging-address=127.0.0.1 --" + "remote-debugging-port=$RemoteDebuggingPort"
    }
    $cmd = @"
@echo off
set "CODEX_HOME=$CodexHome"
set "CODEX_ELECTRON_USER_DATA_PATH=$UserDataDir"
set "OPENAI_BASE_URL="
set "OPENAI_API_KEY="
set "ANTHROPIC_BASE_URL="
set "ANTHROPIC_API_KEY="
set "CODEX_THREAD_ID="
start "" /D "$CloneApp" "$CloneExe" --user-data-dir="$UserDataDir"$extra
"@
    Write-Utf8NoBom -Path $CmdPath -Text $cmd
}

function Hide-AuthEmail {
    <#
    .SYNOPSIS
      Mask an email for status output. Never print the local-part in full.
    #>
    param([Parameter(Mandatory)] [allowemptystring()] [string]$Email)
    if ([string]::IsNullOrWhiteSpace($Email)) { return 'MISSING' }
    if ($Email -in @('MISSING', 'PARSE_ERR')) { return $Email }
    $at = $Email.IndexOf('@')
    if ($at -lt 1) { return '***' }
    $user = $Email.Substring(0, $at)
    $domain = $Email.Substring($at + 1)
    $keep = [Math]::Min(2, $user.Length)
    $shown = $user.Substring(0, $keep) + '***'
    return "$shown@$domain"
}

function ConvertTo-CodexRedactedText {
    <#
    .SYNOPSIS
      Scrub local identity and paths from text safe to paste publicly.
    #>
    param(
        [Parameter(Mandatory)] [string]$Text,
        [string]$ParallelRoot,
        [string]$SourceHome
    )
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    foreach ($pair in @(
            @{ Value = $ParallelRoot; Token = '%CODEX_PARALLEL_ROOT%' }
            @{ Value = $SourceHome; Token = '%CODEX_HOME%' }
            @{ Value = $env:LOCALAPPDATA; Token = '%LOCALAPPDATA%' }
            @{ Value = $env:USERPROFILE; Token = '%USERPROFILE%' }
            @{ Value = $env:COMPUTERNAME; Token = '%COMPUTERNAME%' }
            @{ Value = $env:USERNAME; Token = '%USERNAME%' }
        )) {
        if ([string]::IsNullOrWhiteSpace($pair.Value)) { continue }
        $Text = [regex]::Replace($Text, [regex]::Escape($pair.Value), $pair.Token, 'IgnoreCase')
    }
    return $Text
}

function Get-CodexInstallStatus {
    param(
        [string]$SourceHome = (Join-Path $env:USERPROFILE '.codex'),
        [string]$ParallelRoot = (Get-CodexParallelRoot)
    )
    $lock = Join-Path $ParallelRoot '.authswap-active'
    $swap = if (Test-Path -LiteralPath $lock) { (Get-Content -LiteralPath $lock -Raw).Trim() } else { '' }
    $clone = $null
    try { $clone = Get-CodexCloneExe -ParallelRoot $ParallelRoot } catch { $clone = $null }
    $mainAuth = Join-Path $SourceHome 'auth.json'
    $mainBak = Join-Path $SourceHome 'auth.json.__main__'
    $profilesRoot = Join-Path $ParallelRoot 'profiles'
    $profiles = @()
    if (Test-Path -LiteralPath $profilesRoot) {
        $profiles = @(Get-ChildItem $profilesRoot -Directory | ForEach-Object {
                $email = Get-AuthEmailFromFile -Path (Join-Path $_.FullName 'auth.json')
                [pscustomobject]@{
                    Name    = $_.Name
                    HasAuth = [bool](Test-Path -LiteralPath (Join-Path $_.FullName 'auth.json'))
                    Account = Hide-AuthEmail -Email $email
                }
            })
    }
    [pscustomobject]@{
        Version     = Get-CodexMultiProfileVersion
        Root        = $ParallelRoot
        SharedHome  = $SourceHome
        SwapActive  = $swap
        CloneExe    = $clone
        MainAccount = Hide-AuthEmail -Email (Get-AuthEmailFromFile -Path $mainAuth)
        MainBackup  = Hide-AuthEmail -Email (Get-AuthEmailFromFile -Path $mainBak)
        Profiles    = $profiles
    }
}

function Test-FileHasUtf8Bom {
    param([Parameter(Mandatory)] [string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    return ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
}

function Get-CodexRunningProcesses {
    param([string]$ParallelRoot = (Get-CodexParallelRoot))
    $items = @(Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'" -ErrorAction SilentlyContinue)
    foreach ($p in $items) {
        $path = [string]$p.ExecutablePath
        $cmd = [string]$p.CommandLine
        $kind = 'unknown'
        if ($path -like '*WindowsApps*OpenAI.Codex*') { $kind = 'store' }
        elseif ($path -like '*CodexParallelDesktop*' -or $cmd -like '*CodexParallelDesktop*') { $kind = 'clone' }
        elseif ($cmd -like '*profiles\*') { $kind = 'clone' }
        $profile = $null
        if ($cmd -match 'profiles[\\/]([a-z0-9\-]+)') { $profile = $Matches[1] }
        [pscustomobject]@{
            Pid         = $p.ProcessId
            Kind        = $kind
            Profile     = $profile
            Executable  = $path
            CommandLine = $cmd
        }
    }
}

function Invoke-CodexDoctor {
    <#
    .SYNOPSIS
      Health checks for AuthSwap installs. Returns objects with Severity + Message.
    #>
    param(
        [string]$SourceHome = (Join-Path $env:USERPROFILE '.codex'),
        [string]$ParallelRoot = (Get-CodexParallelRoot)
    )
    $findings = New-Object System.Collections.Generic.List[object]
    function Add-Finding([string]$Severity, [string]$Code, [string]$Message) {
        $findings.Add([pscustomobject]@{ Severity = $Severity; Code = $Code; Message = $Message })
    }

    $required = @(
        'CodexMultiProfile.psm1',
        'Launch-CodexProfile.ps1',
        'Launch-CodexMain.ps1',
        'watch-authswap-restore.ps1',
        'CodexProfile.ps1'
    )
    foreach ($name in $required) {
        $path = Join-Path $ParallelRoot $name
        if (-not (Test-Path -LiteralPath $path)) {
            Add-Finding 'error' 'missing-launcher' "Missing $name under $ParallelRoot. Re-run Install-CodexMultiProfile.ps1."
        }
    }

    $clone = $null
    try { $clone = Get-CodexCloneExe -ParallelRoot $ParallelRoot } catch { $clone = $null }
    if (-not $clone) {
        Add-Finding 'error' 'missing-clone' 'ChatGPT.exe clone not found. Install Codex Desktop from the Store, launch once, then reinstall.'
    }
    else {
        Add-Finding 'info' 'clone-ok' "Clone OK: $clone"
    }

    $mainAuth = Join-Path $SourceHome 'auth.json'
    $mainEmail = Get-AuthEmailFromFile -Path $mainAuth
    if ($mainEmail -eq 'MISSING') {
        Add-Finding 'warn' 'main-auth-missing' "No main auth at $mainAuth. Sign in to Store Codex once."
    }
    elseif ($mainEmail -eq 'PARSE_ERR') {
        Add-Finding 'error' 'main-auth-parse' 'Main auth.json exists but id_token email could not be parsed.'
    }
    else {
        Add-Finding 'info' 'main-auth-ok' ("Main account: " + (Hide-AuthEmail -Email $mainEmail))
    }

    $lock = Join-Path $ParallelRoot '.authswap-active'
    $swap = if (Test-Path -LiteralPath $lock) { (Get-Content -LiteralPath $lock -Raw).Trim() } else { '' }
    $running = @(Get-CodexRunningProcesses -ParallelRoot $ParallelRoot)
    $cloneRunning = @($running | Where-Object { $_.Kind -eq 'clone' })
    $storeRunning = @($running | Where-Object { $_.Kind -eq 'store' })

    if ($swap -and $cloneRunning.Count -eq 0) {
        Add-Finding 'warn' 'stale-swap-lock' "AuthSwap lock is set to '$swap' but no clone process is running. Run: CodexProfile.ps1 -Action repair"
    }
    elseif ($swap) {
        Add-Finding 'info' 'swap-active' "AuthSwap active for profile '$swap'."
    }

    if ($storeRunning.Count -gt 0 -and $cloneRunning.Count -gt 0) {
        Add-Finding 'error' 'dual-window' 'Store Codex and a clone are both running. Close one — AuthSwap owns ~/.codex/auth.json for a single process.'
    }

    $configPath = Join-Path $SourceHome 'config.toml'
    if ((Test-Path -LiteralPath $configPath) -and (Test-FileHasUtf8Bom -Path $configPath)) {
        Add-Finding 'warn' 'config-bom' 'config.toml has a UTF-8 BOM. Codex may ignore it. Rewrite with Write-Utf8NoBom.'
    }

    $profilesRoot = Join-Path $ParallelRoot 'profiles'
    if (Test-Path -LiteralPath $profilesRoot) {
        Get-ChildItem $profilesRoot -Directory | ForEach-Object {
            $email = Get-AuthEmailFromFile -Path (Join-Path $_.FullName 'auth.json')
            if ($email -ne 'MISSING' -and $mainEmail -ne 'MISSING' -and $email -eq $mainEmail) {
                Add-Finding 'warn' 'poisoned-profile' ("Profile '$($_.Name)' auth matches main (" + (Hide-AuthEmail -Email $email) + "). Next launch will bootstrap secondary login.")
            }
        }
    }

    if ($findings.Count -eq 0) {
        Add-Finding 'info' 'healthy' 'No issues found.'
    }
    return $findings.ToArray()
}

function Get-CodexPackagedScriptNames {
    @(
        'CodexMultiProfile.psm1',
        'Launch-CodexProfile.ps1',
        'Launch-CodexMain.ps1',
        'watch-authswap-restore.ps1',
        'CodexProfile.ps1',
        'CodexProfiles-Menu.ps1',
        'Redact-LaunchTrace.ps1',
        'Export-CodexDiagnostics.ps1',
        'Update-CodexMultiProfile.ps1',
        'CodexRouter.psm1',
        'Start-CodexLayer.ps1',
        'layer-inject.js',
        'Show-CodexAccountApp.ps1'
    )
}

function Test-CodexInstallSync {
    <#
    .SYNOPSIS
      Compare packaged scripts in the repo (or $SourceDir) with the LocalAppData install.
    #>
    param(
        [Parameter(Mandatory)] [string]$SourceDir,
        [string]$ParallelRoot = (Get-CodexParallelRoot)
    )
    $rows = @()
    foreach ($name in Get-CodexPackagedScriptNames) {
        $src = Join-Path $SourceDir $name
        $dst = Join-Path $ParallelRoot $name
        $srcOk = Test-Path -LiteralPath $src
        $dstOk = Test-Path -LiteralPath $dst
        $match = $false
        if ($srcOk -and $dstOk) {
            $a = Get-FileHash -LiteralPath $src -Algorithm SHA256
            $b = Get-FileHash -LiteralPath $dst -Algorithm SHA256
            $match = ($a.Hash -eq $b.Hash)
        }
        $rows += [pscustomobject]@{
            Name    = $name
            InRepo  = $srcOk
            Installed = $dstOk
            InSync  = $match
        }
    }
    return $rows
}

function Clear-StaleAuthSwapLock {
    <#
    .SYNOPSIS
      Restore main auth from backup if present and remove .authswap-active when no clone is running.
    #>
    param(
        [string]$SourceHome = (Join-Path $env:USERPROFILE '.codex'),
        [string]$ParallelRoot = (Get-CodexParallelRoot),
        [switch]$Force
    )
    $lock = Join-Path $ParallelRoot '.authswap-active'
    $mainAuth = Join-Path $SourceHome 'auth.json'
    $mainBak = Join-Path $SourceHome 'auth.json.__main__'
    $running = @(Get-CodexRunningProcesses -ParallelRoot $ParallelRoot | Where-Object { $_.Kind -eq 'clone' })
    if ($running.Count -gt 0 -and -not $Force) {
        throw "Clone still running (pid $($running[0].Pid)). Close Codex1 first, or pass -Force."
    }
    $restored = $false
    if (Test-Path -LiteralPath $mainBak) {
        Copy-Item -LiteralPath $mainBak -Destination $mainAuth -Force
        Remove-Item -LiteralPath $mainBak -Force -ErrorAction SilentlyContinue
        $restored = $true
    }
    $hadLock = Test-Path -LiteralPath $lock
    Remove-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue
    [pscustomobject]@{
        RestoredMain = $restored
        ClearedLock  = $hadLock
        MainAccount  = Hide-AuthEmail -Email (Get-AuthEmailFromFile -Path $mainAuth)
    }
}


function Stop-CodexAuthSwapWatchers {
    <#
    .SYNOPSIS
      Kill AuthSwap restore watchers so a one-click switch cannot race restore-main.
    #>
    $killed = 0
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match 'powershell|pwsh' -and
            [string]$_.CommandLine -like '*watch-authswap-restore.ps1*'
        } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            $killed = $killed + 1
        }
    return $killed
}

Export-ModuleMember -Function @(
    'Get-CodexMultiProfileVersion',
    'Get-CodexParallelRoot',
    'ConvertTo-ProfileKey',
    'Write-Utf8NoBom',
    'Get-AuthEmailFromFile',
    'Hide-AuthEmail',
    'ConvertTo-CodexRedactedText',
    'Get-CodexInstallStatus',
    'Test-FileHasUtf8Bom',
    'Get-CodexRunningProcesses',
    'Invoke-CodexDoctor',
    'Get-CodexPackagedScriptNames',
    'Test-CodexInstallSync',
    'Clear-StaleAuthSwapLock',
    'Test-NeedBootstrapLogin',
    'Test-ShouldSaveProfileAuth',
    'Get-CodexCloneExe',
    'New-CodexEnvCmd',
    'Stop-CodexAuthSwapWatchers'
)
