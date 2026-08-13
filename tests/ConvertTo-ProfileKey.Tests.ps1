#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$module = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\CodexMultiProfile.psm1'
Import-Module $module -Force

$cases = @(
    @{ In = 'codex1'; Out = 'codex1' }
    @{ In = 'Codex 2'; Out = 'codex-2' }
    @{ In = '  My.Profile  '; Out = 'my-profile' }
)
foreach ($c in $cases) {
    $got = ConvertTo-ProfileKey -ProfileName $c.In
    if ($got -ne $c.Out) { throw "ConvertTo-ProfileKey '$($c.In)' => '$got', expected '$($c.Out)'" }
}
$threw = $false
try { ConvertTo-ProfileKey -ProfileName '!!!' } catch { $threw = $true }
if (-not $threw) { throw 'ConvertTo-ProfileKey should reject empty keys' }
Write-Output 'OK: ConvertTo-ProfileKey cases passed.'
