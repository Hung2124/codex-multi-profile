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
  },
  slack: {
    command: "npx",
    args: ["-y", "@modelcontextprotocol/server-slack"],
    env: {
      SLACK_BOT_TOKEN: "${SLACK_BOT_TOKEN}",
      SLACK_TEAM_ID: "${SLACK_TEAM_ID}"
    }
  },
  sentry: {
    command: "npx",
    args: ["-y", "@modelcontextprotocol/server-sentry"],
    env: {
      SENTRY_AUTH_TOKEN: "${SENTRY_AUTH_TOKEN}"
    }
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

/**
 * Builds a complete `.mcp.json` configuration object from a list of preset names.
 *
 * @param {string[]} presetNames
 * @returns {{ mcpServers: Record<string, object> }}
 */
function composeMcpConfig(presetNames = []) {
  const mcpServers = {};
  for (const name of presetNames) {
    const preset = getMcpPreset(name);
    if (!preset) {
      throw new Error(`Unknown MCP preset: "${name}"`);
    }
    mcpServers[String(name).toLowerCase().trim()] = preset;
  }
  return { mcpServers };
}

module.exports.composeMcpConfig = composeMcpConfig;
