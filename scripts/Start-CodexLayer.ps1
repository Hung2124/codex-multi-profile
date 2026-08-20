#Requires -Version 5.1
<#
.SYNOPSIS
  Attach Chrome DevTools Protocol to the cloned ChatGPT.exe on 127.0.0.1 and inject layer-inject.js.

  Off unless layer-state.json has enabled=true. Never targets WindowsApps / Store ChatGPT.
#>
[CmdletBinding()]
param(
    [int]$Port = 9222,
    [int]$TimeoutSec = 30,
    [string]$ParallelRoot = (Join-Path $env:LOCALAPPDATA 'CodexParallelDesktop')
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'CodexMultiProfile.psm1'
if (Test-Path -LiteralPath $modulePath) { Import-Module $modulePath -Force }

function Test-CloneOnlyTarget {
    $items = @(Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'" -ErrorAction SilentlyContinue)
    foreach ($p in $items) {
        $path = [string]$p.ExecutablePath
        if ($path -like '*WindowsApps*') {
            throw 'Refusing CDP attach: a Microsoft Store ChatGPT.exe is running. Layer targets the cloned app only.'
        }
    }
    $clone = @($items | Where-Object {
            ([string]$_.ExecutablePath -like '*CodexParallelDesktop*') -or
            ([string]$_.CommandLine -like '*CodexParallelDesktop*')
        })
    if ($clone.Count -eq 0) {
        throw 'No cloned ChatGPT.exe found. Layer will not attach to the Store app.'
    }
}

function Get-CdpPages([int]$CdpPort) {
    $url = "http://127.0.0.1:$CdpPort/json"
    return @(Invoke-RestMethod -Uri $url -UseBasicParsing -TimeoutSec 3)
}

function Send-CdpEvaluate {
    param(
        [Parameter(Mandatory)] [string]$WsUrl,
        [Parameter(Mandatory)] [string]$Expression
    )
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $cts = New-Object System.Threading.CancellationTokenSource
    $cts.CancelAfter(15000)
    $connect = $ws.ConnectAsync([Uri]$WsUrl, $cts.Token)
    $connect.Wait()
    $id = Get-Random -Minimum 10 -Maximum 99999
    $payload = @{
        id     = $id
        method = 'Runtime.evaluate'
        params = @{ expression = $Expression; returnByValue = $true }
    } | ConvertTo-Json -Depth 6 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($payload)
    $seg = New-Object System.ArraySegment[byte] -ArgumentList @(, $bytes)
    $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).Wait()

    $page = @{
        id     = ($id + 1)
        method = 'Page.addScriptToEvaluateOnNewDocument'
        params = @{ source = $Expression }
    } | ConvertTo-Json -Depth 6 -Compress
    $bytes2 = [Text.Encoding]::UTF8.GetBytes($page)
    $seg2 = New-Object System.ArraySegment[byte] -ArgumentList @(, $bytes2)
    $ws.SendAsync($seg2, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).Wait()
    $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'done', $cts.Token).Wait()
}

if ($Port -lt 1) { throw 'CDP port must be a loopback port > 0.' }

Test-CloneOnlyTarget

$injectPath = Join-Path $PSScriptRoot 'layer-inject.js'
if (-not (Test-Path -LiteralPath $injectPath)) {
    throw "Missing $injectPath"
}
$expression = Get-Content -LiteralPath $injectPath -Raw -Encoding UTF8

$deadline = (Get-Date).AddSeconds($TimeoutSec)
$pages = @()
while ((Get-Date) -lt $deadline) {
    try {
        $pages = @(Get-CdpPages -CdpPort $Port)
        if ($pages.Count -gt 0) { break }
    }
    catch { }
    Start-Sleep -Milliseconds 500
}
if ($pages.Count -eq 0) {
    throw "CDP at http://127.0.0.1:$Port/json did not list pages. Is layer enabled on the clone?"
}

foreach ($page in $pages) {
    $wsUrl = [string]$page.webSocketDebuggerUrl
    if ([string]::IsNullOrWhiteSpace($wsUrl)) { continue }
    if ($wsUrl -notlike 'ws://127.0.0.1*' -and $wsUrl -notlike 'ws://localhost*') {
        throw "Refusing non-loopback CDP websocket: $wsUrl"
    }
    Send-CdpEvaluate -WsUrl $wsUrl -Expression $expression
}

Write-Output "Layer injected on 127.0.0.1:$Port (clone only)."
