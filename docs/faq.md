# FAQ

## Can I run Store Codex and Codex1 at the same time?

No. AuthSwap owns `~\.codex\auth.json` for one process. Close one, then open the other. Use **Codex Main** to restore the original account.

## Why not a second `CODEX_HOME`?

The Desktop app-server often ignores it and still reads `~\.codex\auth.json`. You get the main account in a second window.

## Does this upload my ChatGPT token?

No. Files stay on disk under `%LOCALAPPDATA%\CodexParallelDesktop\profiles\` and `~\.codex`. Do not commit `auth.json` or `launch-trace.log`.

## `status` shows `al***@example.com`. Is that my real address?

Only the first characters plus the domain. Full addresses are never printed by `status` / `list`.

## How do I update?

```powershell
git pull
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-CodexMultiProfile.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexParallelDesktop\CodexProfile.ps1" -Action verify
```

## How do I check the install?

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexParallelDesktop\CodexProfile.ps1" -Action status
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexParallelDesktop\CodexProfile.ps1" -Action verify
```
