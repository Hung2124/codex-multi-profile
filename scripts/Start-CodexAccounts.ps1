#Requires -Version 5.1
<#
.SYNOPSIS
  Open the Microsoft Store Codex with the account list in its avatar menu.

.DESCRIPTION
  What the "Codex" shortcut runs (hidden). It starts the Store Codex inside its package
  with the DevTools protocol on 127.0.0.1, injects switcher-inject.js into the main
  window and stays in the background as the bridge for that menu:

    switch  -> close Codex, sync the outgoing login, put the chosen auth.json in place, reopen
    add     -> close Codex, reopen on the sign-in screen, save the new login under the chosen name
    remove / rename / out-of-quota flag

  While Codex runs it keeps each saved account in sync with the live ~/.codex/auth.json
  (Codex rotates refresh tokens). It exits when Codex is closed.

  No HTTP listener, no token sent to the page (masked emails only), Codex files are not patched.
#>
[CmdletBinding()]
param(
    [int]$Port = 0,
    [string]$Root = (Join-Path $env:LOCALAPPDATA 'CodexMultiProfile'),
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' })
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'CodexAccounts.psm1') -Force

$script:NextId = 1
$script:Pending = ''        # name for the account being added (sign-in screen is up)
$script:PendingReturn = ''  # account to go back to if the add is cancelled
$script:QueuedToast = $null # toast to show once the reopened window says hello
$script:LastAction = [datetime]::MinValue

function Write-HostLog([string]$Message) { Write-CodexLog -Message "[host] $Message" -Root $Root }

# ---------------------------------------------------------------- CDP plumbing

function Test-CdpOwnerIsStoreCodex {
    # Only attach when the port belongs to the Store Codex, never a browser or anything else.
    $owners = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | ForEach-Object { $_.OwningProcess } | Select-Object -Unique)
    if ($owners.Count -eq 0) { return $false }
    foreach ($ownerPid in $owners) {
        $p = Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f [int]$ownerPid) -ErrorAction SilentlyContinue
        if (-not $p -or $p.Name -ne 'ChatGPT.exe' -or [string]$p.ExecutablePath -notlike '*\WindowsApps\OpenAI.Codex_*') { return $false }
    }
    return $true
}

function Get-CdpTargets {
    $client = New-Object System.Net.WebClient
    $client.Proxy = $null
    $client.Encoding = [Text.Encoding]::UTF8
    try { $json = $client.DownloadString("http://127.0.0.1:$Port/json/list") } finally { $client.Dispose() }
    return (Select-CdpMainPages -Json $json -CdpPort $Port)
}

function Select-CdpMainPages {
    # Codex main window only (not the Mini, detached or avatar-overlay windows), loopback websocket only.
    param([Parameter(Mandatory)] [string]$Json, [Parameter(Mandatory)] [int]$CdpPort)
    # Assign first: Windows PowerShell 5.1 emits a JSON array as ONE object in a pipeline.
    $items = ConvertFrom-Json -InputObject $Json
    return @($items | Where-Object {
            [string]$_.type -eq 'page' -and ([string]$_.url).StartsWith('app://-/index.html') -and
            ([string]$_.url) -notmatch 'initialRoute=' -and
            ([string]$_.webSocketDebuggerUrl).StartsWith("ws://127.0.0.1:$CdpPort/")
        })
}

function Send-CdpMessage {
    param([Parameter(Mandatory)] $Conn, [Parameter(Mandatory)] [string]$Method, [hashtable]$Params = @{})
    $id = $script:NextId
    $script:NextId++
    $bytes = [Text.Encoding]::UTF8.GetBytes((@{ id = $id; method = $Method; params = $Params } | ConvertTo-Json -Depth 8 -Compress))
    $seg = New-Object System.ArraySegment[byte] -ArgumentList @(, $bytes)
    $cts = New-Object System.Threading.CancellationTokenSource
    $cts.CancelAfter(10000)
    try { $Conn.Ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).Wait() }
    finally { $cts.Dispose() }
}

function Start-CdpReceive($Conn) {
    $Conn.Task = $Conn.Ws.ReceiveAsync($Conn.Segment, [System.Threading.CancellationToken]::None)
}

