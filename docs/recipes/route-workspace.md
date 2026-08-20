# Recipe: route this repo to a profile

Humans: pick the account in **Codex Accounts**. This page is the agent/script path.

From the project folder:

```powershell
$m = "$env:LOCALAPPDATA\CodexParallelDesktop\CodexProfile.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File $m -Action stick -Name codex1
powershell -NoProfile -ExecutionPolicy Bypass -File $m -Action route
```

Close any open Codex window first (AuthSwap is one window).

See the pool:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File $m -Action pool
```

If that account is out of allowance:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File $m -Action depleted -Name codex1
powershell -NoProfile -ExecutionPolicy Bypass -File $m -Action route
```
