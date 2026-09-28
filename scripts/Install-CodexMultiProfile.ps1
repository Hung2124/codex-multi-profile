#Requires -Version 5.1
<#
.SYNOPSIS
  Install Codex Multi-Profile: the account list inside the Microsoft Store Codex avatar menu.

.DESCRIPTION
  Copies the scripts to %LOCALAPPDATA%\CodexMultiProfile, saves the login Codex is using
  now as the first account, and creates a "Codex" shortcut (Desktop + Start menu) that opens
  Codex with the account menu. Pin that shortcut instead of the original Codex icon.

  -RemoveLegacy also imports the logins saved by the old clone-based versions (0.1-0.3,
  %LOCALAPPDATA%\CodexParallelDesktop) and then deletes that folder, its cloned ChatGPT.exe
  copies and the old Codex1 / Codex Main / Codex Accounts / Codex Profiles shortcuts.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-CodexMultiProfile.ps1 -RemoveLegacy
#>
[CmdletBinding()]
param(
    [switch]$RemoveLegacy,
    [switch]$SkipShortcuts,
    [string]$Root = (Join-Path $env:LOCALAPPDATA 'CodexMultiProfile'),
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' })
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'CodexAccounts.psm1') -Force

$files = @('CodexAccounts.psm1', 'Start-CodexAccounts.ps1', 'switcher-inject.js', 'CodexAccounts.ps1', 'Uninstall-CodexMultiProfile.ps1')
$legacyRoot = Join-Path $env:LOCALAPPDATA 'CodexParallelDesktop'
$desktop = [Environment]::GetFolderPath('Desktop')
$startMenu = Join-Path ([Environment]::GetFolderPath('Programs')) 'Codex (accounts).lnk'

function Import-LegacyLogins {
    # Old versions kept a login per profile, plus the main login in auth.json.__main__ during a swap.
    $candidates = @()
    $mainBak = Join-Path $CodexHome 'auth.json.__main__'
    if (Test-Path -LiteralPath $mainBak) { $candidates += [pscustomobject]@{ Name = 'main'; Path = $mainBak } }
    $profilesDir = Join-Path $legacyRoot 'profiles'
    if (Test-Path -LiteralPath $profilesDir) {
        foreach ($d in (Get-ChildItem -LiteralPath $profilesDir -Directory)) {
            foreach ($rel in @('auth.json', 'auth.json.secondary.bak', '.codex\auth.json')) {
                $p = Join-Path $d.FullName $rel
                if (Get-AuthIdentity -Path $p) { $candidates += [pscustomobject]@{ Name = $d.Name; Path = $p }; break }
            }
        }
    }
    foreach ($c in $candidates) {
        $id = Get-AuthIdentity -Path $c.Path
        if (-not $id) { continue }
        $existing = Find-CodexAccountByIdentity -Identity $id -Root $Root
        if ($existing) { Write-Output ("Old login {0} ({1}) is already saved as {2}." -f $c.Name, (Hide-AuthEmail -Email $id.Email), $existing.Name); continue }
        $key = ConvertTo-AccountKey -Name $c.Name
        if (Test-Path -LiteralPath (Join-Path $Root "accounts\$key")) { $key = Get-CodexNextAccountName -Root $Root }
        Copy-FileAtomic -Source $c.Path -Destination (Join-Path $Root "accounts\$key\auth.json")
        Set-CodexAccountMeta -Name $key -Root $Root
        Write-Output ("Imported old login {0} as {1} ({2})." -f $c.Name, $key, (Hide-AuthEmail -Email $id.Email))
    }
    if (Test-Path -LiteralPath $mainBak) {
        # A swap was left half done: ~/.codex/auth.json may hold the secondary login. Both are saved now.
        Remove-Item -LiteralPath $mainBak -Force
    }
}

function New-Shortcut([string]$Path, [string]$Icon) {
    $launch = Get-CodexLauncherCommand -Root $Root
    # Start from an empty file: CreateShortcut() on an existing .lnk keeps its old extra data blocks.
    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut($Path)
    $lnk.TargetPath = $launch.FilePath
    $lnk.Arguments = $launch.Arguments
    $lnk.WindowStyle = 7
    $lnk.WorkingDirectory = $Root
    $lnk.Description = 'Codex with the account list in the avatar menu'
    if ($Icon -and (Test-Path -LiteralPath $Icon)) { $lnk.IconLocation = $Icon }
    $lnk.Save()
}