function Connect-CdpTarget {
    param([Parameter(Mandatory)] $Target, [Parameter(Mandatory)] [string]$Source)
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    try { $ws.Options.Proxy = $null } catch { }
    $cts = New-Object System.Threading.CancellationTokenSource
    $cts.CancelAfter(10000)
    try { $ws.ConnectAsync([Uri][string]$Target.webSocketDebuggerUrl, $cts.Token).Wait() }
    finally { $cts.Dispose() }
    $buffer = New-Object byte[] 65536
    $conn = [pscustomobject]@{
        TargetId = [string]$Target.id
        Ws       = $ws
        Buffer   = $buffer
        Segment  = (New-Object System.ArraySegment[byte] -ArgumentList @(, $buffer))
        Stream   = (New-Object System.IO.MemoryStream)
        Task     = $null
    }
    # No Runtime.enable: bindingCalled arrives without it, and it would stream every Codex console
    # message through this PowerShell process. Page.enable is needed (and cheap: a few events per
    # navigation) for the new-document script to run again when Codex reloads its window.
    Send-CdpMessage -Conn $conn -Method 'Runtime.addBinding' -Params @{ name = (Get-CodexSwitcherBindingName) }
    Send-CdpMessage -Conn $conn -Method 'Page.enable'
    Send-CdpMessage -Conn $conn -Method 'Page.addScriptToEvaluateOnNewDocument' -Params @{ source = $Source }
    Send-CdpMessage -Conn $conn -Method 'Runtime.evaluate' -Params @{ expression = $Source; returnByValue = $true }
    Start-CdpReceive $conn
    return $conn
}

function Close-CdpConn($Conn) {
    try {
        if ($Conn.Ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            $cts = New-Object System.Threading.CancellationTokenSource
            $cts.CancelAfter(2000)
            $Conn.Ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'bye', $cts.Token).Wait()
        }
    }
    catch { }
    try { $Conn.Ws.Dispose() } catch { }
    try { $Conn.Stream.Dispose() } catch { }
}

function Receive-CdpMessage($Conn) {
    # Whole message text, '' while more frames are due, $null when the socket closed.
    $result = $Conn.Task.Result
    if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) { return $null }
    $Conn.Stream.Write($Conn.Buffer, 0, $result.Count)
    if (-not $result.EndOfMessage) { Start-CdpReceive $Conn; return '' }
    $text = [Text.Encoding]::UTF8.GetString($Conn.Stream.ToArray())
    $Conn.Stream.SetLength(0)
    Start-CdpReceive $Conn
    return $text
}

# ---------------------------------------------------------------- page events

function Send-PageEvent([object[]]$Conns, [hashtable]$Event) {
    $json = $Event | ConvertTo-Json -Depth 8 -Compress
    if (Test-CodexTextHasFullEmail -Text $json) { Write-HostLog 'BLOCKED an event with an unmasked email'; return }
    $expr = "if (window.__cmpSwitcher) { window.__cmpSwitcher.receive($json); }"
    foreach ($c in $Conns) {
        try { Send-CdpMessage -Conn $c -Method 'Runtime.evaluate' -Params @{ expression = $expr; returnByValue = $true } } catch { }
    }
}

function Test-CodexStoreRunning {
    # Cheap check (no WMI): any Store Codex process left.
    return [bool](Get-Process -Name 'ChatGPT' -ErrorAction SilentlyContinue | Where-Object { [string]$_.Path -like '*\WindowsApps\OpenAI.Codex_*' } | Select-Object -First 1)
}

function Get-StoreFingerprint {
    $parts = foreach ($p in @((Join-Path $CodexHome 'auth.json'), (Join-Path $Root 'accounts'), (Join-Path $Root 'accounts.json'))) {
        $i = Get-Item -LiteralPath $p -ErrorAction SilentlyContinue
        if ($i) { $i.LastWriteTimeUtc.Ticks } else { 0 }
    }
    return (($parts -join '|') + '|' + $script:Pending)
}

function Send-PageState([object[]]$Conns) {
    $snap = Get-CodexSwitcherSnapshot -Root $Root -CodexHome $CodexHome -Pending $script:Pending
    Send-PageEvent $Conns @{ kind = 'state'; state = $snap }
}

function Send-PageToast([object[]]$Conns, [string]$Level, [string]$Code, [string]$Detail = '') {
    Send-PageEvent $Conns @{ kind = 'toast'; level = $Level; code = $Code; detail = $Detail }
}

