import { syncWorkspaceInstructions } from '../index.js';

const res = syncWorkspaceInstructions(process.cwd(), { dryRun: true });
console.log('Instruction sync check:', res);
