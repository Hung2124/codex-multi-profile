# How it works

```
Codex shortcut
  └─ conhost --headless powershell Start-CodexAccounts.ps1        (hidden, one per Windows session)
       ├─ saves the login in ~/.codex/auth.json as an account if it is new
       ├─ starts the Store Codex through IApplicationActivationManager
       │    with --remote-debugging-address=127.0.0.1 --remote-debugging-port=9333
       ├─ CDP on the main window (app://-/index.html only):
       │    Runtime.addBinding('cmpSwitcherBridge') + inject switcher-inject.js (survives reloads)
       ├─ page: when Codex's avatar menu (role=menu) opens, add the Accounts section under the identity row
       ├─ every 3 s: if auth.json or the account store changed -> sync + push masked state to the page
       └─ exits when Codex is closed
```

## Accounts

- `%LOCALAPPDATA%\CodexMultiProfile\accounts\<name>\auth.json`: one saved copy of `~\.codex\auth.json` per account,
  identified by the id_token email + ChatGPT account id (same email in two workspaces = two accounts).
- `accounts.json`: last used / out-of-quota flags. `settings.json` (optional): `cdpPort`, `lang`.
- **Sync.** Codex refreshes and rotates its tokens in `auth.json`. The helper copies the live file back into the account
  in use whenever it changes, and once more right before a switch. A saved copy that fell behind would stop working.
- **Switch.** Close Codex → sync the outgoing account → copy the chosen `auth.json` in place (write + rename) → start Codex.
- **Add.** Close Codex → sync → remove `~\.codex\auth.json` → start Codex (sign-in screen) → when a new login appears,
  save it under the chosen name. A login that is not saved anywhere is never removed, and any new login seen while
  Codex runs is saved automatically.

## Starting the Store Codex

Codex 26.9xx refuses to run without package identity, so it cannot be copied out of `WindowsApps`.
`IApplicationActivationManager.ActivateApplication("OpenAI.Codex_2p2nqsd0c76g0!App", args)` starts it inside its
package and passes the DevTools arguments. Tried and rejected: `Invoke-CommandInDesktopPackage` and `shell:AppsFolder`
leave a hung `ChatGPT.exe` (no window, no port) when called from a normal process.

Before starting again the helper waits until every `ChatGPT.exe` of the package has exited; starting while the old
instance is still exiting hangs on "The application is exiting and cannot service this request".

## Page side (`switcher-inject.js`)

- Closed shadow roots inside Codex's own menu; built with `createElement` only (no HTML strings, Trusted Types and
  CSP safe), no network calls. React keeps rendering its own rows.
- Finds the avatar button by position / `aria-haspopup=menu` / image. If it cannot be found (sign-in screen, a future
  Codex layout) a same-looking account button appears at the bottom-left instead.
- Talks to the helper only through the binding. Messages: `hello`, `refresh`, `switch`, `add`, `cancel-add`, `rename`,
  `remove`, `depleted`. The helper validates each one (`ConvertFrom-CodexSwitcherMessage`): fixed types, names
  `^[a-z0-9][a-z0-9-]{0,63}$` that must exist, 4 KB max.

## Helper cost

No `Runtime.enable`: the binding works without it, and it would stream every Codex console message through PowerShell.
`Page.enable` is kept (a few events per navigation): the new-document script needs it to run again after a reload. Replies are skipped without JSON parsing. Idle cost: ~130 MB, ~1 s CPU per minute.

## Security notes

- The DevTools port is bound to `127.0.0.1`. The helper attaches only when the port belongs to the Store Codex
  `ChatGPT.exe`, and only to `ws://127.0.0.1:<port>/` sockets. Any program running as you can reach the port as well.
- Events sent to the page are checked for unmasked emails and dropped if one slips through.
- Logs (`codex-accounts.log`, rotated at 512 KB) contain account names and masked emails only.
