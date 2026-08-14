# Recipe: clear a stale AuthSwap lock

## Symptoms

- Store Codex opens the secondary account
- `doctor` reports `stale-swap-lock`
- `.authswap-active` exists under `%LOCALAPPDATA%\CodexParallelDesktop`

## Fix

1. Close every Codex / ChatGPT window.
2. Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexParallelDesktop\CodexProfile.ps1" -Action repair
```

3. Confirm with `status` or `doctor`. Main should show your primary masked email and `SwapActive` should be empty.

## If repair refuses

A clone is still running. Close Codex1, or only if you understand the risk:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexParallelDesktop\CodexProfile.ps1" -Action repair -Force
```
