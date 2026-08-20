#Requires -Version 5.1
<#
.SYNOPSIS
  Windows subscription router for Codex Multi-Profile (AuthSwap, one window).

  Spirit of b-nnett/codex-subscription-router without a mux or ChatGPT.exe patch:
  sticky workspace -> profile; new work -> least-recently-used non-depleted profile;
  depleted owner fails over; all depleted prints one combined message.

  Does not bypass quotas. Users mark their own authorized profiles depleted.
#>
Set-StrictMode -Version Latest

$core = Join-Path $PSScriptRoot 'CodexMultiProfile.psm1'
if (Test-Path -LiteralPath $core) {
    Import-Module $core -Force
}

function ConvertTo-PlainHashtable {
    param($InputObject)
    $h = @{}
    if ($null -eq $InputObject) { return $h }
    if ($InputObject -is [hashtable]) {
        foreach ($k in @($InputObject.Keys)) { $h[[string]$k] = $InputObject[$k] }
        return $h
    }
    foreach ($p in $InputObject.PSObject.Properties) {
        $h[[string]$p.Name] = $p.Value
    }
    return $h
}

function Get-CodexRouterStatePath {
    param([string]$ParallelRoot = (Get-CodexParallelRoot))
    return (Join-Path $ParallelRoot 'router-state.json')
}

function Get-CodexLayerStatePath {
    param([string]$ParallelRoot = (Get-CodexParallelRoot))
    return (Join-Path $ParallelRoot 'layer-state.json')
}

function New-EmptyRouterState {
    return @{
        version  = 1
        profiles = @{}
        stickies = @{}
    }
}

function Get-CodexRouterState {
    param([string]$ParallelRoot = (Get-CodexParallelRoot))
    $path = Get-CodexRouterStatePath -ParallelRoot $ParallelRoot
    if (-not (Test-Path -LiteralPath $path)) {
        return (New-EmptyRouterState)
    }
    $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return (New-EmptyRouterState)
    }
    $obj = $raw | ConvertFrom-Json
    $state = New-EmptyRouterState
    if ($obj.PSObject.Properties['version']) { $state.version = [int]$obj.version }
    $state.profiles = ConvertTo-PlainHashtable $obj.profiles
    $state.stickies = ConvertTo-PlainHashtable $obj.stickies
    $normalized = @{}
    foreach ($name in @($state.profiles.Keys)) {
        $normalized[[string]$name] = ConvertTo-PlainHashtable $state.profiles[$name]
    }
    $state.profiles = $normalized
    return $state
}

function Save-CodexRouterState {
    param(
        [Parameter(Mandatory)] $State,
        [string]$ParallelRoot = (Get-CodexParallelRoot)
    )
    $path = Get-CodexRouterStatePath -ParallelRoot $ParallelRoot
    $json = ($State | ConvertTo-Json -Depth 8)
    Write-Utf8NoBom -Path $path -Text ($json + "`n")
    return $path
}

