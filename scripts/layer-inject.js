/* Codex Multi-Profile desktop layer.
 * Injected via CDP loopback (127.0.0.1) into the *cloned* ChatGPT.exe only.
 * Never patch app.asar or the Microsoft Store package.
 */
(function () {
  if (window.__codexMultiProfileLayer) { return; }
  window.__codexMultiProfileLayer = true;

  function ensureStyle() {
    if (document.getElementById('cmp-layer-style')) { return; }
    var style = document.createElement('style');
    style.id = 'cmp-layer-style';
    style.textContent = [
      '#cmp-layer-badge{position:fixed;z-index:2147483647;top:8px;right:8px;',
      'padding:3px 8px;font:12px/1.4 "Segoe UI",sans-serif;background:#0a7;color:#fff;',
      'border-radius:4px;pointer-events:none;opacity:.92;}',
      'main,[class*="transcript"],[class*="conversation"],[data-testid*="conversation"]{',
      'max-width:min(1200px,96vw)!important;width:100%;}'
    ].join('');
    (document.head || document.documentElement).appendChild(style);
  }

  function ensureBadge() {
    if (document.getElementById('cmp-layer-badge')) { return; }
    var host = document.body || document.documentElement;
    if (!host) { return; }
    var el = document.createElement('div');
    el.id = 'cmp-layer-badge';
    el.textContent = 'Layer · clone';
    el.title = 'Codex Multi-Profile layer (cloned ChatGPT.exe, CDP 127.0.0.1)';
    host.appendChild(el);
  }

  function keepDetailsOpen() {
    var nodes = document.querySelectorAll('details');
    for (var i = 0; i < nodes.length; i++) {
      if (!nodes[i].open) { nodes[i].open = true; }
    }
  }

  function tick() {
    ensureStyle();
    ensureBadge();
    keepDetailsOpen();
  }

  var obs = new MutationObserver(tick);
  try { obs.observe(document.documentElement, { childList: true, subtree: true }); } catch (e) {}
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', tick);
  }
  tick();
})();
