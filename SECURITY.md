# Security

This project keeps a saved copy of `%USERPROFILE%\.codex\auth.json` per ChatGPT account under
`%LOCALAPPDATA%\CodexMultiProfile\accounts\` and copies one of them back into `~\.codex` when you switch.
It also starts the Store Codex with the Chrome DevTools protocol on `127.0.0.1` (see
[docs/architecture.md](docs/architecture.md#security-notes)).

## Do not

- Open an issue, PR, or gist that includes `auth.json`, `id_token`, or refresh tokens
- Commit or share anything under `%LOCALAPPDATA%\CodexMultiProfile\accounts\`
- Use this on a PC where untrusted programs run under your Windows account (they could reach the local DevTools port)

`codex-accounts.log` is written locally and **masks** ChatGPT emails (`al***@example.com`).

## Report privately

Email the maintainer via the GitHub profile on this repository, or open a GitHub Security advisory if the repo has that enabled.

If a token leaked, revoke the ChatGPT session and sign in again.
