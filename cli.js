#!/usr/bin/env node
"use strict";

const { getInstallRoot, getAccountsScriptPath, runCodexAccounts } = require("./index");
const { spawnSync } = require("child_process");

const rawArgs = process.argv.slice(2);

if (rawArgs.includes("--help") || rawArgs.includes("-h")) {
  console.log([
    "codex-multi-profile — Switch ChatGPT accounts in the Microsoft Store Codex app on Windows",
    "",
    "Usage:",
    "  npx codex-multi-profile install              Install or update Codex Multi-Profile",
    "  npx codex-multi-profile list [--json]        List saved accounts and active status",
    "  npx codex-multi-profile status               Show Store app, CDP helper, and active login status",
    "  npx codex-multi-profile save <name>          Save the currently signed-in account",
    "  npx codex-multi-profile switch <name>        Fast-switch to a saved account (2-3s)",
    "  npx codex-multi-profile rename <old> <new>   Rename a saved account",
    "  npx codex-multi-profile remove <name>        Remove a saved account",
    "  npx codex-multi-profile lang <auto|vi|en>    Set avatar menu language",
    "",
    `Install root: ${getInstallRoot()}`
  ].join("\n"));
  process.exit(0);
}

if (rawArgs.includes("--version") || rawArgs.includes("-v")) {
  const pkg = require("./package.json");
  console.log(pkg.version);
  process.exit(0);
}

const cmd = (rawArgs[0] || "list").toLowerCase();

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
