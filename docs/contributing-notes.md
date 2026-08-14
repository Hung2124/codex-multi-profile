# Contributor notes

## Why AuthSwap exists

Codex Desktop on Windows often ignores a second `CODEX_HOME`. The process that actually authenticates ChatGPT still reads `%USERPROFILE%\.codex\auth.json`. AuthSwap puts the secondary token in that path for the duration of a clone window, then restores the main backup.

## Invariants (do not break)

1. Launch through a `.cmd` with `set CODEX_HOME=...` — never `Start-Process` alone for the clone.
2. Entry point is `ChatGPT.exe` from a local clone under `%LOCALAPPDATA%\CodexParallelDesktop\versions`, never `WindowsApps`.
3. `CODEX_ELECTRON_USER_DATA_PATH` and `--user-data-dir` must be the same profile root.
4. On close / Codex Main, only save profile auth when active email ≠ main backup email.
5. Any user-visible or on-disk log that mentions accounts must go through `Hide-AuthEmail`.
6. Write `config.toml` and generated scripts with UTF-8 **without BOM**.

## Suggested PR sizes

Prefer one concern per PR/commit: launcher fix, test, docs, or tooling. Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-All.ps1
```
