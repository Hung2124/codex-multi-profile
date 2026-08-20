# AGENTS.md

This repository is a **Windows-only** Codex Desktop multi-account helper.

- Read `SKILL.md` before changing launch behavior.
- Never commit `auth.json`, backups, or `launch-trace.log`.
- Do not replace the `.cmd` env wrapper with `Start-Process` alone.
- Write `config.toml` without a UTF-8 BOM.
- Run `tests/Run-All.ps1` after script edits.

- Router (`pool` / `stick` / `route` / `depleted`) is opt-in and must stay one-window AuthSwap. Do not add a mux or ChatGPT.exe patcher.
- Layer and ChatGPT Web models stay off by default.