function Get-CodexWorkspaceKey {
    <#
    .SYNOPSIS
      Sticky key: git toplevel if present, otherwise the folder path.
    #>
    param([string]$Path = ((Get-Location).Path))
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Workspace path is empty.' }
    $full = [System.IO.Path]::GetFullPath($Path)
    $dir = $full
    if (Test-Path -LiteralPath $full -PathType Leaf) {
        $dir = Split-Path -Parent $full
    }
    $cursor = $dir
    while ($cursor) {
        $git = Join-Path $cursor '.git'
        if (Test-Path -LiteralPath $git) {
            return $cursor.TrimEnd('\')
        }
        $parent = Split-Path -Parent $cursor
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $cursor) { break }
        $cursor = $parent
    }
    if (Test-Path -LiteralPath $dir -PathType Container) {
        return ([System.IO.Path]::GetFullPath($dir)).TrimEnd('\')
    }
    return $full.TrimEnd('\')
}

function Get-CodexKnownProfileNames {
    param([string]$ParallelRoot = (Get-CodexParallelRoot))
    $root = Join-Path $ParallelRoot 'profiles'
    if (-not (Test-Path -LiteralPath $root)) { return @() }
    return @(Get-ChildItem -LiteralPath $root -Directory | ForEach-Object { $_.Name } | Sort-Object)
}

function Get-CodexProfileMeta {
    param(
        [Parameter(Mandatory)] [string]$Name,
        $State
    )
    $key = ConvertTo-ProfileKey -ProfileName $Name
    if (-not $State) { $State = New-EmptyRouterState }
    $profiles = ConvertTo-PlainHashtable $State.profiles
    if ($profiles.ContainsKey($key)) {
        return (ConvertTo-PlainHashtable $profiles[$key])
    }
    return @{ lastUsedAt = $null; depleted = $false }
}

function Test-CodexProfileDepleted {
    param(
        [Parameter(Mandatory)] [string]$Name,
        $State
    )
    $meta = Get-CodexProfileMeta -Name $Name -State $State
    if ($meta.ContainsKey('depleted')) { return [bool]$meta['depleted'] }
    return $false
}

function Set-CodexProfileLastUsed {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [string]$ParallelRoot = (Get-CodexParallelRoot),
        [datetime]$When = (Get-Date).ToUniversalTime()
    )
    $key = ConvertTo-ProfileKey -ProfileName $Name
    $state = Get-CodexRouterState -ParallelRoot $ParallelRoot
    $meta = Get-CodexProfileMeta -Name $key -State $state
    $meta['lastUsedAt'] = $When.ToUniversalTime().ToString('o')
    if (-not $meta.ContainsKey('depleted')) { $meta['depleted'] = $false }
    $state.profiles[$key] = $meta
    Save-CodexRouterState -State $state -ParallelRoot $ParallelRoot | Out-Null
    return $meta
}

function Set-CodexProfileDepleted {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [string]$ParallelRoot = (Get-CodexParallelRoot),
        [switch]$Clear
    )
    $key = ConvertTo-ProfileKey -ProfileName $Name
    $known = @(Get-CodexKnownProfileNames -ParallelRoot $ParallelRoot)
    if ($known.Count -gt 0 -and $known -notcontains $key) {
        throw "Unknown profile '$key'. Create it first: -Action new -Name $key"
    }
    $state = Get-CodexRouterState -ParallelRoot $ParallelRoot
    $meta = Get-CodexProfileMeta -Name $key -State $state
    $meta['depleted'] = (-not $Clear)
    if ($Clear) { $meta['depletedAt'] = $null }
    else { $meta['depletedAt'] = (Get-Date).ToUniversalTime().ToString('o') }
    $state.profiles[$key] = $meta
    Save-CodexRouterState -State $state -ParallelRoot $ParallelRoot | Out-Null
    return [pscustomobject]@{
        Name     = $key
        Depleted = [bool]$meta['depleted']
    }
}

function Set-CodexProfileSticky {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [string]$Workspace = ((Get-Location).Path),
        [string]$ParallelRoot = (Get-CodexParallelRoot)
    )
    $key = ConvertTo-ProfileKey -ProfileName $Name
    $known = @(Get-CodexKnownProfileNames -ParallelRoot $ParallelRoot)
    if ($known.Count -gt 0 -and $known -notcontains $key) {
        throw "Unknown profile '$key'. Create it first: -Action new -Name $key"
    }
    $ws = Get-CodexWorkspaceKey -Path $Workspace
    $state = Get-CodexRouterState -ParallelRoot $ParallelRoot
    $state.stickies[$ws] = $key
    Save-CodexRouterState -State $state -ParallelRoot $ParallelRoot | Out-Null
    return [pscustomobject]@{
        Workspace = $ws
        Profile   = $key
    }
}

function Clear-CodexProfileSticky {
    param(
        [string]$Workspace = ((Get-Location).Path),
        [string]$ParallelRoot = (Get-CodexParallelRoot)
    )
    $ws = Get-CodexWorkspaceKey -Path $Workspace
    $state = Get-CodexRouterState -ParallelRoot $ParallelRoot
    if ($state.stickies.ContainsKey($ws)) {
        $state.stickies.Remove($ws)
        Save-CodexRouterState -State $state -ParallelRoot $ParallelRoot | Out-Null
        return [pscustomobject]@{ Workspace = $ws; Cleared = $true }
    }
    return [pscustomobject]@{ Workspace = $ws; Cleared = $false }
}

