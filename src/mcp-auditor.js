"use strict";

const fs = require("fs");
const path = require("path");

const SECRET_ENV_PATTERNS = [
  /^(ANTHROPIC|OPENAI|CLAUDE|CODEX|GITHUB|AWS|GCP|AZURE|SLACK|STRIPE|SUPABASE|DATABASE)_.*(KEY|TOKEN|SECRET|PASSWORD)$/i,
  /^sk-[a-zA-Z0-9_-]{16,}$/,
  /^gh[pousr]_[a-zA-Z0-9]{20,}$/,
  /^xox[baprs]-[a-zA-Z0-9-]{10,}$/
];

const DANGEROUS_BINARIES = new Set(["curl", "wget", "nc", "ncat", "powershell", "pwsh", "cmd", "sh", "bash"]);

/**
 * Audits a parsed MCP configuration object (`.mcp.json` or `claude_desktop_config.json`)
 * for security and workspace-isolation risks.
 *
 * @param {object} config - Parsed JSON object containing `mcpServers`.
 * @param {object} [options] - Audit options.
 * @param {boolean} [options.allowRemoteHttp=false] - Whether non-loopback HTTP/SSE URLs are permitted.
 * @returns {{ valid: boolean, serverCount: number, findings: Array<{ server: string, severity: 'error'|'warning', code: string, message: string }> }}
 */
function auditMcpConfig(config, options = {}) {
  const allowRemoteHttp = Boolean(options.allowRemoteHttp);
  const findings = [];

  if (!config || typeof config !== "object") {
    return {
      valid: false,
      serverCount: 0,
      findings: [{ server: "<root>", severity: "error", code: "INVALID_CONFIG", message: "Configuration must be a JSON object." }]
    };
  }

  const servers = config.mcpServers && typeof config.mcpServers === "object" ? config.mcpServers : {};
  const serverNames = Object.keys(servers);

  for (const name of serverNames) {
    const srv = servers[name];
    if (!srv || typeof srv !== "object") {
      findings.push({
        server: name,
        severity: "error",
        code: "INVALID_SERVER_ENTRY",
        message: `Server "${name}" definition must be an object.`
      });
      continue;
    }

    // 1. Check transport URL if HTTP/SSE
    if (typeof srv.url === "string" && srv.url.trim() !== "") {
      try {
        const parsed = new URL(srv.url);
        const isLoopback =
          parsed.hostname === "localhost" ||
          parsed.hostname === "127.0.0.1" ||
          parsed.hostname === "::1" ||
          parsed.hostname === "[::1]";
        if (!isLoopback && !allowRemoteHttp) {
          findings.push({
            server: name,
            severity: parsed.protocol === "https:" ? "warning" : "error",
            code: parsed.protocol === "https:" ? "REMOTE_MCP_ENDPOINT" : "INSECURE_REMOTE_MCP_ENDPOINT",
            message: `Server "${name}" connects to non-loopback endpoint (${parsed.origin}). Verify workspace data boundaries.`
          });
        }
      } catch {
        findings.push({
          server: name,
          severity: "error",
          code: "INVALID_SERVER_URL",
          message: `Server "${name}" has an invalid URL: ${srv.url}`
        });
      }
    }

    // 2. Check command & args for shell injection or unrestricted execution
    if (typeof srv.command === "string") {
      const baseCmd = path.basename(srv.command).replace(/\.(exe|cmd|bat)$/i, "").toLowerCase();
      const args = Array.isArray(srv.args) ? srv.args.map(String) : [];

      if (DANGEROUS_BINARIES.has(baseCmd) && args.some(a => a === "-c" || a === "/c" || a === "-Command" || a.includes("|"))) {
        findings.push({
          server: name,
          severity: "warning",
          code: "SHELL_WRAPPER_COMMAND",
          message: `Server "${name}" invokes a raw shell wrapper (${baseCmd}). Prefer direct package or binary entrypoints.`
        });
      }
    }

    // 3. Check environment variables for hardcoded plaintext tokens
    if (srv.env && typeof srv.env === "object") {
      for (const [envKey, envVal] of Object.entries(srv.env)) {
        const strVal = String(envVal ?? "");
        const usesInterpolation = strVal.startsWith("${") || strVal.startsWith("$env:");
        if (usesInterpolation || strVal.length === 0) continue;

        const keyLooksSensitive = SECRET_ENV_PATTERNS[0].test(envKey);
        const valLooksLikeToken = SECRET_ENV_PATTERNS.slice(1).some(rx => rx.test(strVal));

        if (valLooksLikeToken || (keyLooksSensitive && strVal.length >= 12)) {
          findings.push({
            server: name,
            severity: "error",
            code: "HARDCODED_SECRET_ENV",
            message: `Server "${name}" contains a hardcoded credential in env.${envKey}. Use environment variable expansion (\${${envKey}}) instead.`
          });
        }
      }
    }
  }

  const hasErrors = findings.some(f => f.severity === "error");
  return {
    valid: !hasErrors,
    serverCount: serverNames.length,
    findings
  };
}

/**
 * Loads and audits an MCP config file from disk.
 *
 * @param {string} filePath - Path to `.mcp.json` or `settings.json`.
 * @param {object} [options] - Audit options.
 */
function auditMcpFile(filePath, options = {}) {
  const raw = fs.readFileSync(filePath, "utf8");
  const parsed = JSON.parse(raw);
  return auditMcpConfig(parsed, options);
}

module.exports = {
  auditMcpConfig,
  auditMcpFile
};
