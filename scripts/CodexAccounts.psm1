#Requires -Version 5.1
<#
  Codex Multi-Profile core: several ChatGPT logins for the Microsoft Store Codex app.

  One account = one saved copy of ~/.codex/auth.json under
  %LOCALAPPDATA%\CodexMultiProfile\accounts\<name>\auth.json.
  Switching = sync the live auth.json back into the account in use, copy the chosen
  account's auth.json in place, restart the Store Codex. Chats, projects, skills and
  settings in ~/.codex are shared by every account.
#>
Set-StrictMode -Version Latest

$script:ModuleVersion = '0.4.0'

function Get-CodexMultiProfileVersion {
    foreach ($path in @((Join-Path $PSScriptRoot 'VERSION'), (Join-Path (Split-Path -Parent $PSScriptRoot) 'VERSION'))) {
        if (Test-Path -LiteralPath $path) { return ((Get-Content -LiteralPath $path -Raw).Trim()) }
    }
    return $script:ModuleVersion
}

function Get-CodexAccountsRoot {
    return (Join-Path $env:LOCALAPPDATA 'CodexMultiProfile')
}

function Get-CodexHome {
    if ($env:CODEX_HOME) { return $env:CODEX_HOME }
    return (Join-Path $env:USERPROFILE '.codex')
}

function Write-CodexLog {
    param([Parameter(Mandatory)] [string]$Message, [string]$Root = (Get-CodexAccountsRoot))
    $log = Join-Path $Root 'codex-accounts.log'
    try {
        if ((Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).Length -gt 512KB) {
            Move-Item -LiteralPath $log -Destination "$log.1" -Force
        }
        Add-Content -LiteralPath $log -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Message)
    }
    catch { }
}

