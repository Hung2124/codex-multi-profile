# Support

## Before opening an issue

1. Update:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Update-CodexMultiProfile.ps1
```

2. Run diagnostics (emails are masked):

```powershell
$root = "$env:LOCALAPPDATA\CodexParallelDesktop"
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action doctor
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action status
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action processes
```

3. If you attach a log, redact it first:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\Redact-LaunchTrace.ps1"
```

## Do not paste

- `auth.json`, tokens, or refresh credentials
- Full screenshots of the ChatGPT account email if you can avoid it
- Unredacted absolute paths under your user profile when a redacted log is enough

## Where to ask

- Bugs / wrong-account / Access Denied → [GitHub Issues](https://github.com/Hung2124/codex-multi-profile/issues)
- Official Codex product bugs → [openai/codex](https://github.com/openai/codex)

This project is unofficial and Windows-only.
