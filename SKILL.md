---
name: codex-multi-profile
description: >-
  Create, launch, and restore isolated OpenAI Codex Desktop profiles on Windows
  (codex1, codex2, ...) for separate ChatGPT accounts. Default ShareLive keeps
  history, projects, MCP, skills, and memories in ~/.codex; only auth.json is
  per-profile via AuthSwap. Launch MUST set env vars through a cmd wrapper.
  Use for Codex clone, multi-account, ShareLive, wrong-account, or AuthSwap bugs.
---

# Codex Multi-Profile (Windows)

Unofficial helper for **Codex Desktop on Windows** when you need more than one **authorized** ChatGPT login and still want one shared workspace. Not for account sharing, quota bypass, or Terms-of-Use violations.

## Default: ShareLive + AuthSwap

| Piece | Where it lives |
|---|---|
| Sessions, skills, MCP, memories, projects | Always `%USERPROFILE%\.codex` |
| Account | `profiles\<name>\auth.json`, swapped into `~\.codex\auth.json` at launch |
| On close | Watcher saves secondary auth back, then restores main `auth.json` |
| Electron UI | `--user-data-dir=profiles\<name>` (profile **root**, not a nested `electron\` folder) |

Do **not** open the main Store Codex and a profile at the same time.

## Why AuthSwap (not a second `CODEX_HOME`)

The Desktop app-server sometimes **ignores** `CODEX_HOME` and reads `~\.codex\auth.json` anyway. A second home then shows the **main** account. AuthSwap puts the secondary token in the path the app actually reads.

## Launch rules (verified)

1. Do not run executables from `WindowsApps` (Access Denied). Clone `ChatGPT.exe` first.
2. Entry point is **`ChatGPT.exe`**. `Codex.exe` exits 1.
3. `Get-AppxPackage.InstallLocation` can be empty — prefer an existing local clone.
4. Set **both** `CODEX_ELECTRON_USER_DATA_PATH` and `--user-data-dir` to the profile root.
5. Do not rely on `Start-Process` inheriting `$env:CODEX_HOME`. Write a `.cmd` with `set` and `start`.
6. PowerShell 5.1 `Set-Content -Encoding UTF8` writes a **BOM**. That can invalidate `config.toml`. Use `[IO.File]::WriteAllText(..., UTF8Encoding $false)`.
7. Never set a persistent user-level `CODEX_HOME`.
8. Never copy `auth.json` between machines or into git.

## Paths

| Item | Path |
|---|---|
| Install root | `%LOCALAPPDATA%\CodexParallelDesktop` |
| Shared module | `CodexMultiProfile.psm1` |
| Profile launcher | `Launch-CodexProfile.ps1` |
| Restore main | `Launch-CodexMain.ps1` |
| Manager | `CodexProfile.ps1` (`new`, `list`, `status`, `doctor`, `pool`, `stick`, `route`, `depleted`, `layer`, `models`, …) |
| Profiles | `...\profiles\<name>\` |
| Clone | `...\versions\<ver>\app\ChatGPT.exe` |
| Shared home | `%USERPROFILE%\.codex` |

## Commands

```powershell
$root = "$env:LOCALAPPDATA\CodexParallelDesktop"

# Recommended launch (AuthSwap)
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\Launch-CodexProfile.ps1" -Name codex1

# Restore main Store Codex
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\Launch-CodexMain.ps1"

# Manager
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action new -Name codex2
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action list
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action status
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action status -AsJson
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action doctor
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action processes
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action repair
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action sync-check
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action diagnostics
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action verify
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action stop -Name codex1
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action remove -Name codex2 -Force
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action pool
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action stick -Name codex1
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action route
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action depleted -Name codex1
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action layer
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action models
```

## Agent workflow

1. "Switch account / keep my data" → AuthSwap via `Launch-CodexProfile.ps1`.
2. "Create another profile" → `-Action new`, then launch with `Launch-CodexProfile.ps1`.
3. Wrong account in the UI → compare emails in the two `auth.json` files; fix launch (cmd wrapper); do not tell the user to log in again if profile auth is still valid.
4. Access Denied / empty path / exit 1 → clone `ChatGPT.exe`, never `WindowsApps`, never empty `InstallLocation`.
5. After editing scripts, copy `CodexMultiProfile.psm1` **and** the launchers into `%LOCALAPPDATA%\CodexParallelDesktop` and into `scripts\` in this skill. Launchers import the module from `$PSScriptRoot`.
6. "Is it installed / which account is active?" → `-Action status` (emails are masked) then `-Action doctor` / `-Action verify`.
7. "Stuck on secondary account / stale lock" → `-Action repair` (close clones first).
8. "Bug report" → `-Action diagnostics` or `Redact-LaunchTrace.ps1`.
7. User wants a safe log for GitHub → `Redact-LaunchTrace.ps1`.
## Router (opt-in, one window)

Windows counterpart of b-nnett/codex-subscription-router **routing**, still AuthSwap (one `auth.json`).

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action pool
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action stick -Name codex1
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action route
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action depleted -Name codex1
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action depleted -Name codex1 -Disable
```

New work -> least-recently-used non-depleted profile. Same git repo -> sticky. Depleted owner -> failover. All depleted -> one message. If a Codex window is open, print the choice (do not launch a second window).

Layer and ChatGPT Web models are **off by default**:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action layer
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action layer -Disable
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action models
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action models -Disable
```

Layer targets the cloned ChatGPT.exe only. Models only write `config.toml` (no BOM) for a local Responses bridge on 127.0.0.1. This repo does not log into chatgpt.com and does not name a companion app.

## Poisoned profile auth


If the user opens **Codex Main** while a profile is still running, restore can write the **main** token into `profiles\<name>\auth.json`.

Guards already in the scripts:

- Watcher / `Launch-CodexMain` only save profile auth when the active email **differs** from `auth.json.__main__`
- Keep `auth.json.secondary.bak`
- If profile auth is missing or equals main → bootstrap login (clear active auth, force secondary sign-in)

## Do not

- Copy or commit `auth.json`
- Open main + profile ShareLive together
- Launch `Codex.exe` or a `WindowsApps` path
- `Start-Process` without an explicit cmd/`CODEX_HOME`
- Write `config.toml` with `Set-Content -Encoding UTF8` on Windows PowerShell 5.1

Details: [docs/architecture.md](docs/architecture.md), [docs/troubleshooting.md](docs/troubleshooting.md).
