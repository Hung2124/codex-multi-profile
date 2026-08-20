# Changelog

All notable changes to this project are documented here.

## 0.2.0 — 2026-08-20

### Added
- **Codex Accounts** desktop app (`Show-CodexAccountApp.ps1`): WPF account picker (masked email, last-used, depleted, sticky). Click / Enter launches AuthSwap; one-window message if Codex is already open
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
