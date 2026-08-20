# Architecture

## Problem

Codex Desktop on Windows stores ChatGPT auth at `%USERPROFILE%\.codex\auth.json`.

A second `CODEX_HOME` often fails: the Electron app-server still reads the main token. Owl logs may also show `Ignoring late userData path change` if `CODEX_ELECTRON_USER_DATA_PATH` ≠ `--user-data-dir`.

## AuthSwap

Keep **one** Codex home (`~\.codex`) for data. Only the token file moves.

```mermaid
sequenceDiagram
    participant User
    participant Launch as Launch-CodexProfile
    participant Disk as ~/.codex/auth.json
    participant Profile as profiles/codex1/auth.json
    participant App as Cloned ChatGPT.exe
    participant Watch as watch-authswap-restore

    User->>Launch: open Codex1
    Launch->>Disk: copy to auth.json.__main__
    Launch->>Profile: copy into ~/.codex/auth.json
    Launch->>App: start with cmd wrapper + --user-data-dir
    Launch->>Watch: start
    User->>App: close window
    Watch->>Profile: save only if email is not main
    Watch->>Disk: restore auth.json.__main__
```

Shared logic lives in `scripts/CodexMultiProfile.psm1`:

- `Get-AuthEmailFromFile` — JWT `email` from `auth.json`
- `Test-NeedBootstrapLogin` — missing or poisoned profile auth
- `Test-ShouldSaveProfileAuth` — poison guard on close / Codex Main
- `Write-Utf8NoBom` — PowerShell 5.1 `Set-Content -Encoding UTF8` writes a BOM
- `New-CodexEnvCmd` — `CODEX_HOME` via `set` + `start`, not `Start-Process` alone

## Process rules

1. Clone `ChatGPT.exe` out of the Store package. `WindowsApps` is Access Denied.
2. Launch via `.cmd`. `Start-Process` often drops `CODEX_HOME`.
3. `CODEX_ELECTRON_USER_DATA_PATH` and `--user-data-dir` are both the profile **root**.
4. Never set a persistent user-level `CODEX_HOME`.

## Files

| Script | Role |
|---|---|
| `install.ps1` | Download zip (branch or tag) + run installer |
| `Install-CodexMultiProfile.ps1` | Copy packaged scripts, clone app, shortcuts, skill |
| `Launch-CodexProfile.ps1` | AuthSwap in + start clone |
| `watch-authswap-restore.ps1` | AuthSwap out on close |
| `Launch-CodexMain.ps1` | Save secondary if needed, restore main, start Store app |
| `CodexProfile.ps1` | `new` / `launch` / `list` / `status` / `doctor` / `repair` / `sync-check` / `diagnostics` / … |
| `Export-CodexDiagnostics.ps1` | Redacted support bundle (no `auth.json`) |
| `Redact-LaunchTrace.ps1` | Scrub emails/home paths from launch-trace.log |
| `Update-CodexMultiProfile.ps1` | `git pull --ff-only` + reinstall + verify |

## Optional router (0.2.0)

`scripts/CodexRouter.psm1` stores `router-state.json` (lastUsedAt, depleted, stickies). No tokens.
`route` picks sticky workspace owner or LRU of non-depleted profiles, then launches via AuthSwap.
Still one window. See [router.md](router.md).

## Optional layer / models

Layer: loopback into the cloned ChatGPT.exe only ([layer.md](layer.md)).
Models: marked block in `~/.codex/config.toml` pointing at a local bridge. No chatgpt.com login here.

## Files (0.2.0)

| Script | Role |
|---|---|
| `CodexRouter.psm1` | pool / stick / route / depleted / layer state / models block |
| `Start-CodexLayer.ps1` | Loopback apply of `layer-inject.js` to the clone |
| `layer-inject.js` | Badge, wider transcript, keep details open |
