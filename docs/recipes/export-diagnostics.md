# Recipe: export a safe diagnostic bundle

For GitHub issues without pasting secrets.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexParallelDesktop\CodexProfile.ps1" -Action diagnostics
```

The script writes a temp folder with:

- `meta.json`, `doctor.json`, `status.json`, `processes.json`, `sync-check.json`
- `launch-trace.redacted.txt` (emails and home paths scrubbed)

`auth.json` is never copied. Still skim the files before attaching.
