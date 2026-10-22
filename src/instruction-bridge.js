"use strict";

const fs = require("fs");
const path = require("path");

/**
 * Parses markdown headings and sections from a `CLAUDE.md` or `AGENTS.md` instruction file.
 *
 * @param {string} markdown
 * @returns {{ title: string|null, preamble: string, sections: Array<{ heading: string, level: number, body: string }> }}
 */
function parseAgentMarkdown(markdown) {
  const normalized = String(markdown ?? "").replace(/\r\n/g, "\n");
  const lines = normalized.split("\n");

  let title = null;
  const preambleLines = [];
  const sections = [];
  let current = null;

  for (const line of lines) {
    const h1 = /^#\s+(.+)$/.exec(line);
    if (h1 && title === null && !current) {
      title = h1[1].trim();
      continue;
    }

    const hMatch = /^(#{2,4})\s+(.+)$/.exec(line);
    if (hMatch) {
      if (current) {
        current.body = current.lines.join("\n").trim();
        delete current.lines;
        sections.push(current);
      }
      current = {
        heading: hMatch[2].trim(),
        level: hMatch[1].length,
        lines: []
      };
      continue;
    }

    if (current) {
      current.lines.push(line);
    } else {
      preambleLines.push(line);
    }
  }

  if (current) {
    current.body = current.lines.join("\n").trim();
    delete current.lines;
    sections.push(current);
  }

  return {
    title,
    preamble: preambleLines.join("\n").trim(),
    sections
  };
}

/**
 * Renders a parsed instruction document back into clean Markdown for the target agent (`claude` or `codex`).
 *
 * @param {{ title: string|null, preamble: string, sections: Array<{ heading: string, level: number, body: string }> }} doc
 * @param {{ target: 'claude'|'codex', includeSyncBanner?: boolean }} [options]
 * @returns {string}
 */
function renderAgentMarkdown(doc, options = {}) {
  const target = options.target || "claude";
  const defaultTitle = target === "claude" ? "CLAUDE.md" : "AGENTS.md";
  const effectiveTitle =
    !doc.title || doc.title === "CLAUDE.md" || doc.title === "AGENTS.md" ? defaultTitle : doc.title;
  const out = [`# ${effectiveTitle}`];

  if (options.includeSyncBanner) {
    out.push(
      "",
      `<!-- Synchronized by codex-multi-profile (${target === "claude" ? "CLAUDE.md <- AGENTS.md" : "AGENTS.md <- CLAUDE.md"}) -->`
    );
  }

  if (doc.preamble) {
    out.push("", doc.preamble);
  }

  for (const sec of doc.sections || []) {
    const hashes = "#".repeat(Math.min(Math.max(sec.level || 2, 2), 4));
    out.push("", `${hashes} ${sec.heading}`);
    if (sec.body) {
      out.push("", sec.body);
    }
  }

  return out.join("\n").trimEnd() + "\n";
}

/**
 * Synchronizes shared engineering instructions between `CLAUDE.md` (Claude Code) and `AGENTS.md` (OpenAI Codex)
 * in a workspace directory.
 *
 * @param {string} workspaceDir - Path to repository root.
 * @param {{ direction?: 'claude-to-codex'|'codex-to-claude'|'auto', dryRun?: boolean }} [options]
 * @returns {{ action: string, sourceFile: string|null, targetFile: string|null, sectionCount: number, updated: boolean }}
 */
function syncWorkspaceInstructions(workspaceDir, options = {}) {
  const claudePath = path.join(workspaceDir, "CLAUDE.md");
  const agentsPath = path.join(workspaceDir, "AGENTS.md");
  const hasClaude = fs.existsSync(claudePath);
  const hasAgents = fs.existsSync(agentsPath);

  if (!hasClaude && !hasAgents) {
    return {
      action: "none",
      sourceFile: null,
      targetFile: null,
      sectionCount: 0,
      updated: false
    };
  }

  let direction = options.direction || "auto";
  if (direction === "auto") {
    if (hasClaude && !hasAgents) {
      direction = "claude-to-codex";
    } else if (hasAgents && !hasClaude) {
      direction = "codex-to-claude";
    } else {
      const claudeMtime = fs.statSync(claudePath).mtimeMs;
      const agentsMtime = fs.statSync(agentsPath).mtimeMs;
      direction = claudeMtime >= agentsMtime ? "claude-to-codex" : "codex-to-claude";
    }
  }

  const sourceFile = direction === "claude-to-codex" ? claudePath : agentsPath;
  const targetFile = direction === "claude-to-codex" ? agentsPath : claudePath;
  const targetAgent = direction === "claude-to-codex" ? "codex" : "claude";

  const sourceRaw = fs.readFileSync(sourceFile, "utf8");
  const parsed = parseAgentMarkdown(sourceRaw);
  const rendered = renderAgentMarkdown(
    {
      ...parsed,
      title: targetAgent === "claude" ? "CLAUDE.md" : "AGENTS.md"
    },
    { target: targetAgent, includeSyncBanner: true }
  );

  const existingTarget = fs.existsSync(targetFile) ? fs.readFileSync(targetFile, "utf8").replace(/\r\n/g, "\n") : null;
  const updated = existingTarget !== rendered;

  if (updated && !options.dryRun) {
    fs.writeFileSync(targetFile, rendered, "utf8");
  }

  return {
    action: direction,
    sourceFile,
    targetFile,
    sectionCount: parsed.sections.length,
    updated
  };
}

module.exports = {
  parseAgentMarkdown,
  renderAgentMarkdown,
  syncWorkspaceInstructions
};
