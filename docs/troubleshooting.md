# Troubleshooting

Start with:

```powershell
$root = "$env:LOCALAPPDATA\CodexParallelDesktop"
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action doctor
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\Redact-LaunchTrace.ps1"
```

Default log (emails are masked by the launcher; still prefer the redactor before pasting):

`%LOCALAPPDATA%\CodexParallelDesktop\launch-trace.log`

## Stale AuthSwap lock

`doctor` reports `stale-swap-lock` when `.authswap-active` exists but no clone is running.

Preferred fix:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexParallelDesktop\CodexProfile.ps1" -Action repair
```

`repair` restores `~\.codex\auth.json` from `auth.json.__main__` (if present) and clears `.authswap-active`. It refuses while a clone is still running unless you pass `-Force`.

Fallback: run `Launch-CodexMain.ps1`, which also restores main auth and clears the lock.

## Wrong account in the profile window

The UI shows the main ChatGPT account even though you launched `codex1`.

1. Close every Codex window.
2. Run `doctor` (preferred) or compare masked status:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexParallelDesktop\CodexProfile.ps1" -Action status
```

3. Launch with `Launch-CodexProfile.ps1`, not a raw `Start-Process` on `ChatGPT.exe`.
4. If profile auth equals main, the launcher bootstraps a fresh login. Sign in with the **secondary** account, then close the window so the watcher can save it.

## Access Denied / path empty / exit code 1

| Symptom | Cause | Fix |
|---|---|---|
| Access Denied | Started from `WindowsApps` | Let `CodexProfile.ps1 -Action new` clone into `CodexParallelDesktop\versions` |
| `Join-Path` empty string | `InstallLocation` was blank | Use an existing clone folder; do not join a null Store path |
| Process exits 1 immediately | Launched `Codex.exe` | Use `ChatGPT.exe` |

## Poisoned secondary auth

You opened **Codex Main** while Codex1 was still running. The main token got written into `profiles\codex1\auth.json`.

- Current scripts refuse to save when active email == `auth.json.__main__`.
- If it already happened: close everything, delete the poisoned `profiles\codex1\auth.json` (keep `auth.json.secondary.bak` if it still has the secondary email), launch Codex1, sign in again.
- `doctor` flags this as `poisoned-profile`.

## `Ignoring late userData path change`

`CODEX_ELECTRON_USER_DATA_PATH` and `--user-data-dir` were different. Both must be the profile **root**.

## `config.toml` ignored

File was saved with a UTF-8 BOM (PowerShell 5.1 `Set-Content -Encoding UTF8`). Recreate it with `[IO.File]::WriteAllText(..., UTF8Encoding $false)` or let Codex rewrite it. `doctor` flags `config-bom`.

## Two windows, one account

Do not run Store Codex and a cloned profile together. AuthSwap owns `~\.codex\auth.json` for one process at a time. Use **Codex Main** to restore, then open Store Codex. `doctor` flags `dual-window`.
