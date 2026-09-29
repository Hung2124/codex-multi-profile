// README screenshots from mock.html (made-up accounts, real switcher-inject.js), rendered by headless Edge.
//   node tools/screenshots/capture.mjs
// Writes docs/images/accounts-menu.png (English) and accounts-menu-vi.png (Vietnamese).
import { spawn } from 'node:child_process';
import { mkdirSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const repo = resolve(here, '..', '..');
const out = join(repo, 'docs', 'images');
mkdirSync(out, { recursive: true });
const port = 9555;
const profile = mkdtempSync(join(tmpdir(), 'cmp-shots-'));
const edge = process.env.EDGE || 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';
const browser = spawn(edge, ['--headless=new', '--disable-gpu', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`,
  '--hide-scrollbars', '--force-color-profile=srgb', 'about:blank'], { stdio: 'ignore' });
const sleep = ms => new Promise(r => setTimeout(r, ms));

async function page() {
  for (let i = 0; i < 50; i++) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
      const p = list.find(t => t.type === 'page');
      if (p) { return p; }
    } catch { }
    await sleep(200);
  }
  throw new Error('headless Edge did not start');
}

const target = await page();
const ws = new WebSocket(target.webSocketDebuggerUrl);
let id = 0; const pend = new Map();
ws.onmessage = e => { const m = JSON.parse(e.data); if (pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id); } };
const call = (method, params = {}) => new Promise(r => { const i = ++id; pend.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
const ev = async x => (await call('Runtime.evaluate', { expression: x, returnByValue: true })).result.result.value;
await new Promise(r => ws.onopen = r);
await call('Emulation.setDeviceMetricsOverride', { width: 760, height: 720, deviceScaleFactor: 2, mobile: false });

for (const [lang, file] of [['en', 'accounts-menu.png'], ['vi', 'accounts-menu-vi.png']]) {
  await call('Page.navigate', { url: pathToFileURL(join(here, 'mock.html')).href + '?lang=' + lang });
  let ok = false;
  for (let i = 0; i < 50 && !ok; i++) { await sleep(150); ok = await ev("!!document.querySelector('[data-codex-multi-profile=accounts]')"); }
  if (!ok) { throw new Error('Accounts section was not injected'); }
  await sleep(400);
  const r = await ev("(() => { const b = document.querySelector('[role=menu]').getBoundingClientRect(); return { x: 0, y: Math.max(0, b.top - 24), w: b.right + 24, h: innerHeight - Math.max(0, b.top - 24) }; })()");
  const shot = await call('Page.captureScreenshot', { format: 'png', clip: { x: r.x, y: r.y, width: r.w, height: r.h, scale: 1 } });
  writeFileSync(join(out, file), Buffer.from(shot.result.data, 'base64'));
  console.log('wrote', join('docs', 'images', file));
  if (lang !== 'en') { continue; }
  // Add account dialog: click the "Add account" row (just above the section's bottom divider) and type a name.
  const add = await ev("(() => { const b = document.querySelector('[data-codex-multi-profile=accounts]').getBoundingClientRect(); return [b.left + 60, b.bottom - 26]; })()");
  for (const type of ['mousePressed', 'mouseReleased']) { await call('Input.dispatchMouseEvent', { type, x: add[0], y: add[1], button: 'left', clickCount: 1 }); }
  await sleep(500);
  await call('Input.insertText', { text: 'Side Project' });
  await sleep(300);
  const dlg = await call('Page.captureScreenshot', { format: 'png' });
  writeFileSync(join(out, 'add-account.png'), Buffer.from(dlg.result.data, 'base64'));
  console.log('wrote', join('docs', 'images', 'add-account.png'));
}
ws.close();
browser.kill();
await sleep(500);
try { rmSync(profile, { recursive: true, force: true }); } catch { }
