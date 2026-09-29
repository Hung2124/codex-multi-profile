# Contributing

PRs that encode a **verified Windows Codex Desktop** behavior are welcome. Keep changes small.

## Rules

1. Do not add API keys, `auth.json`, or account emails to the repo or to fixtures. Tests use fake JWTs (`alt@example.com`).
2. Write files Codex will parse with UTF-8 **without BOM** (`Write-Utf8NoBom`).
3. Keep `SKILL.md` under ~500 lines. Put long explanations in `docs/`.
4. Start the Store Codex only through `Start-CodexStore`; never clone or patch `ChatGPT.exe`.
5. Keep `.ps1` / `.psm1` files ASCII (Windows PowerShell 5.1 reads BOM-less UTF-8 as ANSI).
6. Read [AGENTS.md](AGENTS.md) and [docs/architecture.md](docs/architecture.md) for the rules that keep switching safe.
7. Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-All.ps1
```

8. Changed how the menu looks? Regenerate the README screenshots (made-up accounts, headless Edge):

```powershell
node tools/screenshots/capture.mjs
```

## Scope

In scope: the account store, the avatar-menu switcher, starting the Store Codex, the installer and shortcuts, the CLI and agent skill, and their tests.

Out of scope: unofficial API proxies, automating ChatGPT sign-in, shipping tokens, a Go mux, asar/ChatGPT.exe patchers, or quota-bypass features.
