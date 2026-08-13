# Contributing

PRs that encode a **verified Windows Codex Desktop** behavior are welcome. Please keep changes small.

## Rules

1. Do not add API keys, `auth.json`, or account emails to the repo or to fixtures.
2. Write files Codex will parse with UTF-8 **without BOM**.
3. Keep `SKILL.md` under ~500 lines. Put long explanations in `docs/`.
4. Launch paths must keep using a `.cmd` wrapper for `CODEX_HOME`. Do not "simplify" to `Start-Process` alone.
5. Run the local checks:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Invoke-ParseCheck.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\ConvertTo-ProfileKey.Tests.ps1
```

## Scope

In scope: AuthSwap, ShareLive junctions, Store clone, shortcuts, the agent skill.

Out of scope: unofficial API proxies, harvesting stars, or automating ChatGPT sign-in.
