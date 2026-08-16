#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$module = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\CodexMultiProfile.psm1'
Import-Module $module -Force

$tmp = Join-Path $env:TEMP ('cmp-version-sort-' + [guid]::NewGuid().ToString('n'))
$older = Join-Path $tmp 'versions\1.2026.9.0\app'
$newer = Join-Path $tmp 'versions\1.2026.10.0\app'
New-Item -ItemType Directory -Force -Path $older, $newer | Out-Null
New-Item -ItemType File -Force -Path `
    (Join-Path $older 'ChatGPT.exe'), `
    (Join-Path $newer 'ChatGPT.exe') | Out-Null

try {
    $exe = Get-CodexCloneExe -ParallelRoot $tmp
    $expected = Join-Path $newer 'ChatGPT.exe'
    $exeFull = [System.IO.Path]::GetFullPath($exe)
    $expectedFull = [System.IO.Path]::GetFullPath($expected)
    if ($exeFull -ne $expectedFull) {
        throw "Expected newest clone $expectedFull but got $exeFull"
    }
}
finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'OK: Get-CodexCloneExe picks the highest semantic version.'
