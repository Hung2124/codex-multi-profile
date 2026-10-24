"use strict";

const fs = require("fs");
const path = require("path");
const os = require("os");
const crypto = require("crypto");

/**
 * Normalizes a human-readable profile name into a safe slug (`enterprise`, `oss-maint`, etc.).
 *
 * @param {string} name
 * @returns {string}
 */
function normalizeProfileSlug(name) {
  const slug = String(name ?? "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/\u0111/g, "d")
    .replace(/\u0110/g, "d")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 64);

  if (!slug) {
    throw new Error(`Invalid profile name: "${name}"`);
  }
  return slug;
}

/**
 * Masks an email address (`alice.smith@example.com` -> `al***@example.com`) so logs and UI snapshots
 * never expose raw identity strings.
 *
 * @param {string} email
 * @returns {string}
 */
function maskEmailAddress(email) {
  const raw = String(email ?? "").trim();
  const atIdx = raw.indexOf("@");
  if (atIdx <= 0) return "***";
  const local = raw.slice(0, atIdx);
  const domain = raw.slice(atIdx + 1);
  const prefix = local.slice(0, Math.min(2, local.length));
  return `${prefix}***@${domain}`;
}

/**
 * Cross-platform Workspace Profile Manager for Claude Code (`~/.claude`) and OpenAI Codex (`~/.codex`)
 * configuration & MCP server isolation.
 */
class WorkspaceProfileStore {
  /**
   * @param {{ storeRoot?: string, claudeHome?: string, codexHome?: string }} [options]
   */
  constructor(options = {}) {
    const home = os.homedir();
    this.storeRoot =
      options.storeRoot ||
      (process.platform === "win32"
        ? path.join(process.env.LOCALAPPDATA || path.join(home, "AppData", "Local"), "CodexMultiProfile")
        : path.join(process.env.XDG_CONFIG_HOME || path.join(home, ".config"), "codex-multi-profile"));
    this.claudeHome = options.claudeHome || path.join(home, ".claude");
    this.codexHome = options.codexHome || path.join(home, ".codex");
  }

  getProfilesDir(agent = "claude") {
    return path.join(this.storeRoot, `${agent}-profiles`);
  }

  /**
   * Lists saved configuration profiles for the specified agent (`claude` or `codex`).
   *
   * @param {'claude'|'codex'} [agent='claude']
   * @returns {Array<{ slug: string, agent: string, updatedAt: string, hasMcpConfig: boolean, settingsHash: string|null }>}
   */
  listProfiles(agent = "claude") {
    const dir = this.getProfilesDir(agent);
    if (!fs.existsSync(dir)) return [];

    const entries = fs.readdirSync(dir, { withFileTypes: true });
    const result = [];

    for (const entry of entries) {
      if (!entry.isDirectory()) continue;
      const slug = entry.name;
      const profDir = path.join(dir, slug);
      const settingsFile = path.join(profDir, "settings.json");
      const mcpFile = path.join(profDir, ".mcp.json");

      let settingsHash = null;
      let updatedAt = new Date(0).toISOString();

      if (fs.existsSync(settingsFile)) {
        const buf = fs.readFileSync(settingsFile);
        settingsHash = crypto.createHash("sha256").update(buf).digest("hex").slice(0, 12);
        updatedAt = fs.statSync(settingsFile).mtime.toISOString();
      }

      result.push({
        slug,
        agent,
        updatedAt,
        hasMcpConfig: fs.existsSync(mcpFile),
        settingsHash
      });
    }

    return result.sort((a, b) => a.slug.localeCompare(b.slug));
  }

  /**
   * Saves a named Claude Code or Codex configuration profile (`settings.json` and optional `.mcp.json`).
   *
   * @param {string} name - Profile name (`enterprise`, `oss-maintainer`, `research`).
   * @param {{ agent?: 'claude'|'codex', settings?: object, mcpConfig?: object }} [payload]
   */
  saveProfile(name, payload = {}) {
    const agent = payload.agent || "claude";
    const slug = normalizeProfileSlug(name);
    const profDir = path.join(this.getProfilesDir(agent), slug);
    fs.mkdirSync(profDir, { recursive: true });

    if (payload.settings && typeof payload.settings === "object") {
      fs.writeFileSync(path.join(profDir, "settings.json"), JSON.stringify(payload.settings, null, 2) + "\n", "utf8");
    } else if (agent === "claude") {
      const liveSettings = path.join(this.claudeHome, "settings.json");
      if (fs.existsSync(liveSettings)) {
        fs.copyFileSync(liveSettings, path.join(profDir, "settings.json"));
      }
    }

    if (payload.mcpConfig && typeof payload.mcpConfig === "object") {
      fs.writeFileSync(path.join(profDir, ".mcp.json"), JSON.stringify(payload.mcpConfig, null, 2) + "\n", "utf8");
    }

    return { slug, agent, path: profDir };
  }

  /**
   * Activates a saved profile by writing its isolated `settings.json` (and optional `.mcp.json` into a workspace).
   *
   * @param {string} name
   * @param {{ agent?: 'claude'|'codex', workspaceDir?: string }} [options]
   */
  activateProfile(name, options = {}) {
    const agent = options.agent || "claude";
    const slug = normalizeProfileSlug(name);
    const profDir = path.join(this.getProfilesDir(agent), slug);

    if (!fs.existsSync(profDir)) {
      throw new Error(`Profile "${slug}" not found for agent "${agent}".`);
    }

    const srcSettings = path.join(profDir, "settings.json");
    const targetHome = agent === "claude" ? this.claudeHome : this.codexHome;
    fs.mkdirSync(targetHome, { recursive: true });

    let copiedSettings = false;
    if (fs.existsSync(srcSettings)) {
      const dstSettings = path.join(targetHome, "settings.json");
      const tmpSettings = `${dstSettings}.tmp-${process.pid}`;
      fs.copyFileSync(srcSettings, tmpSettings);
      fs.renameSync(tmpSettings, dstSettings);
      copiedSettings = true;
    }

    let copiedMcp = false;
    const srcMcp = path.join(profDir, ".mcp.json");
    if (options.workspaceDir && fs.existsSync(srcMcp)) {
      const dstMcp = path.join(options.workspaceDir, ".mcp.json");
      const tmpMcp = `${dstMcp}.tmp-${process.pid}`;
      fs.copyFileSync(srcMcp, tmpMcp);
      fs.renameSync(tmpMcp, dstMcp);
      copiedMcp = true;
    }

    return { slug, agent, copiedSettings, copiedMcp };
  }
}

module.exports = {
  normalizeProfileSlug,
  maskEmailAddress,
  WorkspaceProfileStore
};
