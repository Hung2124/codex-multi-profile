#Requires -Version 5.1
<#
.SYNOPSIS
  In-app account switcher bridge for the cloned ChatGPT.exe (opt-in).

.DESCRIPTION
  Hidden helper started by Launch-CodexProfile.ps1 when switcher-state.json has
  enabled=true. It attaches Chrome DevTools Protocol on 127.0.0.1 to the *cloned*
  Codex window, injects switcher-inject.js (account pill + menu, Ctrl+Alt+A) and
  listens on a CDP binding (Runtime.addBinding) for clicks in that menu.

  A pick runs the existing Launch-CodexProfile.ps1 -FastSwitch: the same one-window
  AuthSwap as the Codex Accounts app (close clone, swap auth.json, reopen through the
  .cmd env wrapper). No HTTP listener, no token on disk, no asar/ChatGPT.exe patch,
  never the Microsoft Store package.

  The host exits when the clone closes. The next launch starts a fresh one.
#>
[CmdletBinding()]
param(
    [int]$Port = 9333,
    [string]$ProfileKey,
    [string]$ParallelRoot = (Join-Path $env:LOCALAPPDATA 'CodexParallelDesktop'),
    [string]$SourceHome = (Join-Path $env:USERPROFILE '.codex'),
    [int]$AttachTimeoutSec = 60
)

$ErrorActionPreference = 'Stop'
$script:HostRoot = $PSScriptRoot
$core = Join-Path $script:HostRoot 'CodexMultiProfile.psm1'
if (-not (Test-Path -LiteralPath $core)) { throw "Missing $core" }
Import-Module $core -Force
$routerMod = Join-Path $script:HostRoot 'CodexRouter.psm1'
if (-not (Test-Path -LiteralPath $routerMod)) { throw "Missing $routerMod" }
Import-Module $routerMod -Force

$script:LogPath = Join-Path $ParallelRoot 'launch-trace.log'
$script:NextId = 1
$script:LastSwitchUtc = [datetime]::MinValue
$script:Switching = $false

function Write-SwitcherLog([string]$Message) {
    Add-Content -LiteralPath $script:LogPath -Value "$(Get-Date -Format HH:mm:ss.fff) [switcher] $Message" -ErrorAction SilentlyContinue
}

function Test-CodexStoreRunning {
    $items = @(Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'" -ErrorAction SilentlyContinue)
    return (@($items | Where-Object { [string]$_.ExecutablePath -like '*WindowsApps*' }).Count -gt 0)
}

function Test-CodexCloneRunning {
    $items = @(Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'" -ErrorAction SilentlyContinue)
    $clone = @($items | Where-Object {
            ([string]$_.ExecutablePath -like '*CodexParallelDesktop*') -or
            ([string]$_.CommandLine -like '*CodexParallelDesktop*')
        })
    return ($clone.Count -gt 0)
}

function Test-CodexCdpOwnerIsClone {
    <#
    .SYNOPSIS
      The process listening on the CDP port must be the cloned ChatGPT.exe.
      Refuses a browser or anything else that happens to use the same port.
    #>
    param([Parameter(Mandatory)] [int]$CdpPort)
    $owners = @()
    try {
        $owners = @(Get-NetTCPConnection -LocalPort $CdpPort -State Listen -ErrorAction Stop |
            ForEach-Object { $_.OwningProcess } | Select-Object -Unique)
    }
    catch {
        # Get-NetTCPConnection missing (very old Windows): fall back to a clone-only process check.
        return ((Test-CodexCloneRunning) -and -not (Test-CodexStoreRunning))
    }
    if ($owners.Count -eq 0) { return $false }
    foreach ($ownerPid in $owners) {
        $p = Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f [int]$ownerPid) -ErrorAction SilentlyContinue
        if (-not $p) { return $false }
        $path = [string]$p.ExecutablePath
        if ($path -like '*WindowsApps*') { return $false }
        if ($p.Name -ne 'ChatGPT.exe') { return $false }
        if ($path -notlike '*CodexParallelDesktop*' -and [string]$p.CommandLine -notlike '*CodexParallelDesktop*') { return $false }
    }
    return $true
}

function Get-CdpTargets([int]$CdpPort) {
    $client = New-Object System.Net.WebClient
    $client.Proxy = $null
    $client.Encoding = [Text.Encoding]::UTF8
    try {
        $json = $client.DownloadString("http://127.0.0.1:$CdpPort/json/list")
    }
    finally {
        $client.Dispose()
    }
    $items = @($json | ConvertFrom-Json)
    return @($items | Where-Object {
            $_.PSObject.Properties['type'] -and [string]$_.type -eq 'page' -and
            $_.PSObject.Properties['webSocketDebuggerUrl'] -and
            -not ([string]$_.url).StartsWith('devtools://')
        })
}

function Test-LoopbackWsUrl([string]$Url) {
    return ($Url -like 'ws://127.0.0.1:*' -or $Url -like 'ws://localhost:*')
}

function Send-CdpMessage {
    param(
        [Parameter(Mandatory)] $Conn,
        [Parameter(Mandatory)] [string]$Method,
        [hashtable]$Params = @{}
    )
    $id = $script:NextId
    $script:NextId = $script:NextId + 1
    $payload = @{ id = $id; method = $Method; params = $Params } | ConvertTo-Json -Depth 8 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($payload)
    $seg = New-Object System.ArraySegment[byte] -ArgumentList @(, $bytes)
    $cts = New-Object System.Threading.CancellationTokenSource
    $cts.CancelAfter(10000)
    try {
        $Conn.Ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).Wait()
    }
    finally {
        $cts.Dispose()
    }
}

