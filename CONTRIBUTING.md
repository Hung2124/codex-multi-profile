# Contributing

PRs that encode a **verified Windows Codex Desktop** behavior are welcome. Keep changes small.

## Rules

1. Do not add API keys, `auth.json`, or account emails to the repo or to fixtures. Tests use fake JWTs (`alt@example.com`).
2. Write files Codex will parse with UTF-8 **without BOM** (`Write-Utf8NoBom`).
3. Keep `SKILL.md` under ~500 lines. Put long explanations in `docs/`.
4. Launch paths must keep using a `.cmd` wrapper for `CODEX_HOME`. Do not "simplify" to `Start-Process` alone.
5. Copy `CodexMultiProfile.psm1` next to every launcher. Launchers import it from `$PSScriptRoot`.
6. Read [docs/contributing-notes.md](docs/contributing-notes.md) for AuthSwap invariants.
7. Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-All.ps1
```

## Scope

In scope: AuthSwap, Store clone, shortcuts, the agent skill, doctor/repair/diagnostics, the Windows subscription router (pool/stick/route/depleted), tests for the poison guard and router.

Out of scope: unofficial API proxies, automating ChatGPT sign-in, shipping tokens, a Go mux, asar/ChatGPT.exe patchers, or quota-bypass features.
