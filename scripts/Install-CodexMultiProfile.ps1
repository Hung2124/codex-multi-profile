#Requires -Version 5.1
<#
.SYNOPSIS
  Install Codex Multi-Profile launchers, Desktop shortcuts, and the agent skill.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-CodexMultiProfile.ps1
#>
[CmdletBinding()]
param(
    [string]$Name = 'codex1',
    [switch]$SkipClone,
    [switch]$SkipShortcuts,
    [switch]$SkipSkill
)

$ErrorActionPreference = 'Stop'

function ConvertTo-ProfileKey([string]$ProfileName) {
    $key = $ProfileName.Trim().ToLowerInvariant()
    $key = [regex]::Replace($key, '[^a-z0-9]+', '-')
    $key = $key.Trim('-')
    if (-not $key) { throw "Invalid profile name: $ProfileName" }
    return $key
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}

function New-Lnk {
    param(
        [Parameter(Mandatory)] [string]$ShortcutPath,
        [Parameter(Mandatory)] [string]$VbsPath,
        [Parameter(Mandatory)] [string]$WorkingDirectory,
        [Parameter(Mandatory)] [string]$Description,
        [string]$IconPath
    )
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = 'wscript.exe'
    $shortcut.Arguments = "`"$VbsPath`""
    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.Description = $Description
    if ($IconPath -and (Test-Path -LiteralPath $IconPath)) {
        $shortcut.IconLocation = $IconPath
    }
    $shortcut.Save()
}

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ParallelRoot = Join-Path $env:LOCALAPPDATA 'CodexParallelDesktop'
$key = ConvertTo-ProfileKey $Name
$desktop = [Environment]::GetFolderPath('Desktop')

New-Item -ItemType Directory -Force -Path $ParallelRoot, (Join-Path $ParallelRoot "profiles\$key") | Out-Null

$files = @(
    'CodexMultiProfile.psm1',
    'Launch-CodexProfile.ps1',
    'Launch-CodexMain.ps1',
    'watch-authswap-restore.ps1',
    'CodexProfile.ps1',
    'CodexProfiles-Menu.ps1'
)
foreach ($name in $files) {
    $from = Join-Path $PSScriptRoot $name
    if (-not (Test-Path -LiteralPath $from)) { throw "Missing $from" }
    Copy-Item -LiteralPath $from -Destination (Join-Path $ParallelRoot $name) -Force
    Unblock-File -LiteralPath (Join-Path $ParallelRoot $name) -ErrorAction SilentlyContinue
}

$versionSrc = Join-Path $RepoRoot 'VERSION'
if (Test-Path -LiteralPath $versionSrc) {
    Copy-Item -LiteralPath $versionSrc -Destination (Join-Path $ParallelRoot 'VERSION') -Force
}

if (-not $SkipClone) {
    $manager = Join-Path $ParallelRoot 'CodexProfile.ps1'
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $manager -Action new -Name $key
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            Write-Warning "Profile create/clone returned exit $LASTEXITCODE. Install Codex Desktop from the Microsoft Store, then re-run."
        }
    }
    catch {
        Write-Warning $_.Exception.Message
        Write-Warning 'Install Codex Desktop from the Microsoft Store, then re-run this installer.'
    }
}

$launchProfile = Join-Path $ParallelRoot 'Launch-CodexProfile.ps1'
$launchMain = Join-Path $ParallelRoot 'Launch-CodexMain.ps1'
$menu = Join-Path $ParallelRoot 'CodexProfiles-Menu.ps1'

function New-VbsLauncher([string]$CmdLine, [int]$WindowStyle) {
    @(
        'Set WshShell = CreateObject("WScript.Shell")'
        ('cmd = "{0}"' -f $CmdLine)
        ('WshShell.Run cmd, {0}, False' -f $WindowStyle)
    ) -join "`r`n"
}

$vbsProfile = Join-Path $ParallelRoot ("launch-{0}.vbs" -f $key)
$cmdProfile = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{0}"" -Name {1}' -f $launchProfile, $key
Write-Utf8NoBom $vbsProfile (New-VbsLauncher -CmdLine $cmdProfile -WindowStyle 0)

$vbsMain = Join-Path $ParallelRoot 'launch-codex-main.vbs'
$cmdMain = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{0}""' -f $launchMain
Write-Utf8NoBom $vbsMain (New-VbsLauncher -CmdLine $cmdMain -WindowStyle 0)

$vbsMenu = Join-Path $ParallelRoot 'CodexProfiles-Menu.vbs'
$cmdMenu = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""{0}""' -f $menu
Write-Utf8NoBom $vbsMenu (New-VbsLauncher -CmdLine $cmdMenu -WindowStyle 1)

if (-not $SkipShortcuts) {
    $icon = Get-ChildItem (Join-Path $ParallelRoot 'versions') -Recurse -Filter 'icon-chatgpt.ico' -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
    $iconPath = if ($icon) { $icon.FullName } else { $null }

    $display = (Get-Culture).TextInfo.ToTitleCase($key)
    New-Lnk -ShortcutPath (Join-Path $desktop "$display.lnk") -VbsPath $vbsProfile -WorkingDirectory $ParallelRoot `
        -Description "$display - shared Codex data, separate ChatGPT login (AuthSwap)" -IconPath $iconPath
    New-Lnk -ShortcutPath (Join-Path $desktop 'Codex Main.lnk') -VbsPath $vbsMain -WorkingDirectory $ParallelRoot `
        -Description 'Restore main ChatGPT account and open Store Codex' -IconPath $iconPath
    New-Lnk -ShortcutPath (Join-Path $desktop 'Codex Profiles.lnk') -VbsPath $vbsMenu -WorkingDirectory $ParallelRoot `
        -Description 'Pick or create a Codex profile' -IconPath $iconPath
}

if (-not $SkipSkill) {
    $skillSrc = Join-Path $RepoRoot 'SKILL.md'
    $scriptSrc = $PSScriptRoot
    $skillTargets = @(
        (Join-Path $env:USERPROFILE '.codex\skills\codex-multi-profile'),
        (Join-Path $env:USERPROFILE '.cursor\skills\codex-multi-profile')
    )
    foreach ($target in $skillTargets) {
        New-Item -ItemType Directory -Force -Path (Join-Path $target 'scripts') | Out-Null
        if (Test-Path -LiteralPath $skillSrc) {
            Copy-Item -LiteralPath $skillSrc -Destination (Join-Path $target 'SKILL.md') -Force
        }
        foreach ($name in $files) {
            Copy-Item -LiteralPath (Join-Path $scriptSrc $name) -Destination (Join-Path $target "scripts\$name") -Force
        }
    }
}

Write-Output "Installed to $ParallelRoot"
if (Test-Path -LiteralPath (Join-Path $ParallelRoot 'VERSION')) {
    Write-Output ("Version: " + (Get-Content -LiteralPath (Join-Path $ParallelRoot 'VERSION') -Raw).Trim())
}
Write-Output "Profile: $key"
Write-Output "Open '$key' for the secondary account, or 'Codex Main' for the Store app."
Write-Output "Do not run both at the same time."
Write-Output "Check with: CodexProfile.ps1 -Action verify"