function Get-CodexStickyProfile {
    param(
        [string]$Workspace = ((Get-Location).Path),
        $State
    )
    $ws = Get-CodexWorkspaceKey -Path $Workspace
    if (-not $State) { return $null }
    $stickies = ConvertTo-PlainHashtable $State.stickies
    if ($stickies.ContainsKey($ws)) { return [string]$stickies[$ws] }
    return $null
}

function Select-CodexLeastRecentlyUsed {
    param(
        [Parameter(Mandatory)] [string[]]$Names,
        $State
    )
    $rows = foreach ($name in $Names) {
        $meta = Get-CodexProfileMeta -Name $name -State $State
        $last = [datetime]::MinValue
        if ($meta.ContainsKey('lastUsedAt') -and $meta['lastUsedAt']) {
            try { $last = [datetime]$meta['lastUsedAt'] } catch { $last = [datetime]::MinValue }
        }
        [pscustomobject]@{ Name = $name; LastUsed = $last }
    }
    $pick = @($rows | Sort-Object LastUsed, Name | Select-Object -First 1)
    if ($pick.Count -eq 0) { return $null }
    return [string]$pick[0].Name
}

function Resolve-CodexRoute {
    <#
    .SYNOPSIS
      Pick a profile: sticky workspace owner unless depleted, else LRU of the rest.
    #>
    param(
        [string]$Workspace = ((Get-Location).Path),
        [string]$ParallelRoot = (Get-CodexParallelRoot),
        [string]$SourceHome = (Join-Path $env:USERPROFILE '.codex')
    )
    $ws = Get-CodexWorkspaceKey -Path $Workspace
    $state = Get-CodexRouterState -ParallelRoot $ParallelRoot
    $names = @(Get-CodexKnownProfileNames -ParallelRoot $ParallelRoot)
    if ($names.Count -eq 0) {
        return [pscustomobject]@{
            Profile             = $null
            Reason              = 'no-profiles'
            Workspace           = $ws
            Failover            = $false
            DepletedOwner       = $null
            BlockedByOpenWindow = $false
            Message             = 'No profiles yet. Create one: -Action new -Name codex1'
        }
    }

    $available = @($names | Where-Object { -not (Test-CodexProfileDepleted -Name $_ -State $state) })
    $sticky = Get-CodexStickyProfile -Workspace $ws -State $state
    $reason = 'lru'
    $failover = $false
    $depletedOwner = $null
    $pick = $null

    if ($sticky -and ($names -contains $sticky) -and -not (Test-CodexProfileDepleted -Name $sticky -State $state)) {
        $pick = $sticky
        $reason = 'sticky'
    }
    elseif ($sticky -and ($names -contains $sticky) -and (Test-CodexProfileDepleted -Name $sticky -State $state)) {
        $depletedOwner = $sticky
        $failover = $true
        if ($available.Count -gt 0) {
            $pick = Select-CodexLeastRecentlyUsed -Names $available -State $state
            $reason = 'failover'
        }
        else {
            $reason = 'all-depleted'
        }
    }
    elseif ($available.Count -gt 0) {
        $pick = Select-CodexLeastRecentlyUsed -Names $available -State $state
        $reason = 'lru'
    }
    else {
        $reason = 'all-depleted'
    }

    $cloneOpen = $false
    try {
        $running = @(Get-CodexRunningProcesses -ParallelRoot $ParallelRoot | Where-Object { $_.Kind -eq 'clone' -or $_.Kind -eq 'store' })
        $cloneOpen = ($running.Count -gt 0)
    }
    catch {
        $cloneOpen = $false
    }

    $message = $null
    if ($reason -eq 'all-depleted') {
        $rows = @(Get-CodexProfilePool -ParallelRoot $ParallelRoot -SourceHome $SourceHome)
        $lines = @(
            'All profiles in the pool are marked depleted.'
            'This helper does not bypass quotas. Clear a profile when your own allowance resets:'
            '  CodexProfile.ps1 -Action depleted -Name <profile> -Disable'
        )
        foreach ($row in $rows) {
            $lines += ('  {0}  {1}  depleted={2}' -f $row.Name, $row.Account, $row.Depleted)
        }
        $message = $lines -join [Environment]::NewLine
    }
    elseif ($pick -and $cloneOpen) {
        $message = "A Codex window is already open (AuthSwap is one window). Would route to '$pick' (reason=$reason). Close it, then re-run route."
    }
    elseif ($reason -eq 'failover') {
        $message = "Sticky owner '$depletedOwner' is depleted; failing over to '$pick'."
    }
    elseif ($reason -eq 'sticky') {
        $message = "Sticky workspace -> '$pick'."
    }
    else {
        $message = "Least-recently-used non-depleted profile -> '$pick'."
    }

    return [pscustomobject]@{
        Profile             = $pick
        Reason              = $reason
        Workspace           = $ws
        Failover            = $failover
        DepletedOwner       = $depletedOwner
        BlockedByOpenWindow = $cloneOpen
        Message             = $message
    }
}

