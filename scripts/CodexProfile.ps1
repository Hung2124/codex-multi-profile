#Requires -Version 5.1
<#
.SYNOPSIS
  Quan ly nhieu Codex desktop profile (codex1, codex2, ...) tren Windows.

.NOTES
  ShareLive (mac dinh): history/project/MCP/skills/memories dung chung voi ~/.codex.
  Chi auth.json la rieng tung profile. Mo/dong profile se sync 2 chieu.
  Khuyen nghi chi mo 1 Codex (goc HOAC profile) tai mot thoi diem.

.EXAMPLE
  .\CodexProfile.ps1 -Action new -Name codex2
  .\CodexProfile.ps1 -Action launch -Name codex1
  .\CodexProfile.ps1 -Action stop -Name codex1
  .\CodexProfile.ps1 -Action share -Name codex1
  .\CodexProfile.ps1 -Action list
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('new', 'launch', 'sync', 'share', 'shortcut', 'list', 'stop')]
    [string]$Action,

    [string]$Name = 'codex1',

    [string]$SourceHome = (Join-Path $env:USERPROFILE '.codex'),

    [switch]$SyncConfig,
    [switch]$SyncHistory,
    [switch]$CreateShortcut,
    [switch]$ForceRefreshClone,

    # ShareLive bat mac dinh. -NoShareLive de tat.
    [switch]$ShareLive,
    [switch]$NoShareLive
)

$ErrorActionPreference = 'Stop'
$ParallelRoot = Join-Path $env:LOCALAPPDATA 'CodexParallelDesktop'
$SharedDirs = @('sessions', 'skills', 'memories', 'plugins', 'vendor_imports', 'sqlite')
$SharedDbFiles = @('state_5.sqlite', 'memories_1.sqlite', 'goals_1.sqlite', 'session_index.jsonl')

function ConvertTo-ProfileKey([string]$ProfileName) {
    $key = $ProfileName.Trim().ToLowerInvariant()
    $key = [regex]::Replace($key, '[^a-z0-9]+', '-')
    $key = $key.Trim('-')
    if (-not $key) { throw "Ten profile khong hop le: $ProfileName" }
    return $key
}

function Get-ProfilePaths([string]$ProfileName) {
    $key = ConvertTo-ProfileKey $ProfileName
    $root = Join-Path $ParallelRoot "profiles\$key"
    [pscustomobject]@{
        Key          = $key
        DisplayName  = (Get-Culture).TextInfo.ToTitleCase($key)
        Root         = $root
        CodexHome    = Join-Path $root '.codex'
        ElectronData = $root
        ShareMarker  = Join-Path $root '.share-live'
    }
}

function Test-ShareLiveEnabled($Paths) {
    if ($NoShareLive) { return $false }
    if ($ShareLive) { return $true }
    return (Test-Path $Paths.ShareMarker)
}

