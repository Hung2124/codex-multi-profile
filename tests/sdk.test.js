"use strict";

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const {
  auditMcpConfig,
  parseAgentMarkdown,
  renderAgentMarkdown,
  syncWorkspaceInstructions,
  normalizeProfileSlug,
  maskEmailAddress,
  WorkspaceProfileStore,
  listMcpPresets,
  composeMcpConfig
} = require("../index");

// 1. Slug normalization & email masking
assert.strictEqual(normalizeProfileSlug("Enterprise SSO #1"), "enterprise-sso-1");
assert.strictEqual(normalizeProfileSlug("Công việc Đại học"), "cong-viec-dai-hoc");
assert.throws(() => normalizeProfileSlug("!!!"), /Invalid profile name/);
assert.strictEqual(maskEmailAddress("maintainer@open-tooling.dev"), "ma***@open-tooling.dev");

// 2. MCP Security & Workspace Isolation Auditor
const cleanMcp = {
  mcpServers: {
    filesystem: {
      command: "npx",
      args: ["-y", "@modelcontextprotocol/server-filesystem", "./src"],
      env: {
        GITHUB_PERSONAL_ACCESS_TOKEN: "${GITHUB_PERSONAL_ACCESS_TOKEN}"
      }
    },
    localBridge: {
      url: "http://127.0.0.1:3111/mcp"
    }
  }
};
const cleanRes = auditMcpConfig(cleanMcp);
assert.strictEqual(cleanRes.valid, true);
assert.strictEqual(cleanRes.serverCount, 2);
assert.strictEqual(cleanRes.findings.length, 0);

const riskyMcp = {
  mcpServers: {
    leakedProd: {
      command: "node",
      args: ["server.js"],
      env: {
        ANTHROPIC_API_KEY: "sk-ant-api03-hardcodedsecretvalue123456"
      }
    },
    remoteInsecure: {
      url: "http://external-mcp.example.com:8080/sse"
    }
  }
};
const riskyRes = auditMcpConfig(riskyMcp);
assert.strictEqual(riskyRes.valid, false);
assert.ok(riskyRes.findings.some(f => f.code === "HARDCODED_SECRET_ENV"));
assert.ok(riskyRes.findings.some(f => f.code === "INSECURE_REMOTE_MCP_ENDPOINT"));

// 3. CLAUDE.md <-> AGENTS.md Instruction Bridge
const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), "cmp-sdk-test-"));
try {
  const wsDir = path.join(tmpRoot, "workspace");
  fs.mkdirSync(wsDir, { recursive: true });
  fs.writeFileSync(
    path.join(wsDir, "CLAUDE.md"),
    [
      "# CLAUDE.md",
      "",
      "Workspace rules for multi-profile AI coding agents.",
      "",
      "## Architecture Invariants",
      "",
      "- Keep `.mcp.json` secrets interpolated via environment variables.",
      "- Run `npm test` before opening a pull request.",
      "",
      "## Testing",
      "",
      "- Execute `node ./tests/sdk.test.js` and `./tests/Run-All.ps1`."
    ].join("\n"),
    "utf8"
  );

  const syncRes = syncWorkspaceInstructions(wsDir, { direction: "claude-to-codex" });
  assert.strictEqual(syncRes.updated, true);
  assert.strictEqual(syncRes.sectionCount, 2);
  assert.ok(fs.existsSync(path.join(wsDir, "AGENTS.md")));

  const parsedAgents = parseAgentMarkdown(fs.readFileSync(path.join(wsDir, "AGENTS.md"), "utf8"));
  assert.strictEqual(parsedAgents.title, "AGENTS.md");
  assert.strictEqual(parsedAgents.sections.length, 2);
  assert.strictEqual(parsedAgents.sections[0].heading, "Architecture Invariants");

  const reRendered = renderAgentMarkdown(parsedAgents, { target: "claude" });
  assert.ok(reRendered.startsWith("# CLAUDE.md"));

  // 4. Cross-platform WorkspaceProfileStore (Claude Code & Codex)
  const store = new WorkspaceProfileStore({
    storeRoot: path.join(tmpRoot, "store"),
    claudeHome: path.join(tmpRoot, "claude-home"),
    codexHome: path.join(tmpRoot, "codex-home")
  });

  store.saveProfile("Enterprise Work", {
    agent: "claude",
    settings: { model: "claude-sonnet-4-5", permissions: { allow: ["Read", "Edit"] } },
    mcpConfig: cleanMcp
  });

  store.saveProfile("OSS Maintainer", {
    agent: "claude",
    settings: { model: "claude-opus-4-6", permissions: { allow: ["Read", "Edit", "Bash(npm test)"] } }
  });

  const listed = store.listProfiles("claude");
  assert.strictEqual(listed.length, 2);
  assert.strictEqual(listed[0].slug, "enterprise-work");
  assert.strictEqual(listed[0].hasMcpConfig, true);
  assert.strictEqual(listed[1].slug, "oss-maintainer");

  const act = store.activateProfile("Enterprise Work", { agent: "claude", workspaceDir: wsDir });
  assert.strictEqual(act.copiedSettings, true);
  assert.strictEqual(act.copiedMcp, true);
  assert.ok(fs.existsSync(path.join(tmpRoot, "claude-home", "settings.json")));
  assert.ok(fs.existsSync(path.join(wsDir, ".mcp.json")));
} finally {
  fs.rmSync(tmpRoot, { recursive: true, force: true });
}

console.log("OK: SDK tests passed (MCP auditor, CLAUDE.md <-> AGENTS.md bridge, WorkspaceProfileStore).");

// 5. MCP Presets & Composition Audit
const presets = listMcpPresets();
assert.ok(presets.includes("github") && presets.includes("postgres") && presets.includes("slack"));
const composed = composeMcpConfig(["github", "filesystem", "slack"]);
const composedAudit = auditMcpConfig(composed);
assert.strictEqual(composedAudit.valid, true);
assert.strictEqual(composedAudit.serverCount, 3);
