---
name: codex-multi-profile
description: >-
  Several ChatGPT logins for the Microsoft Store Codex app on Windows. The account list lives in
  Codex's own avatar menu (switch, add, rename, remove); a CLI (CodexAccounts.ps1) does the same
  for agents. One saved auth.json per account, chats and settings in ~/.codex are shared.
  Use for Codex multi-account, wrong-account, switch-account or "account menu missing" questions.
---

# Codex Multi-Profile (Windows, Store Codex)

Unofficial helper for people with more than one **authorized** ChatGPT account. Not for account
sharing or bypassing usage limits.

## How it works

- Each account = a saved copy of `~\.codex\auth.json` in `%LOCALAPPDATA%\CodexMultiProfile\accounts\<name>\auth.json`.
- The **Codex** shortcut runs `Start-CodexAccounts.ps1` (hidden): it starts the Store Codex inside its
  package with DevTools on `127.0.0.1:9333`, injects `switcher-inject.js` and stays as the bridge.
- Avatar menu (bottom-left) → **Accounts**: click = switch (2-3 s: only the codex.exe app-server restarts, the window
  stays), **Add account** (Codex restarts on the sign-in screen, the new login is saved under the chosen name),
  pencil = rename, trash = remove. `Ctrl+Alt+A` opens the menu, `1`-`9` pick an account.
- While Codex runs, the live `auth.json` is copied back into the account in use (Codex rotates refresh
  tokens; a stale copy would stop working).

## CLI (agents)

```powershell
$cli = "$env:LOCALAPPDATA\CodexMultiProfile\CodexAccounts.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File $cli list            # -Json for machine output
powershell -NoProfile -ExecutionPolicy Bypass -File $cli status
powershell -NoProfile -ExecutionPolicy Bypass -File $cli save -Name work # save the login in use
powershell -NoProfile -ExecutionPolicy Bypass -File $cli switch -Name work
powershell -NoProfile -ExecutionPolicy Bypass -File $cli rename -Name work -NewName job
powershell -NoProfile -ExecutionPolicy Bypass -File $cli remove -Name old
```

`switch` restarts only Codex's app-server (2-3 s, the window stays) and stops a reply in progress; tell the user first.

## Rules

- Never print or copy tokens; emails are shown masked (`ab***@domain`).
- Do not use Codex's own **Log out** to change accounts: it can invalidate that login's saved copy. Use the menu.
- A watcher (`CodexAccountsWatcher.exe`, HKCU Run) starts the helper whenever the Store Codex runs without it; from the
  original icon Codex restarts once to get the menu. `status` says whether the menu is attached.
- Usage bars come from `chatgpt.com/backend-api/wham/usage` with each saved account's own token (numbers only reach
  the page).
- Log: `%LOCALAPPDATA%\CodexMultiProfile\codex-accounts.log` (masked).
