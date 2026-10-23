---
name: codex-multi-profile
description: >-
  Multi-workspace profile router, MCP server (.mcp.json) security auditor, and CLAUDE.md <-> AGENTS.md
  instruction bridge for Claude Code and OpenAI Codex. Isolates Enterprise, Open-Source Maintainer, and
  Personal profiles across ~/.claude and ~/.codex, and provides a native workspace switcher for the
  Microsoft Store Codex app on Windows.
---

# Codex Multi-Profile (Claude Code, MCP & OpenAI Codex)

Open-source developer toolkit for isolating **authorized** Enterprise SSO, Client, and Open-Source Maintainer workspaces across **Claude Code** (`~/.claude`), **Model Context Protocol (`.mcp.json`)**, and **OpenAI Codex** (`~/.codex`).

## Cross-Platform CLI & SDK (`v2.0+`)

```bash
# Audit .mcp.json for hardcoded tokens and non-loopback endpoints
npx codex-multi-profile mcp-audit .mcp.json

# Synchronize CLAUDE.md and AGENTS.md instructions
npx codex-multi-profile sync-docs .

# Inspect saved Claude Code or Codex profiles
npx codex-multi-profile profiles claude --json
```

## Windows Store Codex Integration

- Each workspace profile is stored as an isolated snapshot in `%LOCALAPPDATA%\CodexMultiProfile\accounts\<name>\auth.json`.
- The **Codex** shortcut runs `Start-CodexAccounts.ps1` (hidden): it launches the Store Codex inside its
  package with DevTools bound to `127.0.0.1:9333`, injects `switcher-inject.js`, and bridges workspace switches.
- Avatar menu (bottom-left) → **Accounts**: click = switch (2-3 s: only the `codex.exe app-server` child restarts, the window
  stays open), **Add account** (restarts on the sign-in screen to register another authorized workspace),
  pencil = rename, trash = remove. `Ctrl+Alt+A` opens the menu, `1`-`9` pick a workspace profile.
- While Codex runs, rotated refresh tokens in the live `auth.json` are synced back into the active workspace profile.

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
