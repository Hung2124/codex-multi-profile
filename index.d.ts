export interface McpAuditFinding {
  server: string;
  severity: "error" | "warning";
  code: string;
  message: string;
}

export interface McpAuditResult {
  valid: boolean;
  serverCount: number;
  findings: McpAuditFinding[];
}

export interface McpAuditOptions {
  allowRemoteHttp?: boolean;
}

export interface AgentSection {
  heading: string;
  level: number;
  body: string;
}

export interface ParsedAgentMarkdown {
  title: string | null;
  preamble: string;
  sections: AgentSection[];
}

export interface SyncInstructionOptions {
  direction?: "claude-to-codex" | "codex-to-claude" | "auto";
  dryRun?: boolean;
}

export interface SyncInstructionResult {
  action: string;
  sourceFile: string | null;
  targetFile: string | null;
  sectionCount: number;
  updated: boolean;
}

export interface ProfileSummary {
  slug: string;
  agent: string;
  updatedAt: string;
  hasMcpConfig: boolean;
  settingsHash: string | null;
}

export declare class WorkspaceProfileStore {
  storeRoot: string;
  claudeHome: string;
  codexHome: string;
  constructor(options?: { storeRoot?: string; claudeHome?: string; codexHome?: string });
  getProfilesDir(agent?: "claude" | "codex"): string;
  listProfiles(agent?: "claude" | "codex"): ProfileSummary[];
  saveProfile(
    name: string,
    payload?: { agent?: "claude" | "codex"; settings?: Record<string, unknown>; mcpConfig?: Record<string, unknown> }
  ): { slug: string; agent: string; path: string };
  activateProfile(
    name: string,
    options?: { agent?: "claude" | "codex"; workspaceDir?: string }
  ): { slug: string; agent: string; copiedSettings: boolean; copiedMcp: boolean };
}

export declare function getInstallRoot(): string;
export declare function getAccountsScriptPath(): string;
export declare function runCodexAccounts(args?: string[]): number;
export declare function auditMcpConfig(config: Record<string, unknown>, options?: McpAuditOptions): McpAuditResult;
export declare function auditMcpFile(filePath: string, options?: McpAuditOptions): McpAuditResult;
export declare function parseAgentMarkdown(markdown: string): ParsedAgentMarkdown;
export declare function renderAgentMarkdown(
  doc: ParsedAgentMarkdown,
  options?: { target?: "claude" | "codex"; includeSyncBanner?: boolean }
): string;
export declare function syncWorkspaceInstructions(workspaceDir: string, options?: SyncInstructionOptions): SyncInstructionResult;
export declare function normalizeProfileSlug(name: string): string;
export declare function maskEmailAddress(email: string): string;

export declare const MCP_PRESETS: Record<string, Record<string, unknown>>;
export declare function getMcpPreset(name: string): Record<string, unknown> | null;
export declare function listMcpPresets(): string[];
export declare function composeMcpConfig(presetNames?: string[]): { mcpServers: Record<string, unknown> };
