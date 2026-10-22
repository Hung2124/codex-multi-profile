#!/usr/bin/env node
"use strict";

const path = require("path");
const { spawnSync } = require("child_process");
const {
  getInstallRoot,
  getAccountsScriptPath,
  runCodexAccounts,
  auditMcpFile,
  syncWorkspaceInstructions,
  WorkspaceProfileStore
} = require("./index");

const rawArgs = process.argv.slice(2);

if (rawArgs.includes("--help") || rawArgs.includes("-h")) {
  console.log([
    "codex-multi-profile — Multi-Workspace Profile Router & MCP Isolation Toolkit for Claude Code and OpenAI Codex",
    "",
    "Cross-Platform Commands (Claude Code, MCP & Codex):",
    "  npx codex-multi-profile mcp-audit [path]         Audit .mcp.json / Claude Code MCP server security & token exposure",
    "  npx codex-multi-profile sync-docs [dir]          Synchronize CLAUDE.md <-> AGENTS.md instructions across a repo",
    "  npx codex-multi-profile profiles [claude|codex]  List isolated Claude Code (~/.claude) or Codex (~/.codex) profiles",
    "",
    "Windows Desktop Commands (Microsoft Store Codex App):",
    "  npx codex-multi-profile install                  Install or update the Windows Store Codex workspace helper",
    "  npx codex-multi-profile list [--json]            List saved workspace profiles and active status",
    "  npx codex-multi-profile status                   Show Store app, local CDP bridge, and active workspace status",
    "  npx codex-multi-profile save <name>              Save the currently active workspace profile",
    "  npx codex-multi-profile switch <name>            Switch active workspace profile (2-3s hot reload)",
    "  npx codex-multi-profile rename <old> <new>       Rename a saved workspace profile",
    "  npx codex-multi-profile remove <name>            Remove a saved workspace profile",
    "  npx codex-multi-profile lang <auto|vi|en>        Set workspace menu language",
    "",
    `Profile store root: ${getInstallRoot()}`
  ].join("\n"));
  process.exit(0);
}

if (rawArgs.includes("--version") || rawArgs.includes("-v")) {
  const pkg = require("./package.json");
  console.log(pkg.version);
  process.exit(0);
}

const cmd = (rawArgs[0] || "list").toLowerCase();

if (cmd === "mcp-audit") {
  const targetFile = path.resolve(rawArgs[1] || ".mcp.json");
  try {
    const res = auditMcpFile(targetFile, { allowRemoteHttp: rawArgs.includes("--allow-remote") });
    if (rawArgs.includes("--json")) {
      console.log(JSON.stringify(res, null, 2));
    } else {
      console.log(`Audited ${res.serverCount} MCP server(s) in ${targetFile}: ${res.valid ? "PASS" : "FAIL"}`);
      for (const f of res.findings) {
        console.log(`  [${f.severity.toUpperCase()}] (${f.code}) ${f.server}: ${f.message}`);
      }
    }
    process.exit(res.valid ? 0 : 1);
  } catch (err) {
    console.error(`Error auditing MCP config at ${targetFile}: ${err.message}`);
    process.exit(1);
  }
}

if (cmd === "sync-docs") {
  const dir = path.resolve(rawArgs[1] || ".");
  const dryRun = rawArgs.includes("--dry-run");
  const res = syncWorkspaceInstructions(dir, { dryRun });
  if (rawArgs.includes("--json")) {
    console.log(JSON.stringify(res, null, 2));
  } else if (res.action === "none") {
    console.log(`No CLAUDE.md or AGENTS.md found in ${dir}.`);
  } else {
    console.log(
      `${dryRun ? "[DRY-RUN] " : ""}Synced (${res.action}): ${res.sectionCount} section(s) -> ${path.basename(res.targetFile)} (updated=${res.updated})`
    );
  }
  process.exit(0);
}

if (cmd === "profiles") {
  const agent = (rawArgs[1] || "claude").toLowerCase() === "codex" ? "codex" : "claude";
  const store = new WorkspaceProfileStore();
  const list = store.listProfiles(agent);
  if (rawArgs.includes("--json")) {
    console.log(JSON.stringify(list, null, 2));
  } else if (list.length === 0) {
    console.log(`No saved ${agent} configuration profiles in ${store.getProfilesDir(agent)}.`);
  } else {
    for (const p of list) {
      console.log(`${p.slug}\tagent=${p.agent}\tmcp=${p.hasMcpConfig}\thash=${p.settingsHash || "none"}`);
    }
  }
  process.exit(0);
}

if (cmd === "install" || cmd === "setup") {
  const installCmd = "irm https://raw.githubusercontent.com/Hung2124/codex-multi-profile/main/install.ps1 | iex";
  const res = spawnSync("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", installCmd], {
    stdio: "inherit"
  });
  process.exit(res.status ?? 0);
}

const mapped = [];
if (cmd === "list") {
  mapped.push("list");
  if (rawArgs.includes("--json")) mapped.push("-Json");
} else if (cmd === "status") {
  mapped.push("status");
} else if (cmd === "save" && rawArgs[1]) {
  mapped.push("save", "-Name", rawArgs[1]);
} else if (cmd === "switch" && rawArgs[1]) {
  mapped.push("switch", "-Name", rawArgs[1]);
} else if (cmd === "rename" && rawArgs[1] && rawArgs[2]) {
  mapped.push("rename", "-Name", rawArgs[1], "-NewName", rawArgs[2]);
} else if (cmd === "remove" && rawArgs[1]) {
  mapped.push("remove", "-Name", rawArgs[1]);
} else if (cmd === "lang" && rawArgs[1]) {
  mapped.push("lang", "-Name", rawArgs[1]);
} else {
  mapped.push(...rawArgs);
}

process.exit(runCodexAccounts(mapped));
