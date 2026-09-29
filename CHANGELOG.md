# Changelog

All notable changes to this project are documented here.

## 0.4.0 — 2026-09-28

Rebuilt around the Microsoft Store Codex. Codex 26.9xx refuses to run outside its package ("The process has no
package identity"), so the cloned `ChatGPT.exe` the earlier versions launched no longer starts. This release
replaces the unreleased 0.3.0 clone-based in-app switcher.

### Added
- **Accounts in the Codex avatar menu** of the Store app: click an account to switch in 2-3 s (only the codex.exe
  app-server restarts, the window stays; full restart from a sign-in screen), **Add account** (Codex reopens on its sign-in screen, the new login is saved under the chosen name),
  rename (pencil) and remove (trash) on hover, `1`-`9`, `Ctrl+Alt+A`, usage-limit suggestion card
- One **Codex** shortcut (Desktop + Start menu) that starts the Store Codex through `IApplicationActivationManager`
  with DevTools on `127.0.0.1` and runs the hidden helper (`Start-CodexAccounts.ps1`) while Codex is open
- Live token sync: the `auth.json` Codex refreshes is copied back into the account in use, so saved logins do not go stale
- Any new login seen while Codex runs is saved automatically; a login that is not saved is never removed
- Menu language follows Codex (`<html lang>`), Vietnamese or English
- **Usage bars** under every account (5h / week on paid plans, month on free), from `/wham/usage` with that
  account's own token, non-blocking; hover shows the reset time
- **Watcher** at sign-in (`CodexAccountsWatcher.exe`, ~25 MB): the menu also appears when Codex is opened from its
  own taskbar / Start icon (Codex restarts once); `-NoAutoStart` to skip
- While switching, an opaque veil hides the error screen Codex shows for a second, until its UI is back
- `CodexAccounts.ps1` CLI: `list`, `status`, `save`, `switch`, `rename`, `remove`, `lang`
- `Install-CodexMultiProfile.ps1 -RemoveLegacy` / `CODEX_MP_REMOVE_LEGACY=1`: imports the logins saved by 0.1-0.2 and
  removes `%LOCALAPPDATA%\CodexParallelDesktop` (junctions into `~\.codex` are unlinked, never followed)

### Changed
- Helper cost: no `Runtime.enable`, no JSON parsing of CDP replies, no WMI polling, work only when
  `auth.json` or the store changes (~130 MB, ~1 s CPU per minute)
- Shortcut runs through `conhost --headless` (no VBScript)
- Page script is event-driven: observes only `<body>`'s direct children (Codex menus are portals) and scans right after
  the avatar click; the usage-limit watcher batches small nodes once a second (no work per streamed token)
- Never a restart loop: Codex is reopened for its menu port at most once per 10 minutes unless the last reopen
  worked, and the watcher waits longer after each helper that ends within a minute (20 s doubling up to 10 min)
- Closing Codex ends its whole process tree with `Stop-Process` from one snapshot and never throws; Codex is always
  started again after a failed switch

### Removed
- Cloned `ChatGPT.exe`, Codex1 / Codex Main launchers, AuthSwap watcher, Codex Accounts WPF app, router
  (`pool` / `stick` / `route`), layer, ChatGPT Web model block, doctor / repair / diagnostics

### Fixed
- The helper hung with GBs of memory after Codex reloaded its window: a `Get-Content` string carries PSProvider /
  PSDrive note properties that `ConvertTo-Json -Depth 8` serialized; the page script is now read with `ReadAllText`
- The helper found no Codex window on Windows PowerShell 5.1 (`ConvertFrom-Json` emits a JSON array as one object),
  so the menu was never injected

## 0.2.0 — 2026-08-20

### Added
- **Codex Accounts** desktop app (`Show-CodexAccountApp.ps1`): WPF account picker (masked email, last-used, depleted, sticky). Click / Enter closes the open Codex window then AuthSwap-launches the saved account
- Desktop shortcut **Codex Accounts** next to Codex1 / Codex Main
- One-command Windows install stays `irm .../install.ps1 | iex` (counterpart of b-nnett/codex-subscription-router curl|bash)
- Subscription router (AuthSwap, one window): `pool`, `stick`, `route`, `depleted` on CodexProfile.ps1
- Sticky git-repo/workspace -> profile; new work picks least-recently-used non-depleted profile; depleted owner fails over; all-depleted prints one combined message
- Combined pool view with masked emails, last-used, depleted flag, sticky paths
- Optional clone-only desktop layer (`layer` / `layer -Disable`)
- Optional ChatGPT Web model block in `~/.codex/config.toml` (`models` / `models -Disable`)
- `docs/router.md`, `docs/layer.md`, `tests/LayerAndRouter.Tests.ps1`

### Changed
- VERSION 0.2.0; installer packages `CodexRouter.psm1`, `Start-CodexLayer.ps1`, `layer-inject.js`, `Show-CodexAccountApp.ps1`
- Existing Codex1 / Codex Main / doctor / verify / AuthSwap launch unchanged until you opt in

## 0.1.4 — 2026-08-14

### Added
- `repair` clears a stale AuthSwap lock and restores main auth from backup
- `sync-check` SHA256-compares packaged scripts vs LocalAppData install
- `diagnostics` / `Export-CodexDiagnostics.ps1` for redacted support bundles
- `install.ps1` tag/`vX.Y.Z` Ref support and temp cleanup
- Recipe cards for stale lock + diagnostics; CODEOWNERS; SUPPORT.md

### Changed
- Installer copies every name from `Get-CodexPackagedScriptNames`
- Menu, FAQ, SKILL, and doctor hint point at `repair` / `diagnostics`

## 0.1.3 — 2026-08-14

### Added
- `doctor` health checks (stale lock, dual-window, BOM, poisoned profile)
- `processes` to list Store vs clone ChatGPT.exe
- `Redact-LaunchTrace.ps1` for safe bug-report logs
- SUPPORT, recipe cards, contributor invariants

### Changed
- Bug template asks for doctor output and redacted logs

## 0.1.2 — 2026-08-13

### Added
- `status -AsJson` for scripts (emails still masked)
- `remove -Force` to delete one profile folder, never `~\.codex`

### Fixed
- `launch-trace.log` no longer writes full ChatGPT emails
- CI uses `actions/checkout@v7`

### Changed
- Installer imports `CodexMultiProfile.psm1` instead of duplicating helpers

## 0.1.1 — 2026-08-13

### Added
- `CodexProfile.ps1 -Action status` (masked emails) and `-Action verify`
- `Update-CodexMultiProfile.ps1` to pull and reinstall
- FAQ, feature-request template, Dependabot for GitHub Actions

### Fixed
- Uninstall now removes every Desktop shortcut whose target is CodexParallelDesktop
- CI uses `actions/checkout@v5` and `tests/Run-All.ps1`

### Security
- Status/list never print a full ChatGPT email

## 0.1.0 — 2026-08-13

### Added
- AuthSwap launchers for a secondary ChatGPT login while keeping `~\.codex` shared
- Restore-main shortcut that refuses to copy the main token into a profile
- Shared PowerShell module with JWT email parse, bootstrap detection, and UTF-8 (no BOM) writes
- Installer, uninstall, Desktop shortcuts, and Codex/Cursor skill copy
- Tests for poison-guard, JWT parse, profile keys, and script parse
- Windows CI

### Security
- `auth.json` stays on disk only. Nothing is uploaded. Do not commit logs or tokens.
