#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scripts = Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -Filter '*.ps1' -File
$failed = @()

foreach ($file in $scripts) {
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

$testFile = $MyInvocation.MyCommand.Path
$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($testFile, [ref]$tokens, [ref]$errors)
if ($errors -and $errors.Count -gt 0) {
    $failed += [pscustomobject]@{ File = 'Invoke-ParseCheck.ps1'; Error = ($errors | ForEach-Object { $_.ToString() }) -join '; ' }
}

if ($failed.Count -gt 0) {
    $failed | Format-Table -AutoSize | Out-String | Write-Output
    throw "Parse failed for $($failed.Count) file(s)."
}

Write-Output "OK: parsed $($scripts.Count) scripts with 0 errors."
