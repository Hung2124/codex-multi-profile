#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

function ConvertTo-ProfileKey([string]$ProfileName) {
    $key = $ProfileName.Trim().ToLowerInvariant()
    $key = [regex]::Replace($key, '[^a-z0-9]+', '-')
    $key = $key.Trim('-')
    if (-not $key) { throw "Invalid profile name: $ProfileName" }
    return $key
}

$cases = @(
    @{ In = 'codex1'; Out = 'codex1' }
    @{ In = 'Codex 2'; Out = 'codex-2' }
    @{ In = '  My.Profile  '; Out = 'my-profile' }
)

foreach ($c in $cases) {
    $got = ConvertTo-ProfileKey $c.In
    if ($got -ne $c.Out) { throw "ConvertTo-ProfileKey '$($c.In)' => '$got', expected '$($c.Out)'" }
}

$threw = $false
try { ConvertTo-ProfileKey '!!!' } catch { $threw = $true }
if (-not $threw) { throw 'ConvertTo-ProfileKey should reject empty keys' }

Write-Output 'OK: ConvertTo-ProfileKey cases passed.'
