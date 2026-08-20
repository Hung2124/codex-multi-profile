#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$failed = @()

$files = @()
$files += Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -File -Recurse | Where-Object { $_.Extension -in '.ps1', '.psm1' }
$files += Get-ChildItem -LiteralPath (Join-Path $root 'tests') -Filter '*.ps1' -File
$files += Get-Item -LiteralPath (Join-Path $root 'install.ps1') -ErrorAction SilentlyContinue

foreach ($file in $files) {
    if (-not $file) { continue }
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        $failed += [pscustomobject]@{
            File  = $file.Name
            Error = ($errors | ForEach-Object { $_.ToString() }) -join '; '
        }
    }
}

if ($failed.Count -gt 0) {
    $failed | Format-List | Out-String | Write-Output
    throw "Parse failed for $($failed.Count) file(s)."
}

Write-Output "OK: parsed $($files.Count) files with 0 errors."
