import { composeMcpConfig, auditMcpConfig } from '../index.js';

const manifest = composeMcpConfig(['github', 'filesystem', 'postgres']);
const report = auditMcpConfig(manifest);
if (!report.valid) {
  console.error('MCP Audit Failed:', report.findings);
  process.exit(1);
}
console.log('Verified', report.serverCount, 'MCP servers with 0 findings.');
