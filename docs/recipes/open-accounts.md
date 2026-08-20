# Recipe: open Codex Accounts

The product UI is the **Codex Accounts** Desktop shortcut. After install:

```powershell
powershell -NoProfile -STA -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexParallelDesktop\Show-CodexAccountApp.ps1"
```

Or:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexParallelDesktop\CodexProfile.ps1" -Action accounts
```

Click a row to switch now. An open Codex window is closed first. Saved `auth.json` does not ask for a password.

**Add profile** creates a folder + shortcut. First-run sign-in still happens inside Codex.

Agents should keep using `pool` / `stick` / `route` / `depleted` — see [router.md](../router.md).
