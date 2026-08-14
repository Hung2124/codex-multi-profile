#Requires -Version 5.1
<#
.SYNOPSIS
  Create, list, launch, and stop Codex Desktop profiles on Windows.

.EXAMPLE
  .\CodexProfile.ps1 -Action new -Name codex2
  .\CodexProfile.ps1 -Action launch -Name codex1
  .\CodexProfile.ps1 -Action list
  .\CodexProfile.ps1 -Action status
  .\CodexProfile.ps1 -Action status -AsJson
  .\CodexProfile.ps1 -Action doctor
  .\CodexProfile.ps1 -Action processes
  .\CodexProfile.ps1 -Action repair
  .\CodexProfile.ps1 -Action sync-check
  .\CodexProfile.ps1 -Action verify
  .\CodexProfile.ps1 -Action remove -Name codex2 -Force
  .\CodexProfile.ps1 -Action stop -Name codex1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('new', 'launch', 'list', 'stop', 'shortcut', 'status', 'verify', 'remove', 'doctor', 'processes', 'repair', 'sync-check')]
    [string]$Action,

    [string]$Name = 'codex1',
    [string]$SourceHome = (Join-Path $env:USERPROFILE '.codex'),
    [switch]$ForceRefreshClone,
    [switch]$AsJson,
    [switch]$Force
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

function Get-RequiredLauncherFiles {
    @(
        'CodexMultiProfile.psm1',
        'Launch-CodexProfile.ps1',
        'Launch-CodexMain.ps1',
        'watch-authswap-restore.ps1',
        'CodexProfile.ps1'
    )
}

function Write-InstallStatus {
    Get-CodexInstallStatus -SourceHome $SourceHome -ParallelRoot $ParallelRoot
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
                    $email = Get-AuthEmailFromFile -Path (Join-Path $_.FullName 'auth.json')
                    [pscustomobject]@{
                        Name    = $_.Name
                        HasAuth = Test-Path -LiteralPath (Join-Path $_.FullName 'auth.json')
                        Account = Hide-AuthEmail -Email $email
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
        'status' {
            $info = Write-InstallStatus
            if ($AsJson) {
                $info | ConvertTo-Json -Depth 6
                break
            }
            Write-Output "Version: $($info.Version)"
            Write-Output "Root: $($info.Root)"
            Write-Output "Shared home: $($info.SharedHome)"
            Write-Output "AuthSwap active: $(if ($info.SwapActive) { $info.SwapActive } else { '(none)' })"
            Write-Output "Clone: $(if ($info.CloneExe) { $info.CloneExe } else { '(missing — install Codex Desktop)' })"
            Write-Output "Main account: $($info.MainAccount)"
            Write-Output "Main backup: $($info.MainBackup)"
            if ($info.Profiles.Count -eq 0) {
                Write-Output 'Profiles: (none)'
            }
            else {
                Write-Output 'Profiles:'
                $info.Profiles | Format-Table -AutoSize | Out-String | Write-Output
            }
        }
        'verify' {
            $missing = @()
            foreach ($name in Get-RequiredLauncherFiles) {
                $here = Join-Path $PSScriptRoot $name
                $installed = Join-Path $ParallelRoot $name
                if (-not (Test-Path -LiteralPath $here) -and -not (Test-Path -LiteralPath $installed)) {
                    $missing += $name
                }
            }
            if ($missing.Count -gt 0) {
                throw "Missing launcher files: $($missing -join ', ')"
            }
            $null = Get-CodexMultiProfileVersion
            $cloneOk = $true
            try { $null = Get-CodexCloneExe -ParallelRoot $ParallelRoot } catch { $cloneOk = $false }
            Write-Output "OK module $(Get-CodexMultiProfileVersion)"
            Write-Output "OK launcher files"
            if ($cloneOk) { Write-Output 'OK ChatGPT.exe clone' }
            else { Write-Warning 'ChatGPT.exe clone not found. Install Codex Desktop from the Store, then re-run install.' }
            Write-Output 'verify passed'
        }
        'remove' {
            if (-not $Force) {
                throw "Refusing to delete profile '$Name' without -Force. ~/.codex is never deleted."
            }
            $record = Get-ProfileRecord -ProfileName $Name
            Stop-ProfileProcesses -Key $record.Key
            Start-Sleep -Seconds 1
            if (Test-Path -LiteralPath $record.Root) {
                Remove-Item -LiteralPath $record.Root -Recurse -Force
            }
            $desktop = [Environment]::GetFolderPath('Desktop')
            $lnk = Join-Path $desktop ("{0}.lnk" -f $record.DisplayName)
            Remove-Item -LiteralPath $lnk -Force -ErrorAction SilentlyContinue
            Write-Output "Removed profile $($record.Key)"
        }
        'doctor' {
            $findings = @(Invoke-CodexDoctor -SourceHome $SourceHome -ParallelRoot $ParallelRoot)
            if ($AsJson) {
                $findings | ConvertTo-Json -Depth 6
                break
            }
            $errors = @($findings | Where-Object { $_.Severity -eq 'error' }).Count
            $warns = @($findings | Where-Object { $_.Severity -eq 'warn' }).Count
            foreach ($f in $findings) {
                Write-Output ("[{0}] {1}: {2}" -f $f.Severity.ToUpperInvariant(), $f.Code, $f.Message)
            }
            Write-Output ("doctor summary: {0} error(s), {1} warning(s)" -f $errors, $warns)
            if ($errors -gt 0) { exit 2 }
        }
        'processes' {
            $procs = @(Get-CodexRunningProcesses -ParallelRoot $ParallelRoot)
            if ($AsJson) {
                $procs | ConvertTo-Json -Depth 5
                break
            }
            if ($procs.Count -eq 0) {
                Write-Output 'No ChatGPT.exe processes found.'
            }
            else {
                $procs | Select-Object Pid, Kind, Profile, Executable | Format-Table -AutoSize | Out-String | Write-Output
            }
        }
        'repair' {
            $result = Clear-StaleAuthSwapLock -SourceHome $SourceHome -ParallelRoot $ParallelRoot -Force:$Force
            if ($AsJson) {
                $result | ConvertTo-Json -Depth 4
                break
            }
            Write-Output ("Restored main auth: {0}" -f $result.RestoredMain)
            Write-Output ("Cleared AuthSwap lock: {0}" -f $result.ClearedLock)
            Write-Output ("Main account now: {0}" -f $result.MainAccount)
        }
        'sync-check' {
            $rows = @(Test-CodexInstallSync -SourceDir $PSScriptRoot -ParallelRoot $ParallelRoot)
            if ($AsJson) {
                $rows | ConvertTo-Json -Depth 4
                break
            }
            $rows | Format-Table -AutoSize | Out-String | Write-Output
            $stale = @($rows | Where-Object { -not $_.InSync })
            if ($stale.Count -gt 0) {
                Write-Warning ("{0} file(s) out of sync. Re-run Install-CodexMultiProfile.ps1 or Update-CodexMultiProfile.ps1." -f $stale.Count)
                exit 3
            }
            Write-Output 'sync-check: all packaged scripts match the install.'
        }
    }
}
catch {
    if ($Action -ne 'launch') { Write-Error $_ }
    exit 1
}