function Write-Utf8NoBom {
    param([Parameter(Mandatory)] [string]$Path, [Parameter(Mandatory)] [AllowEmptyString()] [string]$Text)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

function Copy-FileAtomic {
    # Write next to the target, then rename over it: Codex never sees a half-written auth.json.
    param([Parameter(Mandatory)] [string]$Source, [Parameter(Mandatory)] [string]$Destination)
    $dir = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $tmp = "$Destination.tmp-$PID"
    Copy-Item -LiteralPath $Source -Destination $tmp -Force
    Move-Item -LiteralPath $tmp -Destination $Destination -Force
}

function Remove-CodexTreeNoFollow {
    <#
    .SYNOPSIS
      Delete a folder without ever following a junction or symlink inside it (the old
      clone profiles linked memories / skills / plugins to ~/.codex). Long paths are fine.
    #>
    param([Parameter(Mandatory)] [string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith('\\?\')) { $full = '\\?\' + $full }
    if (-not [IO.Directory]::Exists($full)) { return }
    foreach ($dir in [IO.Directory]::GetDirectories($full)) {
        if (([IO.File]::GetAttributes($dir) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { [IO.Directory]::Delete($dir, $false) }
        else { Remove-CodexTreeNoFollow -Path $dir }
    }
    foreach ($file in [IO.Directory]::GetFiles($full)) {
        [IO.File]::SetAttributes($file, [IO.FileAttributes]::Normal)
        [IO.File]::Delete($file)
    }
    [IO.Directory]::Delete($full, $false)
}

function ConvertTo-AccountKey {
    <#
    .SYNOPSIS
      Folder-safe account name: lower-case a-z 0-9 and dashes, accents dropped ("Cong viec" -> cong-viec).
    #>
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Name)
    $s = $Name.Normalize([Text.NormalizationForm]::FormD)
    $s = [regex]::Replace($s, '\p{Mn}', '')
    $s = $s.Replace([string][char]0x0111, 'd').Replace([string][char]0x0110, 'D')
    $s = [regex]::Replace($s.ToLowerInvariant(), '[^a-z0-9]+', '-').Trim('-')
    if ($s.Length -gt 64) { $s = $s.Substring(0, 64).Trim('-') }
    if (-not $s) { throw "Invalid account name: '$Name'" }
    return $s
}

function ConvertFrom-JwtPayload {
    param([Parameter(Mandatory)] [string]$Jwt)
    $parts = $Jwt.Split('.')
    if ($parts.Count -lt 2) { throw 'JWT missing payload' }
    $payload = $parts[1].Replace('-', '+').Replace('_', '/')
    while ($payload.Length % 4) { $payload += '=' }
    return ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json)
}

function Get-AuthIdentity {
    <#
    .SYNOPSIS
      Who a Codex auth.json belongs to: email, ChatGPT account id, plan. $null if unreadable.
    #>
    param([Parameter(Mandatory)] [string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $j = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $j.PSObject.Properties['tokens'] -or -not $j.tokens) { return $null }
        $claims = ConvertFrom-JwtPayload -Jwt ([string]$j.tokens.id_token)
        $email = [string]$claims.email
        if ([string]::IsNullOrWhiteSpace($email)) { return $null }
        $accountId = ''
        $plan = ''
        $auth = $claims.PSObject.Properties['https://api.openai.com/auth']
        if ($auth -and $auth.Value) {
            if ($auth.Value.PSObject.Properties['chatgpt_account_id']) { $accountId = [string]$auth.Value.chatgpt_account_id }
            if ($auth.Value.PSObject.Properties['chatgpt_plan_type']) { $plan = [string]$auth.Value.chatgpt_plan_type }
        }
        if (-not $accountId -and $j.tokens.PSObject.Properties['account_id']) { $accountId = [string]$j.tokens.account_id }
        return [pscustomobject]@{ Email = $email; AccountId = $accountId; Plan = $plan }
    }
    catch { return $null }
}

function Test-SameIdentity($A, $B) {
    if (-not $A -or -not $B) { return $false }
    if ($A.Email -ne $B.Email) { return $false }
    # Same email in two ChatGPT workspaces = two accounts.
    if ($A.AccountId -and $B.AccountId) { return ($A.AccountId -eq $B.AccountId) }
    return $true
}

function Hide-AuthEmail {
    <#
    .SYNOPSIS
      ab***@domain.com. The local part is never shown in full.
    #>
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Email)
    $at = $Email.IndexOf('@')
    if ($at -lt 1) { return '' }
    return ($Email.Substring(0, [Math]::Min(2, $at)) + '***' + $Email.Substring($at))
}

function Test-CodexTextHasFullEmail {
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Text)
    foreach ($m in [regex]::Matches($Text, '[A-Za-z0-9._%+\-*]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}')) {
        if ($m.Value -notmatch '^[^@]{0,2}\*\*\*@') { return $true }
    }
    return $false
}

# ---------------------------------------------------------------- account store

function Get-CodexAccountsMeta {
    param([string]$Root = (Get-CodexAccountsRoot))
    $meta = @{}
    $path = Join-Path $Root 'accounts.json'
    if (Test-Path -LiteralPath $path) {
        try {
            $obj = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $obj.PSObject.Properties) {
                $meta[$p.Name] = @{
                    depleted = [bool]($p.Value.PSObject.Properties['depleted'] -and $p.Value.depleted)
                    lastUsed = $(if ($p.Value.PSObject.Properties['lastUsed']) { [string]$p.Value.lastUsed } else { '' })
                }
            }
        }
        catch { }
    }
    return $meta
}

function Save-CodexAccountsMeta {
    param([Parameter(Mandatory)] [hashtable]$Meta, [string]$Root = (Get-CodexAccountsRoot))
    $ordered = [ordered]@{}
    foreach ($k in ($Meta.Keys | Sort-Object)) { $ordered[$k] = $Meta[$k] }
    Write-Utf8NoBom -Path (Join-Path $Root 'accounts.json') -Text (($ordered | ConvertTo-Json -Depth 4) + "`n")
}

function Set-CodexAccountMeta {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [string]$Root = (Get-CodexAccountsRoot),
        [object]$Depleted = $null,
        [switch]$Used
    )
    $meta = Get-CodexAccountsMeta -Root $Root
    if (-not $meta.ContainsKey($Name)) { $meta[$Name] = @{ depleted = $false; lastUsed = '' } }
    if ($null -ne $Depleted) { $meta[$Name].depleted = [bool]$Depleted }
    if ($Used) { $meta[$Name].lastUsed = (Get-Date).ToUniversalTime().ToString('o'); $meta[$Name].depleted = $false }
    Save-CodexAccountsMeta -Meta $meta -Root $Root
}

