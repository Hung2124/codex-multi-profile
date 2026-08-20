# Subscription router (Windows)

**Pick accounts in the Codex Accounts app.** The CLI (`pool` / `stick` / `route` / `depleted`) is for agents and scripts.

Windows counterpart of [b-nnett/codex-subscription-router](https://github.com/b-nnett/codex-subscription-router) routing — **without** their Go mux or a ChatGPT.exe / `app.asar` patch.

AuthSwap still owns a **single** `~/.codex/auth.json`. Only one Codex window can be live.

Use only **authorized personal / work accounts you own**. Marking a profile `depleted` is a local flag you set. This is not a quota-bypass product.

## Codex Accounts (the app)

Desktop shortcut **Codex Accounts** after install (`Show-CodexAccountApp.ps1`):

- Rows: profile name, masked email, last-used, depleted badge, sticky paths
- Click / Enter → `Launch-CodexProfile.ps1` (AuthSwap)
- If a Codex window is already open → close the clone, then AuthSwap-launch the chosen saved login (no password prompt)
- **Add profile**, **Open Main**, **Mark depleted / clear**, **Refresh**
- First-run login is still AuthSwap bootstrap inside Codex. This app does not implement chatgpt.com / device-code login

```powershell
powershell -NoProfile -STA -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexParallelDesktop\Show-CodexAccountApp.ps1"
```

Headless (tests / agents, no window): `-Headless`.

## One-command install

```powershell
irm https://raw.githubusercontent.com/Hung2124/codex-multi-profile/main/install.ps1 | iex
```

Same idea as their `curl | bash`: download + install. Then **Codex Accounts** and `CodexProfile.ps1` actions are on this machine.

## Routing table

| Situation | Behaviour here |
|:---|:---|
| New chat / new folder | Least-recently-used **non-depleted** profile (never-used first; name breaks ties) |
| Follow-up in the same git repo or workspace | Sticky owner for that path |
| Sticky owner marked depleted | Fail over to LRU of the remaining non-depleted profiles |
| Every profile depleted | One combined message (masked emails). Nothing is launched |
| A Codex window is already open | Print the choice. Do **not** open a second window |

There is no live multi-account mux in one Electron window. Close the current Codex UI, then `route` again.

## CLI (agents)

```powershell
$m = "$env:LOCALAPPDATA\CodexParallelDesktop\CodexProfile.ps1"

# Combined pool (masked emails, last-used, depleted, sticky paths)
powershell -NoProfile -ExecutionPolicy Bypass -File $m -Action pool

# Pin this git repo / folder to a profile
powershell -NoProfile -ExecutionPolicy Bypass -File $m -Action stick -Name codex1

# Clear the pin for this folder
powershell -NoProfile -ExecutionPolicy Bypass -File $m -Action stick -Disable

# Pick + launch (or print the choice if a window is already open)
powershell -NoProfile -ExecutionPolicy Bypass -File $m -Action route

# You hit a limit on that account — fail over next time
powershell -NoProfile -ExecutionPolicy Bypass -File $m -Action depleted -Name codex1

# Allowance reset — put it back in the pool
powershell -NoProfile -ExecutionPolicy Bypass -File $m -Action depleted -Name codex1 -Disable
```

`route` and `stick` use the current directory. If `.git` exists in this folder or a parent, the sticky key is the git toplevel. JSON: `-Action route -AsJson` / `-Action pool -AsJson`.

## State

`%LOCALAPPDATA%\CodexParallelDesktop\router-state.json` (UTF-8, no BOM):

- `profiles.<name>.lastUsedAt`
- `profiles.<name>.depleted`
- `stickies.<workspacePath> = <profile>`

No tokens. Emails are never stored here.

## What this is not

- Not a port of `codex-mux` or `patch_app.py`
- Not a patcher for Store `ChatGPT.exe` / `app.asar`
- Not an unofficial ChatGPT HTTP API
- Not a way to share one paid seat across people