# ---------------------------------------------------------------- actions

function Restart-Codex {
    <#
    .SYNOPSIS
      Close Codex, run $Swap (auth.json changes happen while Codex is closed), reopen with CDP.
      Codex is always reopened, whatever failed, on whatever login is in place.
    #>
    param([Parameter(Mandatory)] [scriptblock]$Swap)
    $t0 = Get-Date
    $closed = 0
    try {
        Stop-CodexStore
        $closed = ((Get-Date) - $t0).TotalSeconds
        if (Test-CodexStoreRunning) { throw 'Codex did not close; the login was left as it was.' }
        & $Swap
    }
    finally {
        $codexPid = Start-CodexStore -Port $Port
        Write-HostLog ("restart: closed in {0:n1}s, reopened pid={1} after {2:n1}s" -f $closed, $codexPid, ((Get-Date) - $t0).TotalSeconds)
    }
}

function Invoke-LoginChange {
    <#
    .SYNOPSIS
      Change the login Codex uses. Fast path: restart only the app-server, the window stays (2-3 s).
      Fallback: restart Codex. $Swap must be safe to run twice. Returns $true when Codex was restarted
      (the page is gone and must be attached again).
    #>
    param([Parameter(Mandatory)] [scriptblock]$Swap, [switch]$Full)
    $t0 = Get-Date
    if (-not $Full -and (Restart-CodexAppServer -Swap $Swap)) {
        Write-HostLog ("fast switch: new app-server after {0:n1}s" -f ((Get-Date) - $t0).TotalSeconds)
        return $false
    }
    if (-not $Full) { Write-HostLog 'fast switch unavailable; restarting Codex' }
    Restart-Codex -Swap $Swap
    return $true
}

function Complete-LoginChange {
    <#
    .SYNOPSIS
      Run a login change for the page and report the outcome to it. Returns $true when Codex was
      restarted (attach again).
    #>
    param([object[]]$Conns, [string]$Profile, [scriptblock]$Swap, [switch]$Add, [switch]$Full)
    try { $restarted = Invoke-LoginChange -Swap $Swap -Full:$Full }
    catch {
        $script:LastAction = Get-Date
        $what = $(if ($Add) { 'add' } else { 'switch' })
        Write-HostLog ("{0} {1} failed: {2}" -f $what, $Profile, $_.Exception.Message)
        if ($Add) { $script:Pending = ''; $script:PendingReturn = '' }
        # The page may still be there (fast path) or come back after a restart: tell it both ways.
        Send-PageToast $Conns 'error' "$what-failed" $Profile
        $script:QueuedToast = @{ Level = 'error'; Code = "$what-failed"; Detail = $Profile }
        return $false
    }
    # The double-click guard counts from the end of a change: a click queued while it ran is not a new request.
    $script:LastAction = Get-Date
    if (-not $restarted) {
        Send-PageState $Conns
        Send-PageEvent $Conns @{ kind = 'switched'; profile = $Profile; add = [bool]$Add }
    }
    return $restarted
}