function Get-CodexAccounts {
    <#
    .SYNOPSIS
      Saved accounts, oldest first: Name, Email, AccountId, Plan, Depleted, LastUsed, AuthPath.
    #>
    param([string]$Root = (Get-CodexAccountsRoot))
    $dir = Join-Path $Root 'accounts'
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    $meta = Get-CodexAccountsMeta -Root $Root
    $rows = foreach ($d in (Get-ChildItem -LiteralPath $dir -Directory | Sort-Object CreationTimeUtc, Name)) {
        if ($d.Name -notmatch '^[a-z0-9][a-z0-9\-]{0,63}$') { continue }
        $authPath = Join-Path $d.FullName 'auth.json'
        $id = Get-AuthIdentity -Path $authPath
        $m = $meta[$d.Name]
        [pscustomobject]@{
            Name      = $d.Name
            Email     = $(if ($id) { $id.Email } else { '' })
            AccountId = $(if ($id) { $id.AccountId } else { '' })
            Plan      = $(if ($id) { $id.Plan } else { '' })
            Depleted  = [bool]($m -and $m.depleted)
            LastUsed  = $(if ($m) { $m.lastUsed } else { '' })
            AuthPath  = $authPath
        }
    }
    return @($rows)
}

function Find-CodexAccountByIdentity {
    param($Identity, [string]$Root = (Get-CodexAccountsRoot))
    if (-not $Identity) { return $null }
    foreach ($a in (Get-CodexAccounts -Root $Root)) {
        if (Test-SameIdentity $Identity ([pscustomobject]@{ Email = $a.Email; AccountId = $a.AccountId })) { return $a }
    }
    return $null
}

function Get-CodexActiveAccount {
    <#
    .SYNOPSIS
      The saved account whose login is in ~/.codex/auth.json right now, or $null.
    #>
    param([string]$Root = (Get-CodexAccountsRoot), [string]$CodexHome = (Get-CodexHome))
    return (Find-CodexAccountByIdentity -Identity (Get-AuthIdentity -Path (Join-Path $CodexHome 'auth.json')) -Root $Root)
}

function Sync-CodexActiveAccount {
    <#
    .SYNOPSIS
      Copy the live auth.json into the account it belongs to when it changed.
      Codex refreshes (and rotates) tokens in place; a stale saved copy stops working.
    #>
    param([string]$Root = (Get-CodexAccountsRoot), [string]$CodexHome = (Get-CodexHome))
    $live = Join-Path $CodexHome 'auth.json'
    $active = Get-CodexActiveAccount -Root $Root -CodexHome $CodexHome
    if (-not $active) { return $null }
    $same = (Test-Path -LiteralPath $active.AuthPath) -and
        ((Get-FileHash -LiteralPath $live -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $active.AuthPath -Algorithm SHA256).Hash)
    if (-not $same) { Copy-FileAtomic -Source $live -Destination $active.AuthPath }
    return $active.Name
}

function Get-CodexNextAccountName {
    param([string]$Root = (Get-CodexAccountsRoot))
    $names = @(Get-CodexAccounts -Root $Root | ForEach-Object { $_.Name })
    if ($names -notcontains 'main') { return 'main' }
    $i = 2
    while ($names -contains "account-$i") { $i++ }
    return "account-$i"
}

function Save-CodexAccount {
    <#
    .SYNOPSIS
      Save the login in ~/.codex/auth.json as a named account.
    #>
    param(
        [string]$Name,
        [string]$Root = (Get-CodexAccountsRoot),
        [string]$CodexHome = (Get-CodexHome)
    )
    $live = Join-Path $CodexHome 'auth.json'
    $id = Get-AuthIdentity -Path $live
    if (-not $id) { throw 'Codex is not signed in (no readable ~/.codex/auth.json).' }
    $existing = Find-CodexAccountByIdentity -Identity $id -Root $Root
    if ($existing) { throw "This login is already saved as '$($existing.Name)'." }
    if (-not $Name) { $Name = Get-CodexNextAccountName -Root $Root }
    $key = ConvertTo-AccountKey -Name $Name
    $target = Join-Path $Root "accounts\$key"
    if (Test-Path -LiteralPath $target) { throw "An account named '$key' already exists." }
    Copy-FileAtomic -Source $live -Destination (Join-Path $target 'auth.json')
    Set-CodexAccountMeta -Name $key -Root $Root -Used
    return $key
}