function Get-CodexProfilePool {
    param(
        [string]$ParallelRoot = (Get-CodexParallelRoot),
        [string]$SourceHome = (Join-Path $env:USERPROFILE '.codex')
    )
    $state = Get-CodexRouterState -ParallelRoot $ParallelRoot
    $names = @(Get-CodexKnownProfileNames -ParallelRoot $ParallelRoot)
    $stickies = ConvertTo-PlainHashtable $state.stickies
    $rows = foreach ($name in $names) {
        $email = Get-AuthEmailFromFile -Path (Join-Path $ParallelRoot "profiles\$name\auth.json")
        $meta = Get-CodexProfileMeta -Name $name -State $state
        $last = $null
        if ($meta.ContainsKey('lastUsedAt')) { $last = $meta['lastUsedAt'] }
        $bound = @($stickies.GetEnumerator() | Where-Object { [string]$_.Value -eq $name } | ForEach-Object { $_.Key })
        [pscustomobject]@{
            Name      = $name
            Account   = Hide-AuthEmail -Email $email
            LastUsed  = $last
            Depleted  = (Test-CodexProfileDepleted -Name $name -State $state)
            Stickies  = $bound
        }
    }
    return @($rows)
}

function Get-CodexLayerState {
    param([string]$ParallelRoot = (Get-CodexParallelRoot))
    $path = Get-CodexLayerStatePath -ParallelRoot $ParallelRoot
    $state = @{
        enabled = $false
        cdpPort = 9222
        note    = 'CDP loopback into the cloned ChatGPT.exe only. Store app is never targeted.'
    }
    if (Test-Path -LiteralPath $path) {
        $obj = (Get-Content -LiteralPath $path -Raw -Encoding UTF8) | ConvertFrom-Json
        if ($obj.PSObject.Properties['enabled']) { $state.enabled = [bool]$obj.enabled }
        if ($obj.PSObject.Properties['cdpPort']) { $state.cdpPort = [int]$obj.cdpPort }
    }
    return [pscustomobject]@{
        Enabled = [bool]$state.enabled
        CdpPort = [int]$state.cdpPort
        Note    = [string]$state.note
    }
}

function Set-CodexLayerEnabled {
    param(
        [string]$ParallelRoot = (Get-CodexParallelRoot),
        [switch]$Disable,
        [int]$CdpPort = 9222
    )
    if ($CdpPort -lt 1) { $CdpPort = 9222 }
    $state = @{
        enabled = (-not $Disable)
        cdpPort = $CdpPort
        note    = 'CDP 127.0.0.1 only. Never the Microsoft Store package.'
    }
    $path = Get-CodexLayerStatePath -ParallelRoot $ParallelRoot
    Write-Utf8NoBom -Path $path -Text (($state | ConvertTo-Json -Depth 4) + "`n")
    return (Get-CodexLayerState -ParallelRoot $ParallelRoot)
}

function Get-CodexChatGptWebModelIds {
    return @(
        'chatgpt-web/luna',
        'chatgpt-web/light',
        'chatgpt-web/medium',
        'chatgpt-web/high',
        'chatgpt-web/xhigh',
        'chatgpt-web/pro'
    )
}

