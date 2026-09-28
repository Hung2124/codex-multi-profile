# In-app account switcher (Windows)

Switch ChatGPT accounts **from Codex's own avatar menu**. Click your avatar at the bottom-left of
Codex: under your account there is now an **Accounts** list. Click an account and Codex switches to it.
**Add account** puts a new one in the list; hover a row and click the trash icon to remove it.

<p align="center">
  <img src="images/in-app-switcher.png" alt="Accounts section inside the Codex avatar menu" width="880">
</p>

<p align="center">
  <img src="images/in-app-switcher-add.png" alt="Add account dialog in Codex style" width="880">
</p>

Opt-in, off by default. The macOS switchers on GitHub are separate menu-bar apps; this lives inside the
Codex window on Windows, matches the current Codex menu (26.9xx metrics: 20 px menu radius, 15 px rows,
13 px / 430 text, Codex light and dark tokens) and does not patch Codex.

## Turn it on

Either:

- **Codex Accounts** → click **Trong Codex: Tat** so it reads **Trong Codex: Bat**
  (it offers to reopen the current profile so the list shows up right away), or
- CLI:

```powershell
$m = "$env:LOCALAPPDATA\CodexParallelDesktop\CodexProfile.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File $m -Action switcher            # on
powershell -NoProfile -ExecutionPolicy Bypass -File $m -Action switcher -Lang vi   # force Vietnamese UI (auto | vi | en)
powershell -NoProfile -ExecutionPolicy Bypass -File $m -Action switcher -Disable   # off
```

- Fresh install with it already on:

```powershell
$env:CODEX_MP_INAPP = '1'; irm https://raw.githubusercontent.com/Hung2124/codex-multi-profile/main/install.ps1 | iex
```

Then open any profile (Codex Accounts, `Codex1`, …) and click your avatar at the bottom-left of Codex.

## What you get

| In Codex | Does |
|:---|:---|
| Avatar menu → **Accounts** | Your saved accounts under your identity row: name, masked email, **Out of quota** tag, a check on the one in use |
| Click an account | Switches right away (no extra prompt). Codex reopens on that login in a few seconds |
| `1`–`9` while the menu is open | Same as clicking the account with that number (shown on the right of each row) |
| Trash icon (hover a row) | "Remove …?" dialog. Deletes that saved login on this PC; chats and settings in `~\.codex` stay. The account in use cannot be removed |
| **Add account** | Dialog asks for a name (Vietnamese accents are fine: "Công việc" → `cong-viec`). The new account appears in the list right away; **Sign in now** opens Codex's own login for it, once |
| **Main account** row | Confirms, then opens the Microsoft Store Codex with your main login (no account list there; come back via Codex Accounts) |
| `Ctrl+Alt+A` | Opens the avatar menu from anywhere in Codex |
| Usage-limit card | When Codex says "You've hit your usage limit", a card offers **Switch to …** (marks the current one out of quota). Suggestion only |

If a future Codex build moves the avatar button so it cannot be found, a small account control with the
same look appears at the bottom-left instead and opens the same list (it can be dragged).

Light and dark follow Codex. Text follows the system language (Vietnamese or English) unless `-Lang` is set.

## What happens when you pick an account

It is the same **one-window AuthSwap** as Codex Accounts:

1. A "Switching to …" card shows over Codex.
2. `Launch-CodexProfile.ps1 -Name <pick> -FastSwitch` saves the outgoing login, closes the clone,
   swaps `~\.codex\auth.json`, and reopens Codex through the `.cmd` env wrapper.
3. Codex is back in a few seconds on the new account. Chats, projects, skills, MCP and settings are
   the same (ShareLive `~\.codex`). Text you had not sent yet in the composer is not kept.

Why a restart and not a live swap: the Codex app-server reads the signed-in token when it starts.
Swapping `auth.json` under a running Codex is how you end up with a UI on one account and requests on
another. A clean restart of the clone is the reliable path.

## How it works

```
Launch-CodexProfile.ps1
  ├─ .cmd wrapper → cloned ChatGPT.exe --remote-debugging-address=127.0.0.1 --remote-debugging-port=9333
  └─ Start-CodexSwitcherHost.ps1  (hidden PowerShell, one per clone)
        ├─ checks the port is owned by the *cloned* ChatGPT.exe (never Store / WindowsApps, never a browser)
        ├─ CDP: Runtime.addBinding('cmpSwitcherBridge') + inject switcher-inject.js (survives reloads)
        ├─ page: when Codex's account menu (role=menu) opens, add the Accounts section under the identity row
        ├─ pushes masked state (profiles, active, suggestion) into the page every 15 s
        └─ on a click: validates the request → Launch-CodexProfile.ps1 -FastSwitch / Launch-CodexMain.ps1,
           add = CodexProfile.ps1 -Action new, remove = Remove-CodexProfile (never the active one)
```

- **No HTTP server, no token file.** The page talks to the host only through a CDP binding on the loopback
  websocket the host already holds.
- **Strict input.** Requests are JSON with a fixed set of types; profile names must match an existing
  folder (`^[a-z0-9][a-z0-9-]{0,63}$`). Anything else is rejected and logged.
- **Masked only.** Every event is checked for unmasked emails before it is sent into the page.
- **Isolated UI.** The section added to Codex's menu is its own closed shadow root (Codex styles and React
  are untouched; React keeps updating its own rows). Built with `createElement` (no HTML strings,
  Trusted-Types safe), constructable stylesheets (CSP safe), no network calls.
- **Lifecycle.** The host exits when the clone closes. The next launch starts a new one. `Launch-*` stops
  stale hosts first.
- **Port.** `switcher-state.json` → `cdpPort` (default `9333`). If the optional [layer](layer.md) is on too,
  both share the layer port.

## Limits

- Cloned `ChatGPT.exe` only. The Microsoft Store Codex (**Codex Main**) never gets the Accounts list.
- One Codex window at a time (AuthSwap owns one `auth.json`).
- First sign-in for a new profile still happens in Codex's own login screen.
- The loopback DevTools port can be reached by other programs running as you on this PC.
  If that is a concern for your machine, leave the switcher off and use Codex Accounts.

## Troubleshooting

| Symptom | Try |
|:---|:---|
| No Accounts list in the avatar menu | `-Action switcher` shows ON? Reopen the profile. `-Action doctor` should list `switcher-on` |
| List says the helper is not connected | The host is not running. Reopen the profile from Codex Accounts |
| "The switch did not finish" | Check `launch-trace.log` (`[switcher]` lines) and run `-Action doctor` |
| Port already in use | Pick another loopback port: `-Action switcher -CdpPort 9444`, then reopen the profile |

Logs: `%LOCALAPPDATA%\CodexParallelDesktop\launch-trace.log` (`[switcher]` lines, emails masked).
