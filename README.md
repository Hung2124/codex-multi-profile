# Codex Multi-Profile

Windows helper for **OpenAI Codex Desktop**: extra ChatGPT logins, one shared workspace.

The Store app only keeps one `~\.codex\auth.json`. A second `CODEX_HOME` often **does not work** — the app-server still reads the main token and you land on the wrong account. This repo swaps the token the app actually reads (**AuthSwap**), then restores the main account when the profile window closes.

> Unofficial. Not affiliated with OpenAI. Windows + Codex Desktop (Microsoft Store) only.

## What you get

- **codex1 / codex2 / …** — each profile has its own ChatGPT login
- **ShareLive** — sessions, skills, MCP, memories, and projects stay in `~\.codex`
- **Codex Main** shortcut — put the original account back, then open the Store app
- **Agent skill** — drop `SKILL.md` into Codex or Cursor so the agent follows the same launch rules

```
Desktop "codex1"
        │
        ▼
Launch-CodexProfile.ps1
        │  backup ~/.codex/auth.json  →  auth.json.__main__
        │  copy profiles/codex1/auth.json  →  ~/.codex/auth.json
        │  start cloned ChatGPT.exe --user-data-dir=profiles\codex1
        ▼
watcher (on close)
        │  save secondary token back to the profile
        │  restore auth.json.__main__
        ▼
main account is intact
```

## Install

1. Install [Codex Desktop](https://chatgpt.com/codex) from the Microsoft Store and sign in once (this is the **main** account).
2. Clone and run the installer **in Windows PowerShell** (not from inside a running Codex window if you can avoid it):

```powershell
git clone https://github.com/Hung2124/codex-multi-profile.git
cd codex-multi-profile
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-CodexMultiProfile.ps1
```

3. Use the new Desktop shortcuts:
   - **Codex1** — secondary account (first run asks you to sign in)
   - **Codex Main** — restore the original account and open Store Codex
   - **Codex Profiles** — list / create another profile

Close one Codex UI before opening the other.

## Usage

```powershell
$root = "$env:LOCALAPPDATA\CodexParallelDesktop"

powershell -NoProfile -ExecutionPolicy Bypass -File "$root\Launch-CodexProfile.ps1" -Name codex1
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\Launch-CodexMain.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action new -Name codex2
powershell -NoProfile -ExecutionPolicy Bypass -File "$root\CodexProfile.ps1" -Action list
```

## Agent skill

After install, the skill is copied to:

- `%USERPROFILE%\.codex\skills\codex-multi-profile\`
- `%USERPROFILE%\.cursor\skills\codex-multi-profile\`

Or copy `SKILL.md` + `scripts\` yourself. The skill tells Codex/Cursor **not** to launch `Codex.exe`, **not** to use `WindowsApps`, and **not** to `Start-Process` without a cmd wrapper.

## Safety

| Does | Does not |
|---|---|
| Copies `auth.json` **locally** between `~\.codex` and `profiles\<name>` | Upload tokens, log passwords, or set a permanent `CODEX_HOME` |
| Clones `ChatGPT.exe` out of the Store package so it can start | Run the Store binary in-place (Access Denied) |
| Restores the main account when the profile exits | Touch `~\.codex` history/skills except the auth swap |

Do not commit `auth.json`, `*.bak`, or `launch-trace.log` (the log can contain emails).

## Uninstall

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Uninstall-CodexMultiProfile.ps1
# add -PurgeProfiles to delete local profile auth copies too
```

`~\.codex` is never deleted.

## Docs

- [Architecture](docs/architecture.md) — why AuthSwap exists
- [Troubleshooting](docs/troubleshooting.md) — wrong account, Access Denied, BOM, poisoned auth
- [Contributing](CONTRIBUTING.md)

## License

MIT. See [LICENSE](LICENSE).

## Tiếng Việt

Codex Desktop trên Windows chỉ giữ một `~\.codex\auth.json`. Đặt `CODEX_HOME` thứ hai thường **không** đổi được acc — app vẫn đọc token acc chính.

Repo này **AuthSwap**: lúc mở profile thì chép token acc phụ vào `~\.codex\auth.json`, lúc đóng thì restore acc chính. Session / skill / MCP vẫn dùng chung.

Cài:

```powershell
git clone https://github.com/Hung2124/codex-multi-profile.git
cd codex-multi-profile
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-CodexMultiProfile.ps1
```

Dùng shortcut **Codex1** (acc phụ) hoặc **Codex Main** (acc gốc). Không mở hai cái cùng lúc.