function Invoke-PageRequest {
    param([Parameter(Mandatory)] [string]$Payload, [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Conns)
    $known = @(Get-CodexAccounts -Root $Root | ForEach-Object { $_.Name })
    $req = ConvertFrom-CodexSwitcherMessage -Payload $Payload -KnownProfiles $known
    if ($req.Error) {
        Write-HostLog ("rejected {0}: {1}" -f $req.Type, $req.Error)
        Send-PageToast $Conns 'error' $req.Error $req.Name
        return $false
    }
    # Double-click guard. The page shows a waiting card, so always answer instead of ignoring.
    $busy = ((Get-Date) - $script:LastAction).TotalSeconds -lt 1.5
    switch ($req.Type) {
        { $_ -in @('hello', 'refresh') } {
            Send-PageState $Conns
            if ($_ -eq 'hello' -and $script:QueuedToast) {
                $q = $script:QueuedToast
                $script:QueuedToast = $null
                Send-PageToast $Conns $q.Level $q.Code $q.Detail
            }
        }
        'switch' {
            $active = Get-CodexActiveAccount -Root $Root -CodexHome $CodexHome
            if ($active -and $active.Name -eq $req.Profile) { Send-PageToast $Conns 'info' 'already-active' $req.Profile; return $false }
            if ($busy) { Send-PageToast $Conns 'info' 'busy'; return $false }
            $script:LastAction = Get-Date
            Write-HostLog ("switch {0} -> {1}" -f $(if ($active) { $active.Name } else { '(none)' }), $req.Profile)
            Send-PageEvent $Conns @{ kind = 'switching'; profile = $req.Profile }
            $target = $req.Profile
            $script:Pending = ''
            $script:PendingReturn = ''
            return (Complete-LoginChange -Conns $Conns -Profile $target -Full:(-not $req.Value) -Swap { Set-CodexLiveAuth -Name $target -Root $Root -CodexHome $CodexHome })
        }
        'add' {
            if ($busy) { Send-PageToast $Conns 'info' 'busy'; return $false }
            $script:LastAction = Get-Date
            $active = Get-CodexActiveAccount -Root $Root -CodexHome $CodexHome
            Write-HostLog ("add {0}: opening the sign-in screen" -f $req.Name)
            Send-PageEvent $Conns @{ kind = 'switching'; profile = $req.Name; add = $true }
            $script:Pending = $req.Name
            $script:PendingReturn = $(if ($active) { $active.Name } else { '' })
            # The sign-in screen only appears when Codex starts without a login: full restart.
            return (Complete-LoginChange -Conns $Conns -Profile $req.Name -Add -Full -Swap { Clear-CodexLiveAuth -Root $Root -CodexHome $CodexHome })
        }
        'cancel-add' {
            if (-not $script:Pending) { return $false }
            $back = $script:PendingReturn
            Write-HostLog ("add {0} cancelled, back to {1}" -f $script:Pending, $back)
            $script:Pending = ''
            $script:PendingReturn = ''
            if (-not $back -or (Get-AuthIdentity -Path (Join-Path $CodexHome 'auth.json'))) { Send-PageState $Conns; return $false }
            $script:LastAction = Get-Date
            Send-PageEvent $Conns @{ kind = 'switching'; profile = $back }
            # Leaving the sign-in screen needs a restart as well.
            return (Complete-LoginChange -Conns $Conns -Profile $back -Full -Swap { Set-CodexLiveAuth -Name $back -Root $Root -CodexHome $CodexHome })
        }
        'remove' {
            try { Remove-CodexAccount -Name $req.Profile -Root $Root -CodexHome $CodexHome }
            catch {
                Write-HostLog ("remove {0} failed: {1}" -f $req.Profile, $_.Exception.Message)
                Send-PageState $Conns
                Send-PageToast $Conns 'error' 'remove-failed' $req.Profile
                return $false
            }
            Write-HostLog ("removed {0}" -f $req.Profile)
            Send-PageState $Conns
            Send-PageToast $Conns 'success' 'removed' $req.Profile
        }
        'rename' {
            try { $new = Rename-CodexAccount -Name $req.Profile -NewName $req.Name -Root $Root }
            catch {
                Write-HostLog ("rename {0} failed: {1}" -f $req.Profile, $_.Exception.Message)
                Send-PageToast $Conns 'error' 'rename-failed' $req.Profile
                return $false
            }
            Write-HostLog ("renamed {0} -> {1}" -f $req.Profile, $new)
            Send-PageState $Conns
            Send-PageToast $Conns 'success' 'renamed' $new
        }
        'depleted' {
            Set-CodexAccountMeta -Name $req.Profile -Root $Root -Depleted ([bool]$req.Value)
            Send-PageState $Conns
        }
    }
    return $false
}

function Update-FromLiveAuth([object[]]$Conns) {
    <#
    .SYNOPSIS
      Keep the account in use in sync; finish a pending add once Codex has signed in.
    #>
    try { $null = Sync-CodexActiveAccount -Root $Root -CodexHome $CodexHome } catch { Write-HostLog ("sync failed: " + $_.Exception.Message) }
    $id = Get-AuthIdentity -Path (Join-Path $CodexHome 'auth.json')
    if (-not $id) { return }
    if (-not $script:Pending) {
        # Signed in to a login that is not saved (e.g. another account on a sign-in screen): keep it.
        if (Find-CodexAccountByIdentity -Identity $id -Root $Root) { return }
        try { $saved = Save-CodexAccount -Root $Root -CodexHome $CodexHome } catch { Write-HostLog ("auto-save failed: " + $_.Exception.Message); return }
        Write-HostLog ("saved a new login as {0} ({1})" -f $saved, (Hide-AuthEmail -Email $id.Email))
        Send-PageState $Conns
        Send-PageToast $Conns 'success' 'added' $saved
        return
    }
    $name = $script:Pending
    $script:Pending = ''
    $script:PendingReturn = ''
    $existing = Find-CodexAccountByIdentity -Identity $id -Root $Root
    if ($existing) {
        Write-HostLog ("add {0}: that login is already saved as {1}" -f $name, $existing.Name)
        Send-PageState $Conns
        Send-PageToast $Conns 'info' 'exists-as' $existing.Name
        return
    }
    try { $saved = Save-CodexAccount -Name $name -Root $Root -CodexHome $CodexHome }
    catch {
        Write-HostLog ("add {0} failed: {1}" -f $name, $_.Exception.Message)
        Send-PageToast $Conns 'error' 'add-failed' $name
        return
    }
    Write-HostLog ("added {0} ({1})" -f $saved, (Hide-AuthEmail -Email $id.Email))
    Send-PageState $Conns
    Send-PageToast $Conns 'success' 'added' $saved
}

# ---------------------------------------------------------------- main loop

function Invoke-AccountsHost {
    $source = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'switcher-inject.js') -Raw -Encoding UTF8
    $binding = Get-CodexSwitcherBindingName
    $conns = New-Object System.Collections.ArrayList
    $lastDiscover = [datetime]::MinValue
    $lastSync = [datetime]::MinValue
    $lastFingerprint = ''
    $goneSince = $null
    Write-HostLog ("host start port={0}" -f $Port)

    while ($true) {
      try {
        $now = Get-Date
        # Attached: the socket closing tells us when the window goes, so look around rarely.
        if (($now - $lastDiscover).TotalSeconds -ge $(if ($conns.Count) { 15 } else { 1 })) {
            $lastDiscover = $now
            if (-not (Test-CodexStoreRunning)) {
                if (-not $goneSince) { $goneSince = $now }
                if (($now - $goneSince).TotalSeconds -ge 8) { break }
            }
            else { $goneSince = $null }
            $targets = @()
            try { $targets = @(Get-CdpTargets) } catch { $targets = @() }
            $fresh = @($targets | Where-Object { $id = [string]$_.id; -not @($conns | Where-Object { $_.TargetId -eq $id }).Count })
            if ($fresh.Count -gt 0) {
                if (-not (Test-CdpOwnerIsStoreCodex)) { Write-HostLog 'REFUSED: the CDP port is not owned by the Store Codex'; break }
                foreach ($t in $fresh) {
                    try {
                        $c = Connect-CdpTarget -Target $t -Source $source
                        [void]$conns.Add($c)
                        Write-HostLog ("attached {0}" -f $t.id)
                        Send-PageState @($c)
                    }
                    catch { Write-HostLog ("attach failed: " + $_.Exception.Message) }
                }
            }
        }

        # Only when auth.json or the account store changed (token refresh, sign-in, CLI edits).
        if (($now - $lastSync).TotalSeconds -ge 3) {
            $lastSync = $now
            # Safety net: normal use stays around 150 MB. Whatever went wrong, never weigh on the PC.
            $mem = [System.Diagnostics.Process]::GetCurrentProcess().WorkingSet64
            if ($mem -gt 500MB) { Write-HostLog ("helper memory {0} MB, exiting to stay light" -f [int]($mem / 1MB)); break }
            $fingerprint = Get-StoreFingerprint
            if ($fingerprint -ne $lastFingerprint) {
                $lastFingerprint = $fingerprint
                Update-FromLiveAuth @($conns)
                try { Send-PageState @($conns) } catch { }
            }
        }

        if ($conns.Count -eq 0) { Start-Sleep -Milliseconds 500; continue }

        $idx = [System.Threading.Tasks.Task]::WaitAny([System.Threading.Tasks.Task[]]@($conns | ForEach-Object { $_.Task }), 1000)
        if ($idx -lt 0) { continue }
        $conn = $conns[$idx]
        $text = $null
        try { if (-not ($conn.Task.IsFaulted -or $conn.Task.IsCanceled)) { $text = Receive-CdpMessage $conn } } catch { $text = $null }
        if ($null -eq $text) {
            Write-HostLog ("detached {0}" -f $conn.TargetId)
            Close-CdpConn $conn
            $conns.RemoveAt($idx)
            continue
        }
        if (-not $text) { continue }
        if ($text.Contains('"Page.domContentEventFired"')) {
            # Codex reloaded its window. Without Runtime.enable the binding is not carried into the new
            # page by itself; re-adding it does (the script itself comes back via addScriptToEvaluateOnNewDocument).
            # The new-document script is sometimes missing after the first reload; evaluate it too (it guards
            # against running twice), so the menu is always back.
            try {
                Send-CdpMessage -Conn $conn -Method 'Runtime.removeBinding' -Params @{ name = $binding }
                Send-CdpMessage -Conn $conn -Method 'Runtime.addBinding' -Params @{ name = $binding }
                Send-CdpMessage -Conn $conn -Method 'Runtime.evaluate' -Params @{ expression = $source; returnByValue = $true }
            }
            catch { }
            # Do not wait for the page's hello: a hidden window runs its timers very late.
            try { Send-PageState @($conn) } catch { }
            continue
        }
        # Replies to our own commands are skipped without parsing; only the page's requests matter.
        if (-not $text.Contains('"Runtime.bindingCalled"')) { continue }
        $msg = $null
        try { $msg = ConvertFrom-Json -InputObject $text } catch { continue }
        if ([string]$msg.params.name -eq $binding) {
            $restarted = $false
            try { $restarted = Invoke-PageRequest -Payload ([string]$msg.params.payload) -Conns @($conns) }
            catch {
                Write-HostLog ("request failed: " + $_.Exception.Message)
                Send-PageToast @($conns) 'error' 'host-error'
            }
            if ($restarted) {
                # Codex was closed and reopened: drop the dead sockets, attach to the new window.
                foreach ($c in @($conns)) { Close-CdpConn $c }
                $conns.Clear()
                $lastFingerprint = ''
                $goneSince = $null
            }
        }
      }
      catch {
        # Keep serving: one unexpected error must not leave the menu without its helper.
        Write-HostLog ("loop error: " + $_.Exception.Message)
        Start-Sleep -Milliseconds 500
      }
    }

    foreach ($c in @($conns)) { Close-CdpConn $c }
    try { $null = Sync-CodexActiveAccount -Root $Root -CodexHome $CodexHome } catch { }
    Write-HostLog 'host exit (Codex closed)'
}

