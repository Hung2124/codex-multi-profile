# Claude Code & MCP Workspace Isolation Guide

`codex-multi-profile` v2.0 provides programmatic and CLI primitives for developers and open-source maintainers who work across multiple **Claude Code** (`~/.claude`), **Model Context Protocol (`.mcp.json`)**, and **OpenAI Codex** (`~/.codex`) environments.

## 1. Auditing `.mcp.json` Before Switching Profiles

When switching between an Enterprise SSO repository and a public Open-Source repository, `.mcp.json` files can inadvertently expose plaintext API keys or bind to non-loopback HTTP/SSE endpoints.

Run the static auditor in CI or pre-commit hooks:

```bash
npx codex-multi-profile mcp-audit .mcp.json
```

### Checks Performed
- **`HARDCODED_SECRET_ENV` (`error`)**: Detects plaintext tokens (`sk-ant-*`, `ghp_*`, `xoxb-*`, or sensitive `*_KEY` / `*_TOKEN` values) that are not using `${VAR}` environment variable interpolation.
- **`INSECURE_REMOTE_MCP_ENDPOINT` (`error`)**: Flags unencrypted `http://` MCP server URLs bound to non-loopback hosts.
- **`REMOTE_MCP_ENDPOINT` (`warning`)**: Highlights external `https://` MCP endpoints unless `--allow-remote` is passed.
- **`SHELL_WRAPPER_COMMAND` (`warning`)**: Warns when an MCP server spawns `bash -c`, `sh -c`, or `powershell -Command` instead of a direct binary or package entrypoint.

## 2. Managing Isolated `~/.claude` and `~/.codex` Profiles

Use `WorkspaceProfileStore` to snapshot and activate isolated agent settings (`model`, `permissions`, `.mcp.json`) without cross-contaminating credentials:

```javascript
const { WorkspaceProfileStore } = require("codex-multi-profile");

const store = new WorkspaceProfileStore();

// Save an Open-Source Maintainer profile for Claude Code
store.saveProfile("oss-maintainer", {
  agent: "claude",
  settings: {
    model: "claude-sonnet-4-5",
    permissions: {
      allow: ["Read", "Edit", "Bash(npm test)", "Bash(git status)"]
    }
  }
});

// Activate the profile atomically
store.activateProfile("oss-maintainer", {
  agent: "claude",
  workspaceDir: process.cwd()
});
```

## 3. Synchronizing `CLAUDE.md` and `AGENTS.md`

Maintainers who use both **Claude Code** and **OpenAI Codex** can keep their repository instructions aligned from a single source of truth:

```bash
npx codex-multi-profile sync-docs .
```

## 4. Generating Hardened `.mcp.json` Manifests

Use `composeMcpConfig` to scaffold a clean `.mcp.json` manifest that enforces `${VAR}` secret interpolation:

```javascript
const { composeMcpConfig, auditMcpConfig } = require("codex-multi-profile");

const manifest = composeMcpConfig(["github", "filesystem", "postgres"]);
console.assert(auditMcpConfig(manifest).valid === true);
```
