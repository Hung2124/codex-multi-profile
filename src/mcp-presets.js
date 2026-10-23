"use strict";

/**
 * Curated, security-hardened MCP server templates for Claude Code (.mcp.json)
 * using strict environment variable interpolation.
 */
const MCP_PRESETS = {
  github: {
    command: "npx",
    args: ["-y", "@modelcontextprotocol/server-github"],
    env: {
      GITHUB_PERSONAL_ACCESS_TOKEN: "${GITHUB_PERSONAL_ACCESS_TOKEN}"
    }
  },
  filesystem: {
    command: "npx",
    args: ["-y", "@modelcontextprotocol/server-filesystem", "."]
  },
  postgres: {
    command: "npx",
    args: ["-y", "@modelcontextprotocol/server-postgres", "${DATABASE_URL}"]
  },
  memory: {
    command: "npx",
    args: ["-y", "@modelcontextprotocol/server-memory"]
  }
};

function getMcpPreset(name) {
  const key = String(name || "").toLowerCase().trim();
  return MCP_PRESETS[key] ? JSON.parse(JSON.stringify(MCP_PRESETS[key])) : null;
}

function listMcpPresets() {
  return Object.keys(MCP_PRESETS);
}

module.exports = {
  MCP_PRESETS,
  getMcpPreset,
  listMcpPresets
};
