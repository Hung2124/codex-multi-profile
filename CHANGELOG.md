# Changelog

All notable changes to this project are documented here.

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