function Remove-CodexAccount {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [string]$Root = (Get-CodexAccountsRoot),
        [string]$CodexHome = (Get-CodexHome)
    )
    $active = Get-CodexActiveAccount -Root $Root -CodexHome $CodexHome
    if ($active -and $active.Name -eq $Name) { throw "'$Name' is the account in use. Switch to another one first." }
    $dir = Join-Path $Root "accounts\$Name"
    if (-not (Test-Path -LiteralPath $dir)) { throw "Unknown account '$Name'." }
    Remove-Item -LiteralPath $dir -Recurse -Force
    $meta = Get-CodexAccountsMeta -Root $Root
    if ($meta.ContainsKey($Name)) { $meta.Remove($Name); Save-CodexAccountsMeta -Meta $meta -Root $Root }
}

function Rename-CodexAccount {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$NewName,
        [string]$Root = (Get-CodexAccountsRoot)
    )
    $key = ConvertTo-AccountKey -Name $NewName
    $dir = Join-Path $Root "accounts\$Name"
    if (-not (Test-Path -LiteralPath $dir)) { throw "Unknown account '$Name'." }
    if ($key -eq $Name) { return $key }
    if (Test-Path -LiteralPath (Join-Path $Root "accounts\$key")) { throw "An account named '$key' already exists." }
    Rename-Item -LiteralPath $dir -NewName $key
    $meta = Get-CodexAccountsMeta -Root $Root
    if ($meta.ContainsKey($Name)) { $meta[$key] = $meta[$Name]; $meta.Remove($Name); Save-CodexAccountsMeta -Meta $meta -Root $Root }
    return $key
}

function Set-CodexLiveAuth {
    <#
    .SYNOPSIS
      Put account <Name> into ~/.codex/auth.json (Codex must be closed).
      The outgoing login is synced into its own account first.
    #>
    param(
        [Parameter(Mandatory)] [string]$Name,
        [string]$Root = (Get-CodexAccountsRoot),
        [string]$CodexHome = (Get-CodexHome)
    )
    $src = Join-Path $Root "accounts\$Name\auth.json"
    if (-not (Get-AuthIdentity -Path $src)) { throw "Account '$Name' has no usable saved login." }
    $null = Sync-CodexActiveAccount -Root $Root -CodexHome $CodexHome
    Copy-FileAtomic -Source $src -Destination (Join-Path $CodexHome 'auth.json')
    Set-CodexAccountMeta -Name $Name -Root $Root -Used
}

function Clear-CodexLiveAuth {
    <#
    .SYNOPSIS
      Sign-in screen for a new account (Codex must be closed). Refuses to drop a login
      that is not saved anywhere.
    #>
    param([string]$Root = (Get-CodexAccountsRoot), [string]$CodexHome = (Get-CodexHome))
    $live = Join-Path $CodexHome 'auth.json'
    if (-not (Test-Path -LiteralPath $live)) { return }
    if (Get-AuthIdentity -Path $live) {
        if (-not (Sync-CodexActiveAccount -Root $Root -CodexHome $CodexHome)) { throw 'The current login is not saved; save it before adding another.' }
    }
    Remove-Item -LiteralPath $live -Force
}

# ---------------------------------------------------------------- Store Codex process

function Get-CodexStorePackage {
    $pkg = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $pkg) { throw 'Codex from the Microsoft Store is not installed.' }
    return $pkg
}

function Get-CodexStoreProcesses {
    <#
    .SYNOPSIS
      Browser (main) processes of the Store Codex: ChatGPT.exe under WindowsApps\OpenAI.Codex_*, no --type=.
    #>
    return @(Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'" -ErrorAction SilentlyContinue | Where-Object {
            ([string]$_.ExecutablePath -like '*\WindowsApps\OpenAI.Codex_*') -and ([string]$_.CommandLine -notmatch '--type=')
        })
}