function Get-CodexChatGptWebModelsBlock {
    param([string]$BridgeUrl = 'http://127.0.0.1:1455/v1')
    $ids = Get-CodexChatGptWebModelIds
    $profiles = foreach ($id in $ids) {
        $slug = ($id -replace 'chatgpt-web/', 'chatgpt-web-')
        @(
            "[profiles.$slug]"
            "model = `"$id`""
            'model_provider = "chatgpt-web"'
            ''
        ) -join "`n"
    }
    $body = @(
        '# BEGIN CODEX-MULTI-PROFILE CHATGPT-WEB'
        '# Opt-in aliases for a local ChatGPT Web bridge (e.g. miuuyy/codex-chatgpt-web).'
        '# This repo does not log you into chatgpt.com. Start that launcher separately.'
        ''
        '[model_providers.chatgpt-web]'
        'name = "ChatGPT Web"'
        "base_url = `"$BridgeUrl`""
        'wire_api = "responses"'
        'requires_openai_auth = false'
        ''
        ($profiles -join "`n")
        '# END CODEX-MULTI-PROFILE CHATGPT-WEB'
        ''
    ) -join "`n"
    return $body
}

function Update-CodexChatGptWebModels {
    param(
        [string]$ConfigPath = (Join-Path $env:USERPROFILE '.codex\config.toml'),
        [string]$BridgeUrl = 'http://127.0.0.1:1455/v1',
        [switch]$Disable
    )
    $begin = '# BEGIN CODEX-MULTI-PROFILE CHATGPT-WEB'
    $end = '# END CODEX-MULTI-PROFILE CHATGPT-WEB'
    $existing = ''
    if (Test-Path -LiteralPath $ConfigPath) {
        $existing = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8
        if ($existing.Length -ge 1 -and [int][char]$existing[0] -eq 0xFEFF) {
            $existing = $existing.Substring(1)
        }
    }
    $pattern = '(?s)# BEGIN CODEX-MULTI-PROFILE CHATGPT-WEB.*?# END CODEX-MULTI-PROFILE CHATGPT-WEB\r?\n?'
    $stripped = [regex]::Replace($existing, $pattern, '')
    $stripped = $stripped.TrimEnd()
    if ($Disable) {
        $text = if ($stripped) { $stripped + "`n" } else { '' }
        if ($text) { Write-Utf8NoBom -Path $ConfigPath -Text $text }
        elseif (Test-Path -LiteralPath $ConfigPath) { Write-Utf8NoBom -Path $ConfigPath -Text '' }
        return [pscustomobject]@{
            Path     = $ConfigPath
            Enabled  = $false
            Models   = @()
            BridgeUrl = $BridgeUrl
        }
    }
    $block = Get-CodexChatGptWebModelsBlock -BridgeUrl $BridgeUrl
    if ($stripped) { $text = $stripped + "`n`n" + $block }
    else { $text = $block }
    Write-Utf8NoBom -Path $ConfigPath -Text $text
    return [pscustomobject]@{
        Path      = $ConfigPath
        Enabled   = $true
        Models    = @(Get-CodexChatGptWebModelIds)
        BridgeUrl = $BridgeUrl
    }
}

function Test-CodexChatGptWebModelsEnabled {
    param([string]$ConfigPath = (Join-Path $env:USERPROFILE '.codex\config.toml'))
    if (-not (Test-Path -LiteralPath $ConfigPath)) { return $false }
    $raw = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8
    return ($raw -match 'BEGIN CODEX-MULTI-PROFILE CHATGPT-WEB')
}

Export-ModuleMember -Function @(
    'Get-CodexRouterStatePath',
    'Get-CodexRouterState',
    'Save-CodexRouterState',
    'Get-CodexWorkspaceKey',
    'Get-CodexKnownProfileNames',
    'Get-CodexProfileMeta',
    'Test-CodexProfileDepleted',
    'Set-CodexProfileLastUsed',
    'Set-CodexProfileDepleted',
    'Set-CodexProfileSticky',
    'Clear-CodexProfileSticky',
    'Get-CodexStickyProfile',
    'Select-CodexLeastRecentlyUsed',
    'Resolve-CodexRoute',
    'Get-CodexProfilePool',
    'Get-CodexLayerState',
    'Set-CodexLayerEnabled',
    'Get-CodexChatGptWebModelIds',
    'Get-CodexChatGptWebModelsBlock',
    'Update-CodexChatGptWebModels',
    'Test-CodexChatGptWebModelsEnabled'
)
