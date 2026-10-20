"use strict";

const { spawnSync } = require("child_process");
const path = require("path");
const os = require("os");
const fs = require("fs");

function getInstallRoot() {
  const localAppData = process.env.LOCALAPPDATA || path.join(os.homedir(), "AppData", "Local");
  return path.join(localAppData, "CodexMultiProfile");
}

function getAccountsScriptPath() {
  return path.join(getInstallRoot(), "CodexAccounts.ps1");
}

function runCodexAccounts(args = ["list"]) {
  if (process.platform !== "win32") {
    throw new Error("codex-multi-profile requires Windows 10/11 with the Microsoft Store Codex app.");
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
  runCodexAccounts
};