$pkg = Get-CodexStorePackage
New-Item -ItemType Directory -Force -Path $Root | Out-Null
foreach ($name in $files) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $Root $name) -Force
    Unblock-File -LiteralPath (Join-Path $Root $name) -ErrorAction SilentlyContinue
}
Copy-Item -LiteralPath (Join-Path $RepoRoot 'VERSION') -Destination (Join-Path $Root 'VERSION') -Force

# Accounts: the login in use first, then anything the old versions saved.
$live = Get-AuthIdentity -Path (Join-Path $CodexHome 'auth.json')
if ($live -and -not (Find-CodexAccountByIdentity -Identity $live -Root $Root)) {
    $saved = Save-CodexAccount -Root $Root -CodexHome $CodexHome
    Write-Output ("Saved the current Codex login as {0} ({1})." -f $saved, (Hide-AuthEmail -Email $live.Email))
}
if (Test-Path -LiteralPath $legacyRoot) { Import-LegacyLogins }

# Icon copied so the shortcut survives Store updates that move the package folder.
$icon = Join-Path $Root 'codex.ico'
try {
    Add-Type -AssemblyName System.Drawing
    $ico = [System.Drawing.Icon]::ExtractAssociatedIcon((Join-Path $pkg.InstallLocation 'app\ChatGPT.exe'))
    $fs = [IO.File]::Create($icon)
    try { $ico.Save($fs) } finally { $fs.Dispose() }
}
catch { $icon = $null }

if (-not $SkipShortcuts) {
    New-Shortcut -Path (Join-Path $desktop 'Codex.lnk') -Icon $icon
    New-Shortcut -Path $startMenu -Icon $icon
}

if ($RemoveLegacy) {
    $legacyRunning = @(Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'" -ErrorAction SilentlyContinue | Where-Object { [string]$_.ExecutablePath -like '*CodexParallelDesktop*' })
    if ($legacyRunning.Count) { throw 'A cloned Codex from the old version is running. Close it, then run this again.' }
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { [string]$_.CommandLine -match 'CodexParallelDesktop\\(watch-authswap-restore|Start-CodexSwitcherHost|Start-CodexLayer)' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $legacyRoot) {
        Remove-CodexTreeNoFollow -Path $legacyRoot
        Write-Output "Removed the old clone-based install ($legacyRoot)."
    }
    foreach ($n in @('Codex1.lnk', 'Codex Main.lnk', 'Codex Accounts.lnk', 'Codex Profiles.lnk')) {
        $lnk = Join-Path $desktop $n
        if (Test-Path -LiteralPath $lnk) {
            $target = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk).Arguments
            if ($target -like '*CodexParallelDesktop*') { Remove-Item -LiteralPath $lnk -Force; Write-Output "Removed old shortcut $n." }
        }
    }
    foreach ($dir in @((Join-Path $env:USERPROFILE '.cursor\skills\codex-multi-profile\scripts'), (Join-Path $CodexHome 'skills\codex-multi-profile\scripts'))) {
        if (Test-Path -LiteralPath $dir) { Remove-CodexTreeNoFollow -Path $dir }
    }
}

# Agent skill: the CLI lives in the install folder, the skill only describes it.
foreach ($dir in @((Join-Path $CodexHome 'skills\codex-multi-profile'), (Join-Path $env:USERPROFILE '.cursor\skills\codex-multi-profile'))) {
    if (Test-Path -LiteralPath (Split-Path -Parent $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Copy-Item -LiteralPath (Join-Path $RepoRoot 'SKILL.md') -Destination (Join-Path $dir 'SKILL.md') -Force
    }
}

Write-Output ("Installed {0} to {1}" -f (Get-CodexMultiProfileVersion), $Root)
Write-Output ("Accounts: {0}" -f ((@(Get-CodexAccounts -Root $Root) | ForEach-Object { $_.Name }) -join ', '))
Write-Output 'Open Codex from the new "Codex" shortcut (pin it to the taskbar instead of the original icon),'
Write-Output 'then click your avatar at the bottom-left: your accounts are listed under your name.'
