# Troubleshooting

Start with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexMultiProfile\CodexAccounts.ps1" status
```

Log: `%LOCALAPPDATA%\CodexMultiProfile\codex-accounts.log` (masked, safe to paste after a look).

| Symptom | Try |
|:---|:---|
| No **Accounts** section in the avatar menu | The watcher should fix this within seconds (Codex restarts once). If not: is `CodexAccountsWatcher.exe` running? Re-run the installer, or open Codex from the **Codex** shortcut |
| "The account helper is not running" in the menu | The helper exited. Open Codex again from the **Codex** shortcut (it attaches without restarting Codex) |
| After switching, Codex shows its sign-in screen | That account's saved login expired. Sign in with the same account; it is saved automatically. Or use the account button at the bottom-left to go back |
| "That login is already saved as ..." after Add account | You signed in with an account that is already in the list; nothing was added |
| The switch card stays for more than ~25 s | See the log: `restart:` lines show how long closing and reopening took. Open Codex from the shortcut again |
| Port 9333 is used by something else | `settings.json` in the install folder: `{ "cdpPort": 9444 }`, then reopen Codex from the shortcut |
| Menu language | `CodexAccounts.ps1 lang -Name vi` (or `en`, `auto` = follow Codex) |

Never paste `auth.json` or anything from the `accounts` folder into an issue.
