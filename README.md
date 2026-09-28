# Codex Multi-Profile

<p align="center">
  <a href="https://github.com/Hung2124/codex-multi-profile/actions/workflows/ci.yml"><img src="https://github.com/Hung2124/codex-multi-profile/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/Hung2124/codex-multi-profile/releases"><img src="https://img.shields.io/github/v/release/Hung2124/codex-multi-profile?label=release" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-yellow.svg" alt="MIT"></a>
  <img src="https://img.shields.io/badge/platform-Windows-0078D4.svg" alt="Windows">
</p>

<p align="center">
  <strong>Switch ChatGPT accounts from the Codex avatar menu, in the Microsoft Store Codex app on Windows.</strong><br>
  One app, one workspace: chats, projects, skills and settings stay shared.
</p>

<p align="center">
  <a href="README.vi.md">Tiếng Việt</a> &middot;
  <a href="docs/architecture.md">How it works</a> &middot;
  <a href="docs/troubleshooting.md">Troubleshooting</a> &middot;
  <a href="SUPPORT.md">Support</a>
</p>

> Unofficial helper, not affiliated with OpenAI. For people with more than one **authorized** ChatGPT account.
> Not for account sharing or getting around usage limits.

## What you get

Click your avatar at the bottom-left of Codex. Under your name there is an **Accounts** section:

| In the menu | Does |
|:---|:---|
| Click an account | Switches to it in 2-3 seconds; the Codex window stays open (from a sign-in screen Codex restarts, ~10 s) |
| **Add account** | Codex restarts on its sign-in screen; sign in with the other account and it is saved under the name you typed |
| Pencil / trash (hover a row) | Rename / remove a saved account (the one in use cannot be removed) |
| `1`-`9` while the menu is open | Pick the account with that number |
| `Ctrl+Alt+A` | Open the menu from anywhere in Codex |
| Usage bars | Under each account: what is left of its limits (5h and week on paid plans, month on free), green / amber / red; hover for the reset time. Refreshed when you open the menu (at most once a minute) |
| Usage-limit card | When Codex says you hit your usage limit, it offers to switch to the next saved account |

The menu follows Codex's language (Vietnamese or English) and its light / dark theme.

## Install

Needs Windows 10/11, [Codex](https://chatgpt.com/codex) from the Microsoft Store, signed in once.

```powershell
irm https://raw.githubusercontent.com/Hung2124/codex-multi-profile/main/install.ps1 | iex
```

This saves the account Codex is signed in to now as `main`, puts a **Codex** shortcut on the Desktop and in the
Start menu, and starts a tiny watcher at sign-in (~25 MB, no window). Open Codex any way you like: from the
original taskbar / Start icon Codex restarts once in its first seconds to get the menu; from the **Codex**
shortcut it opens with the menu straight away (pin that one to skip the restart). `-NoAutoStart` skips the watcher.

Upgrading from the old clone-based version (Codex1 / Codex Main / Codex Accounts shortcuts)? This imports
those saved logins and removes the old install and its cloned `ChatGPT.exe` copies:

```powershell
$env:CODEX_MP_REMOVE_LEGACY = '1'; irm https://raw.githubusercontent.com/Hung2124/codex-multi-profile/main/install.ps1 | iex
```

## Good to know

- **Do not use Codex's own "Log out" to change account.** It can invalidate that account's saved login. Use the menu.
- A saved login that expired shows Codex's sign-in screen after switching. Sign in with that account again and
  it is saved automatically. A small account button stays at the bottom-left there, so you can switch away.
- A reply Codex is still writing is stopped when you switch (its login changes under it).
- The menu helper is a hidden PowerShell process that runs only while Codex is open (~130 MB, near-zero CPU).

## Command line (agents, scripts)

```powershell
$cli = "$env:LOCALAPPDATA\CodexMultiProfile\CodexAccounts.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File $cli list      # or: status | save -Name x | switch -Name x | rename -Name x -NewName y | remove -Name x | lang -Name vi
```

## Uninstall

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexMultiProfile\Uninstall-CodexMultiProfile.ps1"   # add -RemoveAccounts to delete saved logins
```

`~\.codex` (chats, settings, the login in use) is never touched.

## Privacy and security

- Saved logins stay on this PC in `%LOCALAPPDATA%\CodexMultiProfile\accounts`. Nothing is sent anywhere.
- The Codex window only ever receives masked emails (`ab***@example.com`), never tokens.
- The menu talks to its helper through the Chrome DevTools protocol on `127.0.0.1` only. Other programs running
  as you on this PC can reach that port too; if that matters on your machine, do not use this tool.
- Codex files are not modified. See [docs/architecture.md](docs/architecture.md) and [SECURITY.md](SECURITY.md).

## License

MIT
