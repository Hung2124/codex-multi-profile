#Requires -Version 5.1
<#
.SYNOPSIS
  Create, list, launch, and stop Codex Desktop profiles on Windows.

.EXAMPLE
  .\CodexProfile.ps1 -Action new -Name codex2
  .\CodexProfile.ps1 -Action launch -Name codex1
  .\CodexProfile.ps1 -Action list
  .\CodexProfile.ps1 -Action stop -Name codex1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('new', 'launch', 'list', 'stop', 'shortcut')]
    [string]$Action,

    [string]$Name = 'codex1',
    [string]$SourceHome = (Join-Path $env:USERPROFILE '.codex'),
    [switch]$ForceRefreshClone
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'CodexMultiProfile.psm1'
if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "Missing $modulePath. Re-run Install-CodexMultiProfile.ps1."
}
Import-Module $modulePath -Force

$ParallelRoot = Get-CodexParallelRoot

function Get-ProfileRecord([string]$ProfileName) {
    $key = ConvertTo-ProfileKey -ProfileName $ProfileName
    $root = Join-Path $ParallelRoot "profiles\$key"
    [pscustomobject]@{
        Key         = $key
        DisplayName = (Get-Culture).TextInfo.ToTitleCase($key)
        Root        = $root
        Auth        = Join-Path $root 'auth.json'
    }
}

function Show-ErrorBox([string]$Title, [string]$Message) {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show($Message, $Title, 'OK', 'Error') | Out-Null
    }
    catch {
        Write-Error $Message
    }
}

function Stop-ProfileProcesses([string]$Key) {
    Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -like "*profiles\$Key*" -or
            ($_.ExecutablePath -like '*CodexParallelDesktop*' -and $_.CommandLine -like "*$Key*")
        } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

function New-ProfileShortcut {
    param([Parameter(Mandatory)] $Record)
    $launcher = Join-Path $ParallelRoot 'Launch-CodexProfile.ps1'
    $vbsPath = Join-Path $ParallelRoot ("launch-{0}.vbs" -f $Record.Key)
    $vbs = @(
        'Set WshShell = CreateObject("WScript.Shell")'
        ('cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{0}"" -Name {1}"' -f $launcher, $Record.Key)
        'WshShell.Run cmd, 0, False'
    ) -join "`r`n"
    Write-Utf8NoBom -Path $vbsPath -Text $vbs

    $desktop = [Environment]::GetFolderPath('Desktop')
    $shortcutPath = Join-Path $desktop ("{0}.lnk" -f $Record.DisplayName)
    $iconFile = Get-ChildItem (Join-Path $ParallelRoot 'versions') -Recurse -Filter 'icon-chatgpt.ico' -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Select-Object -First 1

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = 'wscript.exe'
    $shortcut.Arguments = "`"$vbsPath`""
    $shortcut.WorkingDirectory = $ParallelRoot
    $shortcut.Description = "$($Record.DisplayName) - shared Codex data, separate ChatGPT login"
    if ($iconFile) { $shortcut.IconLocation = $iconFile.FullName }
    $shortcut.Save()
    return $shortcutPath
}

try {
    switch ($Action) {
        'list' {
            $root = Join-Path $ParallelRoot 'profiles'
            if (-not (Test-Path -LiteralPath $root)) {
                Write-Output 'No profiles yet. Create one: -Action new -Name codex1'
                break
            }
            $items = @(Get-ChildItem $root -Directory | ForEach-Object {
                    [pscustomobject]@{
                        Name    = $_.Name
                        HasAuth = Test-Path -LiteralPath (Join-Path $_.FullName 'auth.json')
                    }
                })
            if ($items.Count -eq 0) {
                Write-Output 'No profiles yet. Create one: -Action new -Name codex1'
            }
            else {
                $items | Format-Table -AutoSize | Out-String | Write-Output
            }
        }
        'new' {
            $record = Get-ProfileRecord -ProfileName $Name
            New-Item -ItemType Directory -Force -Path $record.Root, (Join-Path $record.Root '.codex') | Out-Null
            $null = Get-CodexCloneExe -ParallelRoot $ParallelRoot -ForceRefresh:$ForceRefreshClone
            $shortcut = New-ProfileShortcut -Record $record
            Write-Output "Created profile: $($record.Key)"
            Write-Output "Auth file (after first login): $($record.Auth)"
            Write-Output "Shared data: $SourceHome"
            Write-Output "Shortcut: $shortcut"
        }
        'shortcut' {
            $record = Get-ProfileRecord -ProfileName $Name
            New-Item -ItemType Directory -Force -Path $record.Root | Out-Null
            $null = Get-CodexCloneExe -ParallelRoot $ParallelRoot
            $shortcut = New-ProfileShortcut -Record $record
            Write-Output "Shortcut: $shortcut"
        }
        'stop' {
            $record = Get-ProfileRecord -ProfileName $Name
            Stop-ProfileProcesses -Key $record.Key
            Write-Output "Stopped $($record.Key)"
        }
        'launch' {
            $record = Get-ProfileRecord -ProfileName $Name
            $reliable = Join-Path $ParallelRoot 'Launch-CodexProfile.ps1'
            if (-not (Test-Path -LiteralPath $reliable)) { throw "Missing $reliable" }
            try {
                & $reliable -Name $record.Key -SourceHome $SourceHome
            }
            catch {
                Show-ErrorBox -Title $record.DisplayName -Message $_.Exception.Message
                throw
            }
        }
    }
}
catch {
    if ($Action -ne 'launch') { Write-Error $_ }
    exit 1
}
