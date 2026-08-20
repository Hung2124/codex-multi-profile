# FAQ

## How do I pick an account in a window?

Open the Desktop shortcut **Codex Accounts** (or `Show-CodexAccountApp.ps1`). Click a row or press Enter. That is the product UI. `route` stays for agents.

## Can I run Store Codex and Codex1 at the same time?

No. AuthSwap owns `~\.codex\auth.json` for one process. Close one, then open the other. Use **Codex Main** to restore the original account.

## Why not a second `CODEX_HOME`?

The Desktop app-server often ignores it and still reads `~\.codex\auth.json`. You get the main account in a second window.

## Does this upload my ChatGPT token?

No. Files stay on disk under `%LOCALAPPDATA%\CodexParallelDesktop\profiles\` and `~\.codex`. Do not commit `auth.json` or `launch-trace.log`.

## `status` shows `al***@example.com`. Is that my real address?

Only the first characters plus the domain. Full addresses are never printed by `status` / `list`.

## How do I update?

From a git clone:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Update-CodexMultiProfile.ps1
```

That pulls `main` (fast-forward only) and re-runs the installer, then `verify`.

## How do I delete a secondary profile?

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexParallelDesktop\CodexProfile.ps1" -Action remove -Name codex2 -Force
```

`-Force` is required. `~\.codex` is never deleted.

## How do I get machine-readable status?

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexParallelDesktop\CodexProfile.ps1" -Action status -AsJson
```

Emails in that JSON are already masked.

## How do I clear a stale AuthSwap lock?

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexParallelDesktop\CodexProfile.ps1" -Action repair
```

Close every Codex window first. See [recipes/clear-stale-lock.md](recipes/clear-stale-lock.md).

## How do I check the install?

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexParallelDesktop\CodexProfile.ps1" -Action status
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexParallelDesktop\CodexProfile.ps1" -Action doctor
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexParallelDesktop\CodexProfile.ps1" -Action sync-check
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexParallelDesktop\CodexProfile.ps1" -Action verify
```

## How do I make a safe bug-report log?

Prefer a full bundle:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexParallelDesktop\CodexProfile.ps1" -Action diagnostics
```

Or redact only the launch log:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexParallelDesktop\Redact-LaunchTrace.ps1"
```

Paste the redacted files, not `auth.json`.

## How do I pick a profile for this repo (router)?

Prefer **Codex Accounts** for a human. For a script:


```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexParallelDesktop\CodexProfile.ps1" -Action pool
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexParallelDesktop\CodexProfile.ps1" -Action stick -Name codex1
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexParallelDesktop\CodexProfile.ps1" -Action route
```

Close any open Codex window first. See [router.md](router.md).

## Does route open two Codex windows?

No. AuthSwap is one `~/.codex/auth.json`. If a window is already open, `route` prints the choice and stops.

## Is this a quota bypass?

No. You mark **your** profile `depleted`. The router only chooses among accounts you already set up.
