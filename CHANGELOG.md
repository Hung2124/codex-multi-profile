# Changelog

All notable changes to this project are documented here.

## 0.3.0 — 2026-09-28

### Added
- **In-app account switcher** (opt-in): click your avatar in Codex and the account menu lists your saved accounts under your identity row. Click one to switch (one-window AuthSwap via `Launch-CodexProfile.ps1 -FastSwitch`, Codex reopens in a few seconds); `1`-`9` pick by number; `Ctrl+Alt+A` opens the menu
- **Add account** from that menu (Codex-style dialog, accents normalised: "Công việc" → `cong-viec`); the new account appears in the list at once with a **Sign in now** action
- **Remove account** from that menu (trash on hover + confirm dialog); `Remove-CodexProfile` deletes the saved login, launchers, Desktop shortcut and router entries, never the active profile, never `~\.codex`
- Styled with the current Codex (26.9xx) account-menu metrics and light / dark tokens; injected as a closed shadow root inside Codex's own menu, React keeps rendering its own rows. Falls back to a same-looking account control if the avatar button cannot be found
- **Main account** row (opens the Store Codex after a confirm), usage-limit card that suggests the next saved, non-depleted login (suggestion only)
- Vietnamese and English UI (auto from system, or `-Lang vi|en`)
- `Start-CodexSwitcherHost.ps1`: hidden per-clone bridge. Checks the loopback CDP port is owned by the cloned ChatGPT.exe, talks over `Runtime.addBinding` (no HTTP listener, no token file), re-injects after renderer reloads, exits with the clone
- `CodexProfile.ps1 -Action switcher` (`-Disable`, `-Lang`, `-CdpPort`), **Trong Codex** toggle in Codex Accounts, `Install-CodexMultiProfile.ps1 -EnableInAppSwitcher`, `install.ps1 -InApp` / `CODEX_MP_INAPP=1`
- Router module: `Get-CodexSwitcherState`, `Set-CodexSwitcherEnabled`, `Get-CodexCdpLaunchPort`, `Get-CodexSwitcherSnapshot`, `ConvertFrom-CodexSwitcherMessage`, `Test-CodexTextHasFullEmail`, `Remove-CodexProfile`
- `doctor` reports `switcher-on` / `switcher-missing`; `tests/InAppSwitcher.Tests.ps1`; `docs/in-app-switcher.md`

### Changed
- Launchers stop stale switcher hosts before a switch (`Stop-CodexSwitcherHosts`)
- Uninstall also removes packaged `.js` files
- Scripts renormalized to the CRLF line endings `.gitattributes` already asked for

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
