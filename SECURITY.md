# Security

This project launches a local clone of Codex Desktop and temporarily replaces
`%USERPROFILE%\.codex\auth.json` with a per-profile copy.

## Do not

- Open an issue, PR, or gist that includes `auth.json`, `id_token`, refresh tokens, or full `launch-trace.log`
- Commit files under `%LOCALAPPDATA%\CodexParallelDesktop\profiles\`
- Set a user-level `CODEX_HOME` that points at someone else's machine

## Report privately

Email the maintainer via the GitHub profile on this repository, or open a GitHub Security advisory if the repo has that enabled.

If a token leaked, revoke the ChatGPT session and sign in again.