function Test-CodexStoreHasCdp {
    param([Parameter(Mandatory)] [int]$Port)
    return (@(Get-CodexStoreProcesses | Where-Object { [string]$_.CommandLine -match ("--remote-debugging-port={0}(\s|`"|$)" -f $Port) }).Count -gt 0)
}

function Stop-CodexStore {
    <#
    .SYNOPSIS
      Close the Store Codex: ask the window to close, then end the process tree.
    #>
    param([double]$GraceSeconds = 0.5)
    $ids = @(Get-CodexStoreProcesses | ForEach-Object { [int]$_.ProcessId })
    if ($ids.Count -eq 0) { return }
    # Get-Process polling (no WMI) keeps this fast; Codex usually only hides on close, hence the short grace.
    $alive = { @(Get-Process -Id $ids -ErrorAction SilentlyContinue) }
    foreach ($gp in (& $alive)) { try { [void]$gp.CloseMainWindow() } catch { } }
    $deadline = (Get-Date).AddSeconds($GraceSeconds)
    while ((Get-Date) -lt $deadline -and @(& $alive).Count -gt 0) { Start-Sleep -Milliseconds 150 }
    foreach ($gp in (& $alive)) { & taskkill.exe /PID $gp.Id /T /F 2>&1 | Out-Null }
    # Wait for every ChatGPT.exe of the package (renderers, GPU, ...), not just the main one: a new
    # instance started while the old one is still exiting hangs on "The application is exiting".
    $any = { @(Get-Process -Name 'ChatGPT' -ErrorAction SilentlyContinue | Where-Object { [string]$_.Path -like '*\WindowsApps\OpenAI.Codex_*' -or -not $_.Path }) }
    $deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $deadline -and @(& $any).Count -gt 0) { Start-Sleep -Milliseconds 150 }
    foreach ($gp in (& $any)) { & taskkill.exe /PID $gp.Id /F 2>&1 | Out-Null }
}

function Start-CodexStore {
    <#
    .SYNOPSIS
      Start the Store Codex through Windows app activation (it refuses to run without package
      identity), with the DevTools protocol on 127.0.0.1:<Port> for the account menu. Returns the pid.
      Invoke-CommandInDesktopPackage and shell:AppsFolder were tried: from a normal process both
      leave a hung ChatGPT.exe with no window and no port.
    #>
    param([Parameter(Mandatory)] [int]$Port)
    if (-not ('CodexMultiProfile.AppActivation' -as [type]) -or -not [CodexMultiProfile.AppActivation].GetMethod('ActivateWithTimeout')) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace CodexMultiProfile {
    [ComImport, Guid("2e941141-7f97-4756-ba1d-9decde894a3d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IApplicationActivationManager {
        int ActivateApplication([MarshalAs(UnmanagedType.LPWStr)] string appUserModelId, [MarshalAs(UnmanagedType.LPWStr)] string arguments, int options, out uint processId);
    }
    [ComImport, Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C")]
    class ApplicationActivationManager { }
    public static class AppActivation {
        public static uint Activate(string appUserModelId, string arguments) {
            uint pid;
            int hr = ((IApplicationActivationManager)new ApplicationActivationManager()).ActivateApplication(appUserModelId, arguments, 0, out pid);
            if (hr != 0) { Marshal.ThrowExceptionForHR(hr); }
            return pid;
        }
        // ActivateApplication waits for the app to come up; never let that freeze the caller.
        public static uint ActivateWithTimeout(string appUserModelId, string arguments, int timeoutMs) {
            var task = System.Threading.Tasks.Task.Run(() => Activate(appUserModelId, arguments));
            return task.Wait(timeoutMs) ? task.Result : 0;
        }
    }
}
'@
    }
    $pkg = Get-CodexStorePackage
    $cdpArgs = "--remote-debugging-address=127.0.0.1 --remote-debugging-port=$Port"
    return [CodexMultiProfile.AppActivation]::ActivateWithTimeout("$($pkg.PackageFamilyName)!App", $cdpArgs, 15000)
}

function Get-CodexLauncherCommand {
    <#
    .SYNOPSIS
      What the Codex shortcut runs: the host in a hidden PowerShell. conhost --headless keeps
      it windowless without VBScript (Windows is phasing VBScript / wscript out).
    #>
    param([string]$Root = (Get-CodexAccountsRoot))
    return [pscustomobject]@{
        FilePath  = Join-Path $env:WINDIR 'System32\conhost.exe'
        Arguments = '--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f (Join-Path $Root 'Start-CodexAccounts.ps1')
    }
}

# ---------------------------------------------------------------- page <-> host

function Get-CodexSwitcherBindingName { return 'cmpSwitcherBridge' }

function Get-CodexAccountsSettings {
    param([string]$Root = (Get-CodexAccountsRoot))
    $port = 9333
    $lang = 'auto'
    $path = Join-Path $Root 'settings.json'
    if (Test-Path -LiteralPath $path) {
        try {
            $obj = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($obj.PSObject.Properties['cdpPort'] -and [int]$obj.cdpPort -gt 1023) { $port = [int]$obj.cdpPort }
            if ($obj.PSObject.Properties['lang'] -and ([string]$obj.lang) -in @('auto', 'vi', 'en')) { $lang = [string]$obj.lang }
        }
        catch { }
    }
    return [pscustomobject]@{ CdpPort = $port; Lang = $lang }
}

function Get-CodexSwitcherSnapshot {
    <#
    .SYNOPSIS
      State pushed into the Codex window. Masked emails only; no tokens, no paths.
    #>
    param(
        [string]$Root = (Get-CodexAccountsRoot),
        [string]$CodexHome = (Get-CodexHome),
        [string]$Pending = ''
    )
    $accounts = @(Get-CodexAccounts -Root $Root)
    $active = Get-CodexActiveAccount -Root $Root -CodexHome $CodexHome
    $activeName = $(if ($active) { $active.Name } else { $null })
    $profiles = @(foreach ($a in $accounts) {
            [ordered]@{
                name       = $a.Name
                account    = (Hide-AuthEmail -Email $a.Email)
                plan       = $a.Plan
                depleted   = $a.Depleted
                needsLogin = (-not $a.Email)
                active     = ($a.Name -eq $activeName)
            }
        })
    # Usage-limit hint: least recently used saved account that is not out of quota.
    $next = @($accounts | Where-Object { $_.Name -ne $activeName -and -not $_.Depleted -and $_.Email } | Sort-Object LastUsed | Select-Object -First 1)
    $settings = Get-CodexAccountsSettings -Root $Root
    return [ordered]@{
        version    = (Get-CodexMultiProfileVersion)
        active     = $activeName
        signedIn   = [bool](Get-AuthIdentity -Path (Join-Path $CodexHome 'auth.json'))
        pending    = $(if ($Pending) { $Pending } else { $null })
        suggestion = $(if ($next.Count) { $next[0].Name } else { $null })
        hotkey     = 'Ctrl+Alt+A'
        lang       = $settings.Lang
        profiles   = $profiles
    }
}

function ConvertFrom-CodexSwitcherMessage {
    <#
    .SYNOPSIS
      Validate one message from the page (CDP binding). Never trusts page input.
      Returns Type / Profile / Name / Value, or Error.
    #>
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Payload,
        [string[]]$KnownProfiles = @()
    )
    function New-Result([string]$Type, [string]$ProfileName, [string]$Name, $Value, [string]$ErrorText) {
        return [pscustomobject]@{ Type = $Type; Profile = $ProfileName; Name = $Name; Value = $Value; Error = $ErrorText }
    }
    if ([string]::IsNullOrWhiteSpace($Payload)) { return (New-Result '' '' '' $null 'empty') }
    if ($Payload.Length -gt 4096) { return (New-Result '' '' '' $null 'too-large') }
    try { $msg = $Payload | ConvertFrom-Json } catch { return (New-Result '' '' '' $null 'bad-json') }
    if ($null -eq $msg -or -not $msg.PSObject -or -not $msg.PSObject.Properties['type']) { return (New-Result '' '' '' $null 'no-type') }
    $type = [string]$msg.type
    if (@('hello', 'refresh', 'switch', 'add', 'remove', 'rename', 'depleted', 'cancel-add') -notcontains $type) {
        return (New-Result $type '' '' $null 'unknown-type')
    }
    $target = ''
    if ($type -in @('switch', 'remove', 'rename', 'depleted')) {
        if (-not $msg.PSObject.Properties['profile']) { return (New-Result $type '' '' $null 'no-profile') }
        $target = [string]$msg.profile
        if ($target -notmatch '^[a-z0-9][a-z0-9\-]{0,63}$') { return (New-Result $type '' '' $null 'bad-profile') }
        if ($KnownProfiles -notcontains $target) { return (New-Result $type $target '' $null 'unknown-profile') }
    }
    $name = ''
    if ($type -in @('add', 'rename')) {
        $raw = ''
        if ($msg.PSObject.Properties['name']) { $raw = [string]$msg.name }
        if ($raw.Length -gt 64) { return (New-Result $type $target '' $null 'bad-name') }
        try { $name = ConvertTo-AccountKey -Name $raw } catch { return (New-Result $type $target '' $null 'bad-name') }
        if ($KnownProfiles -contains $name -and $name -ne $target) { return (New-Result $type $target $name $null 'exists') }
    }
    $value = $null
    if ($type -eq 'depleted') {
        $value = $true
        if ($msg.PSObject.Properties['value'] -and $msg.value -is [bool]) { $value = [bool]$msg.value }
    }
    return (New-Result $type $target $name $value '')
}

Export-ModuleMember -Function *
