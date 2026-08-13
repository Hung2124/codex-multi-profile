#Requires -Version 5.1
Set-StrictMode -Version Latest

$script:ModuleVersion = '0.1.2'

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
            Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName 'app\ChatGPT.exe' } |
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
        [Parameter(Mandatory)] [string]$CloneExe
    )
    $cmd = @"
@echo off
set "CODEX_HOME=$CodexHome"
set "CODEX_ELECTRON_USER_DATA_PATH=$UserDataDir"
set "OPENAI_BASE_URL="
set "OPENAI_API_KEY="
set "ANTHROPIC_BASE_URL="
set "ANTHROPIC_API_KEY="
set "CODEX_THREAD_ID="
start "" /D "$CloneApp" "$CloneExe" --user-data-dir="$UserDataDir"
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

Export-ModuleMember -Function @(
    'Get-CodexMultiProfileVersion',
    'Get-CodexParallelRoot',
    'ConvertTo-ProfileKey',
    'Write-Utf8NoBom',
    'Get-AuthEmailFromFile',
    'Hide-AuthEmail',
    'Get-CodexInstallStatus',
    'Test-NeedBootstrapLogin',
    'Test-ShouldSaveProfileAuth',
    'Get-CodexCloneExe',
    'New-CodexEnvCmd'
)