function Start-CdpReceive($Conn) {
    $Conn.Task = $Conn.Ws.ReceiveAsync($Conn.Segment, [System.Threading.CancellationToken]::None)
}

function Connect-CdpTarget {
    param(
        [Parameter(Mandatory)] $Target,
        [Parameter(Mandatory)] [string]$Source
    )
    $wsUrl = [string]$Target.webSocketDebuggerUrl
    if (-not (Test-LoopbackWsUrl $wsUrl)) { throw "Refusing non-loopback CDP websocket: $wsUrl" }
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    try { $ws.Options.Proxy = $null } catch { }
    $cts = New-Object System.Threading.CancellationTokenSource
    $cts.CancelAfter(10000)
    try {
        $ws.ConnectAsync([Uri]$wsUrl, $cts.Token).Wait()
    }
    finally {
        $cts.Dispose()
    }
    $buffer = New-Object byte[] 65536
    $conn = [pscustomobject]@{
        TargetId = [string]$Target.id
        Ws       = $ws
        Buffer   = $buffer
        Segment  = (New-Object System.ArraySegment[byte] -ArgumentList @(, $buffer))
        Stream   = (New-Object System.IO.MemoryStream)
        Task     = $null
    }
    Send-CdpMessage -Conn $conn -Method 'Runtime.enable'
    Send-CdpMessage -Conn $conn -Method 'Runtime.addBinding' -Params @{ name = (Get-CodexSwitcherBindingName) }
    # Page.enable is required for the new-document script to survive reloads.
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

function Send-SwitcherEvent {
    <#
    .SYNOPSIS
      Push one event into the page: window.__cmpSwitcher.receive(<json>).
    #>
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Conns,
        [Parameter(Mandatory)] [hashtable]$Event
    )
    $json = $Event | ConvertTo-Json -Depth 8 -Compress
    if (Test-CodexTextHasFullEmail -Text $json) {
        Write-SwitcherLog 'BLOCKED event that contained an unmasked email'
        return
    }
    $expr = "if (window.__cmpSwitcher) { window.__cmpSwitcher.receive($json); }"
    foreach ($c in $Conns) {
        try { Send-CdpMessage -Conn $c -Method 'Runtime.evaluate' -Params @{ expression = $expr; returnByValue = $true } } catch { }
    }
}

function Send-SwitcherState([object[]]$Conns) {
    $snapshot = Get-CodexSwitcherSnapshot -ParallelRoot $ParallelRoot -SourceHome $SourceHome -ActiveProfile $script:Active
    Send-SwitcherEvent -Conns $Conns -Event @{ kind = 'state'; state = $snapshot; switching = $script:Switching }
}

