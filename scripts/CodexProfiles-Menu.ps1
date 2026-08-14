#Requires -Version 5.1
# Tiny picker for installed Codex profiles (AuthSwap).
Add-Type -AssemblyName Microsoft.VisualBasic
Add-Type -AssemblyName System.Windows.Forms

$root = Join-Path $env:LOCALAPPDATA 'CodexParallelDesktop'
$script = Join-Path $root 'CodexProfile.ps1'
if (-not (Test-Path -LiteralPath $script)) {
    [System.Windows.Forms.MessageBox]::Show("Missing CodexProfile.ps1 in $root", 'Codex Profiles', 'OK', 'Error') | Out-Null
    exit 1
}

$choice = [Microsoft.VisualBasic.Interaction]::InputBox(
    @"
Enter a number or name:

1 / codex1 = launch secondary profile
main = restore main account (Store Codex)
list = list profiles
status / doctor / verify / processes / repair / sync-check / diagnostics = tools
or type a new profile name to create + launch
"@, 'Codex Profiles', '1')

if ([string]::IsNullOrWhiteSpace($choice)) { exit 0 }
$choice = $choice.Trim()

function Invoke-Profile([string]$Action, [string]$Name) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Action $Action -Name $Name
}

switch -Regex ($choice) {
    '^(?i)list$' { Invoke-Profile -Action list -Name '_' }
    '^(?i)status|verify|doctor|processes|repair|sync-check|diagnostics$' {
        Invoke-Profile -Action $choice.ToLowerInvariant() -Name '_'
    }
    '^(?i)main|goc|home$' {
        $main = Join-Path $root 'Launch-CodexMain.ps1'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $main
    }
    '^(?i)1$|^codex1$' { Invoke-Profile -Action launch -Name 'codex1' }
    default {
        $name = $choice.ToLowerInvariant()
        if ($name -notmatch '^[a-z0-9][a-z0-9\-]*$') {
            [System.Windows.Forms.MessageBox]::Show("Invalid name: $choice", 'Codex Profiles', 'OK', 'Error') | Out-Null
            exit 1
        }
        Invoke-Profile -Action new -Name $name
        Invoke-Profile -Action launch -Name $name
    }
}