function Start-CodexWithAccounts {
    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    if ($Port -le 0) { $script:Port = (Get-CodexAccountsSettings -Root $Root).CdpPort }

    $mutex = New-Object System.Threading.Mutex($false, 'Local\CodexMultiProfileHost')
    $owned = $false
    try { $owned = $mutex.WaitOne(0) }
    catch {
        # A killed host leaves the mutex abandoned; WaitOne still hands it over.
        $ex = $_.Exception
        if ($ex -is [System.Threading.AbandonedMutexException] -or $ex.InnerException -is [System.Threading.AbandonedMutexException]) { $owned = $true }
        else { throw }
    }
    if (-not $owned) {
        # A host is already serving Codex: just bring Codex up / to the front.
        $null = Start-CodexStore -Port $Port
        return
    }
    try {
        # The login in use is always saved, so switching away can never lose it.
        $live = Get-AuthIdentity -Path (Join-Path $CodexHome 'auth.json')
        if ($live -and -not (Find-CodexAccountByIdentity -Identity $live -Root $Root)) {
            $name = Save-CodexAccount -Root $Root -CodexHome $CodexHome
            Write-HostLog ("saved the current login as {0} ({1})" -f $name, (Hide-AuthEmail -Email $live.Email))
        }
        if (-not (Test-CodexStoreHasCdp -Port $Port)) {
            if (@(Get-CodexStoreProcesses).Count -gt 0) {
                Write-HostLog 'Codex was opened without the account menu; reopening it'
                Stop-CodexStore
            }
            $null = Start-CodexStore -Port $Port
        }
        Invoke-AccountsHost
    }
    finally {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
}

# Dot-sourcing loads the functions only (tests); running the file starts Codex + the host.
if ($MyInvocation.InvocationName -ne '.') {
    try { Start-CodexWithAccounts }
    catch {
        Write-HostLog ("ERROR: " + $_.Exception.Message)
        exit 1
    }
}
