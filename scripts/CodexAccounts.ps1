#Requires -Version 5.1
<#
.SYNOPSIS
  Command line for the saved Codex accounts (same store as the avatar menu).

.EXAMPLE
  CodexAccounts.ps1 list
  CodexAccounts.ps1 save -Name work        # save the login Codex uses now
  CodexAccounts.ps1 switch -Name work      # close Codex, switch, reopen with the account menu
  CodexAccounts.ps1 rename -Name work -NewName cong-viec
  CodexAccounts.ps1 remove -Name old
  CodexAccounts.ps1 lang -Name vi          # menu language: auto | vi | en
  CodexAccounts.ps1 status
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)] [ValidateSet('list', 'save', 'switch', 'rename', 'remove', 'lang', 'status')] [string]$Action = 'list',
    [string]$Name,
    [string]$NewName,
    [switch]$Json,
    [string]$Root = (Join-Path $env:LOCALAPPDATA 'CodexMultiProfile'),
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' })
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'CodexAccounts.psm1') -Force

function Get-Rows {
    $active = Get-CodexActiveAccount -Root $Root -CodexHome $CodexHome
    return @(Get-CodexAccounts -Root $Root | ForEach-Object {
            [pscustomobject]@{
                Name     = $_.Name
                Account  = (Hide-AuthEmail -Email $_.Email)
                Plan     = $_.Plan
                Active   = [bool]($active -and $active.Name -eq $_.Name)
                Depleted = $_.Depleted
                LastUsed = $_.LastUsed
            }
        })
}

switch ($Action) {
    'list' {
        $rows = Get-Rows
        if ($Json) { ConvertTo-Json -InputObject @($rows) -Depth 3 }
        elseif ($rows.Count -eq 0) { 'No saved accounts. Open Codex from the Codex shortcut, or run: CodexAccounts.ps1 save -Name <name>' }
        else { $rows | Format-Table -AutoSize | Out-String -Width 200 }
    }
    'save' {
        $saved = Save-CodexAccount -Name $Name -Root $Root -CodexHome $CodexHome
        "Saved the current login as $saved."
    }
    'switch' {
        if (-not $Name) { throw 'Use -Name <account>.' }
        $key = ConvertTo-AccountKey -Name $Name
        if (-not (Get-AuthIdentity -Path (Join-Path $Root "accounts\$key\auth.json"))) { throw "Unknown account '$key'." }
        # Same fast path as the menu: only the app-server restarts, the Codex window stays.
        if (Restart-CodexAppServer -Swap { Set-CodexLiveAuth -Name $key -Root $Root -CodexHome $CodexHome }) {
            Write-CodexLog -Message "[cli] switched to $key (fast)" -Root $Root
            "Switched to $key."
            break
        }
        Stop-CodexStore
        if (@(Get-CodexStoreProcesses).Count) { throw 'Codex did not close; nothing was changed.' }
        Set-CodexLiveAuth -Name $key -Root $Root -CodexHome $CodexHome
        Write-CodexLog -Message "[cli] switched to $key" -Root $Root
        $launch = Get-CodexLauncherCommand -Root $Root
        Start-Process -FilePath $launch.FilePath -ArgumentList $launch.Arguments -WindowStyle Hidden
        "Switched to $key. Codex is reopening."
    }
    'rename' {
        if (-not $Name -or -not $NewName) { throw 'Use -Name <account> -NewName <new name>.' }
        $new = Rename-CodexAccount -Name (ConvertTo-AccountKey -Name $Name) -NewName $NewName -Root $Root
        "Renamed to $new."
    }
    'remove' {
        if (-not $Name) { throw 'Use -Name <account>.' }
        Remove-CodexAccount -Name (ConvertTo-AccountKey -Name $Name) -Root $Root -CodexHome $CodexHome
        "Removed $Name."
    }
    'lang' {
        if ($Name -notin @('auto', 'vi', 'en')) { throw 'Use -Name auto, vi or en.' }
        $settings = Get-CodexAccountsSettings -Root $Root
        Write-Utf8NoBom -Path (Join-Path $Root 'settings.json') -Text ((([ordered]@{ cdpPort = $settings.CdpPort; lang = $Name }) | ConvertTo-Json) + "`n")
        "Menu language: $Name (applies the next time the menu opens)."
    }
    'status' {
        $settings = Get-CodexAccountsSettings -Root $Root
        $live = Get-AuthIdentity -Path (Join-Path $CodexHome 'auth.json')
        $active = Get-CodexActiveAccount -Root $Root -CodexHome $CodexHome
        $procs = @(Get-CodexStoreProcesses)
        $hostUp = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { [string]$_.CommandLine -like '*Start-CodexAccounts.ps1*' }).Count -gt 0
        "Version:        $(Get-CodexMultiProfileVersion)"
        "Codex (Store):  $(try { (Get-CodexStorePackage).Version } catch { 'NOT INSTALLED' })"
        "Signed in as:   $(if ($live) { Hide-AuthEmail -Email $live.Email } else { '(signed out)' })"
        "Active account: $(if ($active) { $active.Name } else { '(not saved)' })"
        "Codex running:  $(if ($procs.Count) { 'yes' + $(if (Test-CodexStoreHasCdp -Port $settings.CdpPort) { ', with the account menu' } else { ', WITHOUT the account menu (opened from the original icon)' }) } else { 'no' })"
        "Menu helper:    $(if ($hostUp) { 'running' } else { 'not running' }) (127.0.0.1:$($settings.CdpPort), language $($settings.Lang))"
        "Accounts:       $(@(Get-CodexAccounts -Root $Root).Count)"
    }
}
