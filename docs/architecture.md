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

## Watcher

`CodexAccountsWatcher.exe` (compiled at install from `scripts/CodexAccountsWatcher.cs`, started at sign-in from
HKCU `Run`): every 1.5 s it lists `ChatGPT.exe` processes; when the Store Codex runs and the helper's mutex
(`Local\CodexMultiProfileHost`) is free it starts the helper, which reopens Codex with the DevTools port if needed.
~25 MB, near-zero CPU. It exits by itself once the install folder is gone. A helper that ends within a minute
while Codex runs makes it wait longer before the next try (20 s doubling up to 10 min), and the helper reopens
Codex for the port at most once per 10 minutes unless the last reopen worked: never a restart loop.

## Usage bars

The helper asks `https://chatgpt.com/backend-api/wham/usage` for every saved account with that account's own access
token (the endpoint Codex itself uses), without blocking: one shared `HttpClient`, tasks checked in the main loop.
When the menu opens (at most once a minute per account) and every 10 minutes. The page gets label / percent used /
reset time only. A limit reached counts as out of quota; a login the server rejects shows no bar.

## Accounts

- `%LOCALAPPDATA%\CodexMultiProfile\accounts\<name>\auth.json`: one saved copy of `~\.codex\auth.json` per account,
  identified by the id_token email + ChatGPT account id (same email in two workspaces = two accounts).
- `accounts.json`: last used / out-of-quota flags. `settings.json` (optional): `cdpPort`, `lang`.
- **Sync.** Codex refreshes and rotates its tokens in `auth.json`. The helper copies the live file back into the account
  in use whenever it changes, and once more right before a switch. A saved copy that fell behind would stop working.
- **Switch (fast, 2-3 s).** The login lives in the `codex.exe app-server` child, not in the window. End only the
  app-server → sync the outgoing account → copy the chosen `auth.json` in place (write + rename) → Codex starts a new
  app-server by itself and the open window picks the new account up (name, plan, limits) without a reload. If Codex
  was quicker than the copy, that app-server is ended once more. Used when the page reports the normal signed-in UI.
- **Switch (full).** From a sign-in screen, or when no new app-server shows up within 10 s: end Codex and its whole
  process tree (one snapshot, `Stop-Process`, wait until every process is gone) → swap → start Codex. Codex is always
  started again, whatever failed.
- **Add.** Full restart (only a fresh start shows the sign-in screen): sync → remove `~\.codex\auth.json` → start Codex → when a new login appears,
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
- Finds the avatar button by position / `aria-haspopup=menu` / image, and looks again only when it went away or the
  window became visible. If it cannot be found (sign-in screen, a future Codex layout) a same-looking account button
  appears at the bottom-left instead.
- Light on Codex: menus are Radix portals appended to `<body>`, so only `<body>`'s direct children are observed, plus a
  scan right after the avatar is clicked. The usage-limit watcher only queues small new nodes and checks them once a
  second, so streaming replies do not cost anything noticeable.
- Codex sends printable keys typed outside an editable element to its composer; the layer carries
  `data-codex-character-input-boundary` (Codex's own opt-out) so typing in our dialogs stays there.
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