function Send-SwitcherToast([object[]]$Conns, [string]$Level, [string]$Code, [string]$Detail = '') {
    Send-SwitcherEvent -Conns $Conns -Event @{ kind = 'toast'; level = $Level; code = $Code; detail = $Detail }
}

function Start-HiddenScript([string]$FileName, [string[]]$ScriptArgs = @()) {
    $path = Join-Path $script:HostRoot $FileName
    if (-not (Test-Path -LiteralPath $path)) { $path = Join-Path $ParallelRoot $FileName }
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing $FileName" }
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $path) + $ScriptArgs
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList $argList | Out-Null
}

function New-SwitcherProfile([string]$Name) {
    # Same path as Codex Accounts "Add": CodexProfile.ps1 -Action new (folder + shortcut, clone check).
    $manager = Join-Path $script:HostRoot 'CodexProfile.ps1'
    if (-not (Test-Path -LiteralPath $manager)) { $manager = Join-Path $ParallelRoot 'CodexProfile.ps1' }
    $null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $manager -Action new -Name $Name 2>&1
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        Write-SwitcherLog ("add {0} failed exit={1}" -f $Name, $LASTEXITCODE)
        return $false
    }
    return $true
}

function Invoke-SwitcherRequest {
    param(
        [Parameter(Mandatory)] [string]$Payload,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Conns
    )
    $known = @(Get-CodexKnownProfileNames -ParallelRoot $ParallelRoot)
    $req = ConvertFrom-CodexSwitcherMessage -Payload $Payload -KnownProfiles $known
    if ($req.Error) {
        Write-SwitcherLog ("rejected request type={0} error={1}" -f $req.Type, $req.Error)
        Send-SwitcherToast -Conns $Conns -Level 'error' -Code $req.Error -Detail $req.Name
        return
    }
    switch ($req.Type) {
        { $_ -in @('hello', 'refresh') } {
            Send-SwitcherState $Conns
        }
        'switch' {
            if ($req.Profile -eq $script:Active) {
                Send-SwitcherToast -Conns $Conns -Level 'info' -Code 'already-active' -Detail $req.Profile
                return
            }
            $now = [datetime]::UtcNow
            if ($script:Switching -or ($now - $script:LastSwitchUtc).TotalSeconds -lt 4) { return }
            $script:LastSwitchUtc = $now
            $script:Switching = $true
            Write-SwitcherLog ("switch {0} -> {1}" -f $script:Active, $req.Profile)
            Send-SwitcherEvent -Conns $Conns -Event @{ kind = 'switching'; profile = $req.Profile }
            Start-HiddenScript -FileName 'Launch-CodexProfile.ps1' -ScriptArgs @('-Name', $req.Profile, '-FastSwitch')
        }
        'main' {
            $now = [datetime]::UtcNow
            if ($script:Switching -or ($now - $script:LastSwitchUtc).TotalSeconds -lt 4) { return }
            $script:LastSwitchUtc = $now
            $script:Switching = $true
            Write-SwitcherLog ("switch {0} -> main (Store Codex)" -f $script:Active)
            Send-SwitcherEvent -Conns $Conns -Event @{ kind = 'switching'; profile = ''; main = $true }
            Start-HiddenScript -FileName 'Launch-CodexMain.ps1'
        }
        'depleted' {
            $clear = -not [bool]$req.Value
            $null = Set-CodexProfileDepleted -Name $req.Profile -ParallelRoot $ParallelRoot -Clear:$clear
            Write-SwitcherLog ("depleted {0}={1}" -f $req.Profile, (-not $clear))
            Send-SwitcherState $Conns
        }
        'add' {
            if (-not (New-SwitcherProfile -Name $req.Name)) {
                Send-SwitcherToast -Conns $Conns -Level 'error' -Code 'add-failed' -Detail $req.Name
                return
            }
            Write-SwitcherLog ("added profile {0}" -f $req.Name)
            Send-SwitcherState $Conns
            Send-SwitcherToast -Conns $Conns -Level 'success' -Code 'added' -Detail $req.Name
        }
        'remove' {
            if ($req.Profile -eq $script:Active) {
                Send-SwitcherToast -Conns $Conns -Level 'error' -Code 'remove-active' -Detail $req.Profile
                return
            }
            try {
                $null = Remove-CodexProfile -Name $req.Profile -ParallelRoot $ParallelRoot
            }
            catch {
                Write-SwitcherLog ("remove {0} failed: {1}" -f $req.Profile, $_.Exception.Message)
                Send-SwitcherState $Conns
                Send-SwitcherToast -Conns $Conns -Level 'error' -Code 'remove-failed' -Detail $req.Profile
                return
            }
            Write-SwitcherLog ("removed profile {0}" -f $req.Profile)
            Send-SwitcherState $Conns
            Send-SwitcherToast -Conns $Conns -Level 'success' -Code 'removed' -Detail $req.Profile
        }
        'accounts' {
            $app = Join-Path $script:HostRoot 'Show-CodexAccountApp.ps1'
            if (-not (Test-Path -LiteralPath $app)) { $app = Join-Path $ParallelRoot 'Show-CodexAccountApp.ps1' }
            if (Test-Path -LiteralPath $app) {
                Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @(
                    '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $app
                ) | Out-Null
            }
        }
    }
}

