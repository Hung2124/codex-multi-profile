# Codex Multi-Profile

<p align="center">
  <a href="https://github.com/Hung2124/codex-multi-profile/actions/workflows/ci.yml"><img src="https://github.com/Hung2124/codex-multi-profile/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/Hung2124/codex-multi-profile/releases"><img src="https://img.shields.io/github/v/release/Hung2124/codex-multi-profile?label=release" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-yellow.svg" alt="MIT"></a>
  <img src="https://img.shields.io/badge/platform-Windows-0078D4.svg" alt="Windows">
</p>

<p align="center">
  <strong>Two or more authorized ChatGPT logins on Codex Desktop for Windows.<br>One shared workspace. One window (AuthSwap).</strong>
</p>

<p align="center">
  <a href="README.vi.md">Tiếng Việt</a> &middot;
  <a href="docs/router.md">Router</a> &middot;
  <a href="docs/recipes.md">Recipes</a> &middot;
  <a href="docs/troubleshooting.md">Troubleshooting</a> &middot;
  <a href="SUPPORT.md">Support</a>
</p>

<p align="center">
  <img src="docs/images/hero.png" alt="Codex Multi-Profile -- MAIN and CODEX1 with AuthSwap" width="920">
</p>

> Unofficial helper. Not affiliated with OpenAI. Needs [Codex Desktop](https://chatgpt.com/codex) from the Microsoft Store.

## Install

One command. It downloads this repo and runs the Windows installer (AuthSwap + subscription router):

```powershell
irm https://raw.githubusercontent.com/Hung2124/codex-multi-profile/main/install.ps1 | iex
```

Until 0.2.0 is merged, that `main` URL still installs 0.1.4. Use the PR branch:

```powershell
irm https://raw.githubusercontent.com/Hung2124/codex-multi-profile/feature/v0.2.0-layer-router-models/install.ps1 | iex
```

That is the Windows counterpart of [b-nnett/codex-subscription-router](https://github.com/b-nnett/codex-subscription-router#install) `curl | bash` -- **without** patching ChatGPT.exe or unpacking `app.asar`.

1. Install Codex Desktop and sign in once (**main** account) if you have not already.
2. Close every Codex window.
3. Run the one-liner above (or clone + `scripts\Install-CodexMultiProfile.ps1`).

### Desktop shortcuts

| Shortcut | What it does |
|:---|:---|
| **Codex1** | Secondary ChatGPT login (first run asks you to sign in) |
| **Codex Main** | Restore the original account and open Store Codex |
| **Codex Profiles** | List / create another profile |

**Rule:** close one Codex UI before opening the other.

From a git clone instead of the one-liner:

```powershell
git clone https://github.com/Hung2124/codex-multi-profile.git
cd codex-multi-profile
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-CodexMultiProfile.ps1
```

Quick check after install:

```powershell
$m = "$env:LOCALAPPDATA\CodexParallelDesktop\CodexProfile.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File $m -Action doctor
powershell -NoProfile -ExecutionPolicy Bypass -File $m -Action verify
powershell -NoProfile -ExecutionPolicy Bypass -File $m -Action pool
```

## Routing

Windows routing in the spirit of b-nnett/codex-subscription-router. Still **one** Codex window because AuthSwap uses a single `~\.codex\auth.json`. Full table: [docs/router.md](docs/router.md).

| Situation | Behaviour |
|:---|:---|
| New chat / new folder | Least-recently-used **non-depleted** profile |
| Follow-up in the same git repo or workspace | Sticky owner |
| Sticky owner marked depleted | Fail over to another non-depleted profile |
| Every profile depleted | One combined message (masked emails). Nothing launches |
| A Codex window is already open | Print the choice. Do not open a second window |

```powershell
$m = "$env:LOCALAPPDATA\CodexParallelDesktop\CodexProfile.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File $m -Action pool
powershell -NoProfile -ExecutionPolicy Bypass -File $m -Action stick -Name codex1
powershell -NoProfile -ExecutionPolicy Bypass -File $m -Action route
powershell -NoProfile -ExecutionPolicy Bypass -File $m -Action depleted -Name codex1
powershell -NoProfile -ExecutionPolicy Bypass -File $m -Action depleted -Name codex1 -Disable
```

Use only **authorized personal / work accounts you own**. Marking `depleted` is a local flag. This is not a quota-bypass product and not a live multi-account mux.

## Purpose and acceptable use

This repository is a **local, open-source utility** for Windows developers who already hold **multiple authorized ChatGPT accounts** (for example personal and work) and need to switch between them in Codex Desktop while keeping one shared workspace.

It is **not** intended for:

- sharing one paid subscription across people or machines
- bypassing rate limits, quotas, or billing
- automating sign-in, scraping, or unofficial API access
- any use that violates [OpenAI Terms of Use](https://openai.com/policies/terms-of-use)

Use only accounts you own or are explicitly allowed to use. Changes that enable abuse are out of scope ([CONTRIBUTING.md](CONTRIBUTING.md)).

---

## The problem

A second `CODEX_HOME` often **does not** switch accounts. The Desktop app-server still reads `~\.codex\auth.json`, so you land on the main ChatGPT user.

| You try... | What actually happens |
|:---|:---|
| Copy `~\.codex` + set `CODEX_HOME` | UI still shows the main account |
| `Start-Process` with `$env:CODEX_HOME` | Env is dropped -> wrong account |
| Run `ChatGPT.exe` from `WindowsApps` | Access Denied |
| Launch `Codex.exe` | Process exits with code 1 |

**AuthSwap** keeps sessions, skills, MCP, and memories in `~\.codex`. Only `auth.json` moves for the profile window, then restores on close.

<p align="center">
  <img src="docs/images/flow.png" alt="Open Codex1 -> swap auth.json -> secondary account; on close restore main" width="920">
</p>

---

## Usage

Set `$root` once, then call the actions you need:

```powershell
$root = "$env:LOCALAPPDATA\CodexParallelDesktop"
$m    = "$root\CodexProfile.ps1"
```

| Goal | Command |
|:---|:---|
| Open secondary account | `...\Launch-CodexProfile.ps1 -Name codex1` |
| Restore main + Store app | `...\Launch-CodexMain.ps1` |
| Create `codex2` | `-Action new -Name codex2` |
| List / status / doctor | `-Action list` / `status` / `doctor` |
| Pool / stick / route / depleted | `-Action pool` / `stick` / `route` / `depleted` |
| Repair stale AuthSwap lock | `-Action repair` |
| Install file sync check | `-Action sync-check` |
| JSON status | `-Action status -AsJson` |
| Running processes | `-Action processes` |
| Diagnostic bundle | `-Action diagnostics` |
| Verify install | `-Action verify` |
| Remove a profile | `-Action remove -Name codex2 -Force` |
| Optional clone layer | `-Action layer` / `layer -Disable` |
| Optional ChatGPT Web models | `-Action models` / `models -Disable` |
| Safe bug-report log | `...\Redact-LaunchTrace.ps1` |
| Update from git clone | `.\scripts\Update-CodexMultiProfile.ps1` |

Existing 0.1.4 launch (Codex1 / Codex Main / doctor / verify / AuthSwap) is unchanged until you opt in to router, layer, or models.

Tests (no Codex UI required):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-All.ps1
```

### Optional extras (off by default)

- **Layer** -- badge, wider transcript, keep details open on the **cloned** ChatGPT.exe only. [docs/layer.md](docs/layer.md)
- **ChatGPT Web models** -- write `~\.codex\config.toml` (UTF-8, no BOM) with `chatgpt-web/luna|light|medium|high|xhigh|pro` pointing at a local Responses bridge you already run on `127.0.0.1` (default `http://127.0.0.1:1455/v1`). This repo does **not** log you into chatgpt.com and does not ship or name a companion scraper.

---

## Agent skill

Install also copies `SKILL.md` to:

- `%USERPROFILE%\.codex\skills\codex-multi-profile\`
- `%USERPROFILE%\.cursor\skills\codex-multi-profile\`

So Codex / Cursor agents know **not** to launch `Codex.exe`, **not** to use `WindowsApps`, and **not** to `Start-Process` without a `.cmd` wrapper.

---

## Safety

| Does | Does not |
|:---|:---|
| Copy `auth.json` **locally** between `~\.codex` and `profiles\<name>` | Upload tokens or set a permanent `CODEX_HOME` |
| Clone `ChatGPT.exe` out of the Store package | Run the Store binary in-place |
| Restore main auth on close; refuse to save if active email == main | Delete `~\.codex` history |
| Choose among **your** profiles (sticky / LRU / depleted) | Mux many accounts in one window, patch asar, or bypass quotas |

Do not commit `auth.json` or `*.bak`. Prefer `Redact-LaunchTrace.ps1` before pasting logs.

---

## Uninstall

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Uninstall-CodexMultiProfile.ps1
# add -PurgeProfiles to also delete local profile auth copies
```

`~\.codex` is never deleted.

---

## Docs

| Doc | Topic |
|:---|:---|
| [Router](docs/router.md) | pool / stick / route / depleted |
| [Layer](docs/layer.md) | Optional clone-only desktop tweaks |
| [Architecture](docs/architecture.md) | Why AuthSwap exists |
| [Troubleshooting](docs/troubleshooting.md) | Wrong account, locks, BOM |
| [FAQ](docs/faq.md) | Common questions |
| [Recipes](docs/recipes.md) | Daily command cards |
| [Support](SUPPORT.md) | Before opening an issue |
| [Changelog](CHANGELOG.md) | Releases |
| [Contributing](CONTRIBUTING.md) | PR rules |
| [Security](SECURITY.md) | Token handling |

## License

[MIT](LICENSE) © Hung Nguyen
