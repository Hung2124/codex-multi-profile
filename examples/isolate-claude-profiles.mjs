import { WorkspaceProfileStore } from '../index.js';

const store = new WorkspaceProfileStore();
console.log('Saved Claude Code profiles:', store.listProfiles('claude'));
