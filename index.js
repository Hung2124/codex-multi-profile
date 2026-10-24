"use strict";

const { spawnSync } = require("child_process");
const path = require("path");
const os = require("os");
const fs = require("fs");

const { auditMcpConfig, auditMcpFile } = require("./src/mcp-auditor");
const { parseAgentMarkdown, renderAgentMarkdown, syncWorkspaceInstructions } = require("./src/instruction-bridge");
const { normalizeProfileSlug, maskEmailAddress, WorkspaceProfileStore } = require("./src/profile-manager");

function getInstallRoot() {
  if (process.platform === "win32") {
    const localAppData = process.env.LOCALAPPDATA || path.join(os.homedir(), "AppData", "Local");
    return path.join(localAppData, "CodexMultiProfile");
  }
  return path.join(process.env.XDG_CONFIG_HOME || path.join(os.homedir(), ".config"), "codex-multi-profile");
}

function getAccountsScriptPath() {
  return path.join(getInstallRoot(), "CodexAccounts.ps1");
}

function runCodexAccounts(args = ["list"]) {
  if (process.platform !== "win32") {
    throw new Error("Native Windows Store Codex app integration requires Windows 10/11. Use `profiles`, `mcp-audit`, or `sync-docs` on macOS/Linux.");
  }
  const scriptPath = getAccountsScriptPath();
  if (!fs.existsSync(scriptPath)) {
    const installCmd = "irm https://raw.githubusercontent.com/Hung2124/codex-multi-profile/main/install.ps1 | iex";
    const res = spawnSync("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", installCmd], {
      stdio: "inherit"
    });
    return res.status ?? 0;
  }
  const res = spawnSync(
    "powershell.exe",
    ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", scriptPath, ...args],
    { stdio: "inherit" }
  );
  return res.status ?? 0;
}

module.exports = {
  getInstallRoot,
  getAccountsScriptPath,
  runCodexAccounts,
  auditMcpConfig,
  auditMcpFile,
  parseAgentMarkdown,
  renderAgentMarkdown,
  syncWorkspaceInstructions,
  normalizeProfileSlug,
  maskEmailAddress,
  WorkspaceProfileStore
};
