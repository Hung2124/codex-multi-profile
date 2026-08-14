# Recipe cards

Copy-paste commands after install. All paths assume the default install root.

```powershell
$root = "$env:LOCALAPPDATA\CodexParallelDesktop"
```

## First secondary login

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\Launch-CodexProfile.ps1" -Name codex1 -BootstrapLogin
# Sign in with the SECONDARY ChatGPT account, then close the window.
```

## Daily switch

```powershell
# Secondary
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\Launch-CodexProfile.ps1" -Name codex1

# Back to main Store Codex
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\Launch-CodexMain.ps1"
```

## Health check before filing a bug

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action doctor
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action processes
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\Redact-LaunchTrace.ps1"
```

## Machine-readable status

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action status -AsJson
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action doctor -AsJson
```

## Create another profile

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action new -Name codex2
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\Launch-CodexProfile.ps1" -Name codex2
```

## Delete a profile (never deletes ~/.codex)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action remove -Name codex2 -Force
```
