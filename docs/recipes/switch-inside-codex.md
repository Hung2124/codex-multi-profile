# Recipe: switch accounts inside Codex

Turn it on once:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexParallelDesktop\CodexProfile.ps1" -Action switcher
```

(or click **Trong Codex** in Codex Accounts).

Open a profile. In the Codex window:

1. Click your avatar (bottom-left) or press `Ctrl+Alt+A`.
2. Under **Accounts**, click the account you want (or press its digit).
3. Codex reopens on that login in a few seconds. Chats and projects are unchanged.

**Add account** adds a new row (sign in once from the toast or by clicking it). Hover a row and click the trash icon to remove it.
Out of quota? Accept the **Switch to …** card Codex shows after a usage-limit message.

Turn it off: `-Action switcher -Disable`. Details: [in-app-switcher.md](../in-app-switcher.md).
