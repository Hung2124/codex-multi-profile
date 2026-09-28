# AGENTS.md

Windows-only helper: several ChatGPT logins for the **Microsoft Store Codex**, switched from the Codex avatar menu.

- Read `SKILL.md` and `docs/architecture.md` before changing launch or switch behavior.
- Start the Store Codex only through `Start-CodexStore` (IApplicationActivationManager). Do not copy / clone
  `ChatGPT.exe` (26.9xx needs package identity), do not use `Invoke-CommandInDesktopPackage` or `shell:AppsFolder`
  (both hang from a normal process), do not patch Codex files.
- Keep the helper cheap: no `Runtime.enable` (console flood), no JSON parsing of CDP replies, no WMI in the loop.
  `Page.enable` stays: without it the injected script is not re-added after Codex reloads its window.
- Page input goes through `ConvertFrom-CodexSwitcherMessage`. Only masked emails reach the page. The injected
  script builds DOM with `createElement` only (tests enforce this).
- Never drop a login that is not saved (`Clear-CodexLiveAuth` refuses). Sync the live `auth.json` into its account
  before replacing it.
- `.ps1` / `.psm1` files stay ASCII (Windows PowerShell 5.1 reads BOM-less UTF-8 as ANSI). Remember that
  `ConvertFrom-Json` on 5.1 emits a JSON array as one object in a pipeline: assign it first.
- Never commit `auth.json`, the `accounts` folder or logs. Run `tests/Run-All.ps1` after edits.
