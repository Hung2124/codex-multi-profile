# Changelog

All notable changes to this project are documented here.

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