function Receive-CdpMessage($Conn) {
    <#
    .SYNOPSIS
      Consume the finished receive task. Returns the decoded text when a whole
      message arrived, '' when more frames are needed, $null when closed.
    #>
    $result = $Conn.Task.Result
    if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) { return $null }
    $Conn.Stream.Write($Conn.Buffer, 0, $result.Count)
    if (-not $result.EndOfMessage) {
        Start-CdpReceive $Conn
        return ''
    }
    $text = [Text.Encoding]::UTF8.GetString($Conn.Stream.ToArray())
    $Conn.Stream.SetLength(0)
    Start-CdpReceive $Conn
    return $text
}

function Invoke-CodexSwitcherHost {
    if ($Port -lt 1) { throw 'CDP port must be a loopback port > 0.' }
    $script:Active = $ProfileKey
    if (-not $script:Active) { $script:Active = Get-CodexActiveProfileKey -ParallelRoot $ParallelRoot }

    $injectPath = Join-Path $script:HostRoot 'switcher-inject.js'
    if (-not (Test-Path -LiteralPath $injectPath)) { throw "Missing $injectPath" }
    $source = Get-Content -LiteralPath $injectPath -Raw -Encoding UTF8
    $binding = Get-CodexSwitcherBindingName
    if ($source -notlike "*$binding*") { throw 'switcher-inject.js does not use the expected binding name.' }

    $conns = New-Object System.Collections.ArrayList
    $attachDeadline = (Get-Date).AddSeconds($AttachTimeoutSec)
    $lastDiscover = [datetime]::MinValue
    $lastState = Get-Date
    $cloneGoneSince = $null
    Write-SwitcherLog ("host start port={0} active={1}" -f $Port, $script:Active)

    while ($true) {
        $now = Get-Date
        $discoverEvery = 3
        if ($conns.Count -eq 0) { $discoverEvery = 1 }
        if (($now - $lastDiscover).TotalSeconds -ge $discoverEvery) {
            $lastDiscover = $now
            $targets = @()
            try { $targets = @(Get-CdpTargets -CdpPort $Port) } catch { $targets = @() }
            $fresh = @($targets | Where-Object { $id = [string]$_.id; -not (@($conns | Where-Object { $_.TargetId -eq $id }).Count) })
            if ($fresh.Count -gt 0) {
                if (-not (Test-CodexCdpOwnerIsClone -CdpPort $Port)) {
                    Write-SwitcherLog 'REFUSED: CDP port is not owned by the cloned ChatGPT.exe'
                    throw 'Refusing CDP attach: the port is not owned by the cloned ChatGPT.exe.'
                }
                foreach ($t in $fresh) {
                    try {
                        $c = Connect-CdpTarget -Target $t -Source $source
                        [void]$conns.Add($c)
                        Write-SwitcherLog ("attached target {0}" -f $c.TargetId)
                    }
                    catch {
                        Write-SwitcherLog ("attach failed: " + $_.Exception.Message)
                    }
                }
            }
            if ($conns.Count -eq 0) {
                if (-not (Test-CodexCloneRunning)) {
                    if (-not $cloneGoneSince) { $cloneGoneSince = $now }
                }
                else { $cloneGoneSince = $null }
                if ($now -gt $attachDeadline -and $cloneGoneSince -and ($now - $cloneGoneSince).TotalSeconds -ge 6) { break }
                if ($now -gt $attachDeadline.AddSeconds(120) -and $conns.Count -eq 0) { break }
            }
        }

        if ($conns.Count -eq 0) {
            Start-Sleep -Milliseconds 500
            continue
        }
        $attachDeadline = $now.AddSeconds(15)

        $tasks = [System.Threading.Tasks.Task[]]@($conns | ForEach-Object { $_.Task })
        $idx = [System.Threading.Tasks.Task]::WaitAny($tasks, 1000)
        if ($idx -ge 0) {
            $conn = $conns[$idx]
            $text = $null
            try {
                if ($conn.Task.IsFaulted -or $conn.Task.IsCanceled) { $text = $null }
                else { $text = Receive-CdpMessage $conn }
            }
            catch { $text = $null }
            if ($null -eq $text) {
                Write-SwitcherLog ("target {0} closed" -f $conn.TargetId)
                Close-CdpConn $conn
                $conns.RemoveAt($idx)
                continue
            }
            if ($text) {
                $msg = $null
                try { $msg = $text | ConvertFrom-Json } catch { $msg = $null }
                $method = ''
                if ($msg -and $msg.PSObject.Properties['method']) { $method = [string]$msg.method }
                if ($method -eq 'Runtime.executionContextCreated') {
                    # Fallback re-inject for the main world after a reload (script guards double init).
                    $ctx = $msg.params.context
                    $isDefault = $false
                    if ($ctx -and $ctx.PSObject.Properties['auxData'] -and $ctx.auxData -and $ctx.auxData.PSObject.Properties['isDefault']) {
                        $isDefault = [bool]$ctx.auxData.isDefault
                    }
                    if ($isDefault) {
                        try { Send-CdpMessage -Conn $conn -Method 'Runtime.evaluate' -Params @{ expression = $source; contextId = [int]$ctx.id; returnByValue = $true } } catch { }
                    }
                }
                elseif ($method -eq 'Runtime.bindingCalled' -and [string]$msg.params.name -eq $binding) {
                    try { Invoke-SwitcherRequest -Payload ([string]$msg.params.payload) -Conns @($conns) }
                    catch {
                        Write-SwitcherLog ("request failed: " + $_.Exception.Message)
                        Send-SwitcherToast -Conns @($conns) -Level 'error' -Code 'host-error'
                    }
                }
            }
        }

        if (((Get-Date) - $lastState).TotalSeconds -ge 15) {
            $lastState = Get-Date
            try { Send-SwitcherState @($conns) } catch { }
        }
    }

    foreach ($c in @($conns)) { Close-CdpConn $c }
    Write-SwitcherLog 'host exit (clone closed)'
}

# Dot-sourcing loads the functions only (local harnesses); running the file starts the host.
if ($MyInvocation.InvocationName -ne '.') {
    try {
        if (Test-CodexStoreRunning) {
            Write-SwitcherLog 'REFUSED: Microsoft Store ChatGPT.exe is running; switcher targets the clone only'
            return
        }
        $mutex = New-Object System.Threading.Mutex($false, 'Local\CodexMultiProfileSwitcherHost')
        $owned = $false
        try { $owned = $mutex.WaitOne(0) }
        catch {
            # A killed previous host leaves the mutex abandoned; WaitOne still hands it to us.
            $ex = $_.Exception
            if ($ex -is [System.Threading.AbandonedMutexException] -or $ex.InnerException -is [System.Threading.AbandonedMutexException]) { $owned = $true }
            else { throw }
        }
        if (-not $owned) {
            Write-SwitcherLog 'another switcher host is running; exit'
            return
        }
        try { Invoke-CodexSwitcherHost }
        finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
    }
    catch {
        Write-SwitcherLog ("ERROR: " + $_.Exception.Message)
        exit 1
    }
}