function Enable-ShareLiveMarker($Paths) {
    Set-Content -Path $Paths.ShareMarker -Value "share-live=1`nsource=$SourceHome`n" -Encoding ASCII
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

function Ensure-CodexClone([switch]$ForceRefresh) {
    $versionsRoot = Join-Path $ParallelRoot 'versions'
    if (-not $ForceRefresh -and (Test-Path -LiteralPath $versionsRoot)) {
        $existingExe = Get-ChildItem -LiteralPath $versionsRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName 'app\ChatGPT.exe' } |
            Where-Object { Test-Path -LiteralPath $_ } |
            Select-Object -First 1
        if ($existingExe) {
            $cloneApp = Split-Path -Parent $existingExe
            return [pscustomobject]@{
                Version   = Split-Path -Leaf (Split-Path -Parent $cloneApp)
                CloneApp  = $cloneApp
                CloneExe  = $existingExe
                SourceApp = $null
            }
        }
    }

    $package = Get-AppxPackage -Name OpenAI.Codex -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending | Select-Object -First 1
    $install = if ($package) { [string]$package.InstallLocation } else { '' }
    if ([string]::IsNullOrWhiteSpace($install)) {
        throw 'Khong tim thay clone local / Store InstallLocation. Hay cai Codex Desktop.'
    }
    $sourceApp = Join-Path $install 'app'
    $sourceExe = Join-Path $sourceApp 'ChatGPT.exe'
    if (-not (Test-Path -LiteralPath $sourceExe)) { throw "Khong tim thay ChatGPT.exe: $sourceExe" }
    $version = $package.Version.ToString()
    $cloneApp = Join-Path $ParallelRoot "versions\$version\app"
    $cloneExe = Join-Path $cloneApp 'ChatGPT.exe'
    if ($ForceRefresh -and (Test-Path -LiteralPath $cloneApp)) {
        Remove-Item -LiteralPath $cloneApp -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (-not (Test-Path -LiteralPath $cloneExe)) {
        New-Item -ItemType Directory -Force -Path $cloneApp | Out-Null
        & robocopy.exe $sourceApp $cloneApp /E /NFL /NDL /NJH /NJS /NC /NS /R:1 /W:1 | Out-Null
        if ($LASTEXITCODE -gt 7) { throw "Clone that bai ($LASTEXITCODE)" }
    }
    return [pscustomobject]@{ Version=$version; CloneApp=$cloneApp; CloneExe=$cloneExe; SourceApp=$sourceApp }
}

function Write-DefaultConfig([string]$CodexHomePath) {
    # Do not stamp config.toml. Codex Desktop creates its own on first run.
    # PowerShell 5.1 Set-Content -Encoding UTF8 writes a BOM that can make
    # Codex ignore the file and fall back to the main home.
    New-Item -ItemType Directory -Force -Path $CodexHomePath | Out-Null
}

function Get-ItemLinkType([string]$Path) {
    if (-not (Test-Path $Path)) { return $null }
    $item = Get-Item $Path -Force
    return $item.LinkType
}

function Set-Junction([string]$LinkPath, [string]$TargetPath) {
    if (-not (Test-Path $TargetPath)) {
        New-Item -ItemType Directory -Force -Path $TargetPath | Out-Null
    }

    if (Test-Path $LinkPath) {
        $linkType = Get-ItemLinkType $LinkPath
        $currentTarget = $null
        try { $currentTarget = (Get-Item $LinkPath -Force).Target } catch { }

        $targetFull = (Resolve-Path $TargetPath).Path
        if ($linkType -eq 'Junction' -and $currentTarget -and ($currentTarget -contains $targetFull -or "$currentTarget" -eq $targetFull)) {
            return
        }

        if ($linkType -eq 'Junction') {
            cmd /c "rmdir `"$LinkPath`"" | Out-Null
        }
        else {
            # Merge real folder into target then replace with junction
            & robocopy.exe $LinkPath $TargetPath /E /NFL /NDL /NJH /NJS /NC /NS /R:1 /W:1 | Out-Null
            Remove-Item $LinkPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    New-Item -ItemType Junction -Path $LinkPath -Target $TargetPath | Out-Null
}

function Enable-SharedDirLinks {
    param(
        [Parameter(Mandatory)] $Paths,
        [string]$SourceHome
    )

    New-Item -ItemType Directory -Force -Path $Paths.CodexHome | Out-Null
    foreach ($dirName in $SharedDirs) {
        $fromDir = Join-Path $SourceHome $dirName
        $toDir = Join-Path $Paths.CodexHome $dirName
        Set-Junction -LinkPath $toDir -TargetPath $fromDir
    }
}

function Rewrite-ConfigHome([string]$ConfigText, [string]$CodexHomePath) {
    $cfg = $ConfigText
    $cfg = $cfg -replace "CODEX_HOME = '[^']+'", "CODEX_HOME = '$CodexHomePath'"
    $cfg = $cfg -replace "NODE_REPL_TRUSTED_CODE_PATHS = '[^']+'", "NODE_REPL_TRUSTED_CODE_PATHS = '$CodexHomePath'"
    return $cfg
}

function Sync-DbAndMeta {
    param(
        [Parameter(Mandatory)] [ValidateSet('In', 'Out')] [string]$Direction,
        [Parameter(Mandatory)] $Paths,
        [string]$SourceHome
    )

    $src = $SourceHome
    $dst = $Paths.CodexHome
    if ($Direction -eq 'Out') {
        $src = $Paths.CodexHome
        $dst = $SourceHome
    }

    New-Item -ItemType Directory -Force -Path $dst | Out-Null

    # Remove WAL/SHM on destination before replacing DB
    foreach ($name in @(
            'state_5.sqlite-wal', 'state_5.sqlite-shm',
            'memories_1.sqlite-wal', 'memories_1.sqlite-shm',
            'goals_1.sqlite-wal', 'goals_1.sqlite-shm'
        )) {
        Remove-Item (Join-Path $dst $name) -Force -ErrorAction SilentlyContinue
    }

    foreach ($name in $SharedDbFiles) {
        $from = Join-Path $src $name
        if (Test-Path $from) {
            Copy-Item $from (Join-Path $dst $name) -Force
        }
    }

    # AGENTS.md
    $agentsFrom = Join-Path $src 'AGENTS.md'
    if (Test-Path $agentsFrom) {
        Copy-Item $agentsFrom (Join-Path $dst 'AGENTS.md') -Force
    }

    # config.toml with rewritten CODEX_HOME for destination
    $cfgFrom = Join-Path $src 'config.toml'
    if (Test-Path $cfgFrom) {
        $cfg = Get-Content $cfgFrom -Raw -Encoding UTF8
        $cfg = Rewrite-ConfigHome -ConfigText $cfg -CodexHomePath $dst
        [System.IO.File]::WriteAllText((Join-Path $dst 'config.toml'), $cfg, [System.Text.UTF8Encoding]::new($false))
    }

    # global state: merge project/thread fields
    $srcStatePath = Join-Path $src '.codex-global-state.json'
    $dstStatePath = Join-Path $dst '.codex-global-state.json'
    if (Test-Path $srcStatePath) {
        $srcState = Get-Content $srcStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (Test-Path $dstStatePath) {
            $dstState = Get-Content $dstStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        else {
            $dstState = [pscustomobject]@{}
        }

        foreach ($k in @('electron-saved-workspace-roots', 'project-order', 'active-workspace-roots', 'pinned-thread-ids')) {
            if ($null -ne $srcState.$k) {
                $dstState | Add-Member -NotePropertyName $k -NotePropertyValue $srcState.$k -Force
            }
        }

        $srcAtom = $srcState.'electron-persisted-atom-state'
        $dstAtom = $dstState.'electron-persisted-atom-state'
        if (-not $dstAtom) { $dstAtom = [pscustomobject]@{} }
        if ($srcAtom) {
            $keys = @(
                'thread-descriptions-v1', 'pinned-thread-ids', 'projectless-thread-ids',
                'thread-workspace-root-hints', 'thread-projectless-output-directories',
                'unread-thread-ids-by-host-v1', 'heartbeat-thread-permissions-by-id',
                'prompt-history', 'flat-project-sidebar-preferences-v1',
                'composer-prompt-drafts-v1', 'skip-full-access-confirm',
                'composer-auto-context-enabled', 'composer-model-picker-menu-view-v1'
            )
            foreach ($k in $keys) {
                if ($null -ne $srcAtom.$k) {
                    $dstAtom | Add-Member -NotePropertyName $k -NotePropertyValue $srcAtom.$k -Force
                }
            }
            $srcAtom.PSObject.Properties | Where-Object { $_.Name -like 'thread-client-id-v1:*' } | ForEach-Object {
                $dstAtom | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value -Force
            }
        }
        $dstState | Add-Member -NotePropertyName 'electron-persisted-atom-state' -NotePropertyValue $dstAtom -Force
        $json = $dstState | ConvertTo-Json -Depth 50 -Compress
        [System.IO.File]::WriteAllText($dstStatePath, $json, [System.Text.UTF8Encoding]::new($false))
    }

    # NEVER touch auth.json in either direction
}

function Sync-CodexProfile {
    param(
        [Parameter(Mandatory)] $Paths,
        [string]$SourceHome,
        [switch]$Config,
        [switch]$History,
        [ValidateSet('In', 'Out')] [string]$Direction = 'In'
    )

    if (-not (Test-Path $SourceHome)) {
        throw "Source home khong ton tai: $SourceHome"
    }

    New-Item -ItemType Directory -Force -Path $Paths.CodexHome | Out-Null

    if (Test-ShareLiveEnabled $Paths) {
        Enable-SharedDirLinks -Paths $Paths -SourceHome $SourceHome
        Sync-DbAndMeta -Direction $Direction -Paths $Paths -SourceHome $SourceHome
        return
    }

    # Legacy copy mode (NoShareLive)
    if ($Direction -eq 'Out') {
        # Still support push-back without junctions
        Sync-DbAndMeta -Direction Out -Paths $Paths -SourceHome $SourceHome
        foreach ($dirName in $SharedDirs) {
            $fromDir = Join-Path $Paths.CodexHome $dirName
            $toDir = Join-Path $SourceHome $dirName
            if (Test-Path $fromDir) {
                New-Item -ItemType Directory -Force -Path $toDir | Out-Null
                & robocopy.exe $fromDir $toDir /E /NFL /NDL /NJH /NJS /NC /NS /R:1 /W:1 | Out-Null
            }
        }
        return
    }

    if ($Config -or $History) {
        Sync-DbAndMeta -Direction In -Paths $Paths -SourceHome $SourceHome
    }
    if ($Config) {
        foreach ($dirName in @('skills', 'memories', 'plugins', 'vendor_imports')) {
            $fromDir = Join-Path $SourceHome $dirName
            if (Test-Path $fromDir) {
                $toDir = Join-Path $Paths.CodexHome $dirName
                New-Item -ItemType Directory -Force -Path $toDir | Out-Null
                & robocopy.exe $fromDir $toDir /E /NFL /NDL /NJH /NJS /NC /NS /R:1 /W:1 | Out-Null
            }
        }
    }
    if ($History) {
        foreach ($dirName in @('sessions', 'sqlite')) {
            $fromDir = Join-Path $SourceHome $dirName
            if (Test-Path $fromDir) {
                $toDir = Join-Path $Paths.CodexHome $dirName
                New-Item -ItemType Directory -Force -Path $toDir | Out-Null
                & robocopy.exe $fromDir $toDir /E /NFL /NDL /NJH /NJS /NC /NS /R:1 /W:1 | Out-Null
            }
        }
    }
}

function Stop-MainCodex {
    Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.ExecutablePath -like '*WindowsApps*OpenAI.Codex*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

function Stop-Profile([string]$Key) {
    Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -like "*profiles\$Key*" -or
            $_.CommandLine -like "*profiles/$Key*" -or
            ($_.ExecutablePath -like '*CodexParallelDesktop*' -and $_.CommandLine -like "*$Key*")
        } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

    # Also stop clone helpers
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ExecutablePath -like '*CodexParallelDesktop*' -and
            $_.CommandLine -like "*profiles\$Key*"
        } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

function Start-ShareSyncWatcher {
    param(
        [Parameter(Mandatory)] $Paths,
        [string]$SourceHome
    )

    $watcher = Join-Path $ParallelRoot 'watch-sync-back.ps1'
    $watcherCode = @'
param([string]$ProfileKey, [string]$SourceHome, [string]$Manager)
Start-Sleep -Seconds 8
while ($true) {
  $running = @(Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*profiles\$ProfileKey*" -or $_.CommandLine -like "*profiles/$ProfileKey*" })
  if ($running.Count -eq 0) { break }
  Start-Sleep -Seconds 4
}
# Push profile changes back to main ~/.codex
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Manager -Action stop -Name $ProfileKey 2>$null
'@
    [System.IO.File]::WriteAllText($watcher, $watcherCode, [System.Text.UTF8Encoding]::new($false))

    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $watcher,
        '-ProfileKey', $Paths.Key,
        '-SourceHome', $SourceHome,
        '-Manager', (Join-Path $ParallelRoot 'CodexProfile.ps1')
    ) | Out-Null
}

function New-ProfileShortcut {
    param([Parameter(Mandatory)] $Paths)

    $launcherPs1 = Join-Path $ParallelRoot 'Launch-CodexProfile.ps1'
    $vbsPath = Join-Path $ParallelRoot ("launch-{0}.vbs" -f $Paths.Key)
    $vbs = @"
Set WshShell = CreateObject("WScript.Shell")
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$launcherPs1"" -Name ""$($Paths.Key)"""
WshShell.Run cmd, 0, False
"@
    Set-Content -Path $vbsPath -Value $vbs -Encoding ASCII

    $desktop = [Environment]::GetFolderPath('Desktop')
    $shortcutPath = Join-Path $desktop ("{0}.lnk" -f $Paths.DisplayName)
    $iconFile = Get-ChildItem (Join-Path $ParallelRoot 'versions') -Recurse -Filter 'icon-chatgpt.ico' -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = 'wscript.exe'
    $shortcut.Arguments = "`"$vbsPath`""
    $shortcut.WorkingDirectory = $ParallelRoot
    $shortcut.Description = "$($Paths.DisplayName) — shared data, separate ChatGPT auth (ShareLive)"
    if ($iconFile) { $shortcut.IconLocation = $iconFile.FullName }
    $shortcut.Save()
    return $shortcutPath
}

function Start-Profile([Parameter(Mandatory)] $Paths, [switch]$ForceRefreshClone) {
    New-Item -ItemType Directory -Force -Path $Paths.Root, $Paths.CodexHome, $Paths.ElectronData | Out-Null
    Write-DefaultConfig -CodexHomePath $Paths.CodexHome
    $clone = Ensure-CodexClone -ForceRefresh:$ForceRefreshClone

    $varsToRemove = @(
        'OPENAI_BASE_URL', 'OPENAI_API_KEY', 'OPENAI_ORG_ID', 'OPENAI_PROJECT_ID',
        'ANTHROPIC_BASE_URL', 'ANTHROPIC_API_KEY', 'ANTHROPIC_AUTH_TOKEN', 'CODEX_THREAD_ID'
    )
    $saved = @{}
    foreach ($n in ($varsToRemove + @('CODEX_HOME', 'CODEX_ELECTRON_USER_DATA_PATH'))) {
        $saved[$n] = [Environment]::GetEnvironmentVariable($n, 'Process')
    }

    try {
        foreach ($n in $varsToRemove) { Remove-Item -Path "Env:$n" -ErrorAction SilentlyContinue }
        $env:CODEX_HOME = $Paths.CodexHome
        $env:CODEX_ELECTRON_USER_DATA_PATH = $Paths.ElectronData

        $proc = Start-Process -FilePath $clone.CloneExe `
            -WorkingDirectory $clone.CloneApp `
            -ArgumentList @("--user-data-dir=$($Paths.Root)") `
            -PassThru

        Start-Sleep -Seconds 4
        if ($proc.HasExited) {
            throw "$($Paths.DisplayName) thoat ngay (exit $($proc.ExitCode)). Kiem tra clone ChatGPT.exe + env ShareLive."
        }
        return $proc
    }
    finally {
        foreach ($entry in $saved.GetEnumerator()) {
            if ($null -eq $entry.Value) {
                Remove-Item -Path "Env:$($entry.Key)" -ErrorAction SilentlyContinue
            }
            else {
                Set-Item -Path "Env:$($entry.Key)" -Value $entry.Value
            }
        }
    }
}

function Get-ProfileList {
    $root = Join-Path $ParallelRoot 'profiles'
    if (-not (Test-Path $root)) { return @() }
    Get-ChildItem $root -Directory | ForEach-Object {
        $codexHome = Join-Path $_.FullName '.codex'
        $share = Test-Path (Join-Path $_.FullName '.share-live')
        [pscustomobject]@{
            Name      = $_.Name
            ShareLive = $share
            HasAuth   = Test-Path (Join-Path $codexHome 'auth.json')
            HasConfig = Test-Path (Join-Path $codexHome 'config.toml')
            Sessions  = if (Test-Path (Join-Path $codexHome 'sessions')) {
                (Get-ChildItem (Join-Path $codexHome 'sessions') -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
            } else { 0 }
        }
    }
}

# --- main ---
try {
    switch ($Action) {
        'list' {
            $items = @(Get-ProfileList)
            if (-not $items -or $items.Count -eq 0) {
                Write-Output 'Chua co profile nao. Tao bang: -Action new -Name codex2'
            }
            else {
                $items | Format-Table -AutoSize | Out-String | Write-Output
            }
        }
        'share' {
            $paths = Get-ProfilePaths -ProfileName $Name
            New-Item -ItemType Directory -Force -Path $paths.Root, $paths.CodexHome, $paths.ElectronData | Out-Null
            Stop-Profile -Key $paths.Key
            Stop-MainCodex
            Start-Sleep -Seconds 2
            Enable-ShareLiveMarker -Paths $paths
            Enable-SharedDirLinks -Paths $paths -SourceHome $SourceHome
            Sync-DbAndMeta -Direction In -Paths $paths -SourceHome $SourceHome
            $null = New-ProfileShortcut -Paths $paths
            Write-Output "ShareLive ON for $($paths.Key)"
            Write-Output "Dirs junctioned to $SourceHome : $($SharedDirs -join ', ')"
            Write-Output "DB/meta sync on launch/stop. auth.json stays separate."
        }
        'new' {
            $paths = Get-ProfilePaths -ProfileName $Name
            New-Item -ItemType Directory -Force -Path $paths.Root, $paths.CodexHome, $paths.ElectronData | Out-Null
            Write-DefaultConfig -CodexHomePath $paths.CodexHome
            $null = Ensure-CodexClone -ForceRefresh:$ForceRefreshClone

            if (-not $NoShareLive) { Enable-ShareLiveMarker -Paths $paths }
            $SyncConfig = $true
            $SyncHistory = $true
            Sync-CodexProfile -Paths $paths -SourceHome $SourceHome -Config:$SyncConfig -History:$SyncHistory -Direction In

            $shortcut = New-ProfileShortcut -Paths $paths
            Write-Output "Created profile: $($paths.Key)"
            Write-Output "ShareLive: $(Test-ShareLiveEnabled $paths)"
            Write-Output "Home: $($paths.CodexHome)"
            Write-Output "Shortcut: $shortcut"
        }
        'sync' {
            $paths = Get-ProfilePaths -ProfileName $Name
            if (-not (Test-Path $paths.CodexHome)) {
                throw "Profile chua ton tai: $($paths.Key). Hay chay -Action new truoc."
            }
            # Manual sync = always PULL from main ~/.codex
            Stop-Profile -Key $paths.Key
            Stop-MainCodex
            Start-Sleep -Seconds 2
            if (-not $NoShareLive) { Enable-ShareLiveMarker -Paths $paths }
            Sync-CodexProfile -Paths $paths -SourceHome $SourceHome -Config:$true -History:$true -Direction In
            Write-Output "Pulled $($paths.Key) <- $SourceHome (auth.json NOT touched)"
        }
        'shortcut' {
            $paths = Get-ProfilePaths -ProfileName $Name
            New-Item -ItemType Directory -Force -Path $paths.Root, $paths.CodexHome, $paths.ElectronData | Out-Null
            $null = Ensure-CodexClone
            $shortcut = New-ProfileShortcut -Paths $paths
            Write-Output "Shortcut: $shortcut"
        }
        'stop' {
            $paths = Get-ProfilePaths -ProfileName $Name
            Stop-Profile -Key $paths.Key
            Start-Sleep -Seconds 2
            if (Test-ShareLiveEnabled $paths) {
                Sync-CodexProfile -Paths $paths -SourceHome $SourceHome -Config:$true -History:$true -Direction Out
                Write-Output "Stopped $($paths.Key) + synced changes back to $SourceHome"
            }
            else {
                Write-Output "Stopped $($paths.Key)"
            }
        }
        'launch' {
            $paths = Get-ProfilePaths -ProfileName $Name
            try {
                $reliable = Join-Path $ParallelRoot 'Launch-CodexProfile.ps1'
                if (-not (Test-Path -LiteralPath $reliable)) { throw "Missing $reliable" }
                & $reliable -Name $paths.Key -SourceHome $SourceHome
            }
            catch {
                Show-ErrorBox -Title $paths.DisplayName -Message $_.Exception.Message
                throw
            }
        }
    }
}
catch {
    if ($Action -ne 'launch') { Write-Error $_ }
    exit 1
}


