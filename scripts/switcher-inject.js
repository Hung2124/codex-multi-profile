/* Codex Multi-Profile - in-app account switcher.
 *
 * Injected over CDP loopback (127.0.0.1) into the Microsoft Store Codex main window by
 * Start-CodexAccounts.ps1. Never patches app.asar or any file of the Store package.
 *
 * Where it shows up:
 *   - Native: when the Codex sidebar account menu (avatar, bottom-left) opens, an
 *     "Accounts" section is added right under your identity row: saved accounts
 *     (click = switch), Add account, and rename / remove buttons on hover.
 *   - Fallback: if that avatar button cannot be found, a small account control with
 *     the same look sits bottom-left and opens the same menu.
 *   - Ctrl+Alt+A opens it from anywhere.
 *
 * Talks to the host through one CDP binding: window.cmpSwitcherBridge(jsonString).
 * The host answers with window.__cmpSwitcher.receive({kind, ...}).
 * Only masked emails ever reach this page. DOM is built node by node (no HTML strings,
 * Trusted Types safe) inside shadow roots, styled with Codex's own 26.9xx menu metrics.
 */
(function () {
  'use strict';
  if (window.__cmpSwitcher) { return; }

  var BINDING = 'cmpSwitcherBridge';
  var POS_KEY = 'cmpSwitcher.pos.v2';

  var I18N = {
    en: {
      accounts: 'Accounts',
      offline: 'Accounts offline',
      offlineHint: 'The account helper is not running. Open Codex from the Codex shortcut.',
      needsLogin: 'Sign-in needed',
      depleted: 'Out of quota',
      current: 'Current',
      add: 'Add account',
      remove: 'Remove',
      removeTip: 'Remove this account',
      renameTip: 'Rename',
      addTitle: 'Add account',
      addBody: 'Codex shows its sign-in screen. Sign in with the other ChatGPT account and it is saved under this name. Your current account stays in the list.',
      addLabel: 'Account name',
      addPlaceholder: 'e.g. work',
      addSaves: 'Saved as {key}',
      addBtn: 'Continue',
      adding: 'Opening sign-in...',
      cancel: 'Cancel',
      removeTitle: 'Remove {name}?',
      removeBody: 'This deletes the saved login for {name} on this PC. Chats, projects and settings in ~/.codex stay as they are. You can add it again any time.',
      removeBtn: 'Remove',
      removing: 'Removing...',
      renameTitle: 'Rename {name}',
      renameBtn: 'Save',
      renaming: 'Saving...',
      switching: 'Switching to {name}',
      switchingAdd: 'Opening sign-in for {name}',
      switchingSub: 'Just a few seconds.',
      switchFailed: 'The switch did not finish. Try again.',
      pendingTitle: 'Sign in for {name}',
      pendingBody: 'Sign in with the ChatGPT account you want to save as {name}.',
      pendingCancel: 'Cancel, go back',
      limitTitle: '{name} hit its usage limit',
      limitBody: 'Switch to {next} and keep going?',
      limitSwitch: 'Switch to {next}',
      dismiss: 'Not now',
      toast_added: 'Saved {detail}. You are now using it.',
      toast_removed: 'Removed {detail}.',
      toast_switched: 'Now using {detail}.',
      toast_renamed: 'Renamed to {detail}.',
      toast_exists: 'An account named {detail} already exists.',
      'toast_exists-as': 'That login is already saved as {detail}.',
      'toast_bad-name': 'Use letters, numbers and dashes.',
      'toast_already-active': 'You are already on {detail}.',
      'toast_add-failed': 'Could not add {detail}.',
      'toast_switch-failed': 'Could not switch to {detail}.',
      'toast_remove-failed': 'Could not remove {detail}. Switch to another account first.',
      'toast_rename-failed': 'Could not rename {detail}.',
      'toast_unknown-profile': 'That account no longer exists.',
      'toast_host-error': 'Something went wrong. See codex-accounts.log.',
      toast_generic: 'Request rejected ({code}).'
    },
    vi: {
      accounts: 'Tài khoản',
      offline: 'Chưa kết nối',
      offlineHint: 'Trình quản lý tài khoản chưa chạy. Mở Codex bằng shortcut Codex.',
      needsLogin: 'Cần đăng nhập lại',
      depleted: 'Hết lượt',
      current: 'Đang dùng',
      add: 'Thêm tài khoản',
      remove: 'Xoá',
      removeTip: 'Xoá tài khoản này',
      renameTip: 'Đổi tên',
      addTitle: 'Thêm tài khoản',
      addBody: 'Codex sẽ chuyển sang màn hình đăng nhập. Đăng nhập tài khoản ChatGPT kia, nó sẽ được lưu với tên này. Tài khoản hiện tại vẫn giữ trong danh sách.',
      addLabel: 'Tên tài khoản',
      addPlaceholder: 'vd: cong-viec',
      addSaves: 'Sẽ lưu thành {key}',
      addBtn: 'Tiếp tục',
      adding: 'Đang mở đăng nhập...',
      cancel: 'Huỷ',
      removeTitle: 'Xoá {name}?',
      removeBody: 'Thông tin đăng nhập đã lưu của {name} trên máy này sẽ bị xoá. Lịch sử chat, project và cài đặt trong ~/.codex vẫn giữ nguyên. Bạn có thể thêm lại bất cứ lúc nào.',
      removeBtn: 'Xoá',
      removing: 'Đang xoá...',
      renameTitle: 'Đổi tên {name}',
      renameBtn: 'Lưu',
      renaming: 'Đang lưu...',
      switching: 'Đang chuyển sang {name}',
      switchingAdd: 'Đang mở đăng nhập cho {name}',
      switchingSub: 'Chỉ mất vài giây.',
      switchFailed: 'Chuyển chưa xong. Thử lại nhé.',
      pendingTitle: 'Đăng nhập cho {name}',
      pendingBody: 'Đăng nhập tài khoản ChatGPT bạn muốn lưu thành {name}.',
      pendingCancel: 'Huỷ, quay lại',
      limitTitle: '{name} đã chạm giới hạn sử dụng',
      limitBody: 'Chuyển sang {next} để làm tiếp?',
      limitSwitch: 'Chuyển sang {next}',
      dismiss: 'Để sau',
      toast_added: 'Đã lưu {detail} và đang dùng nó.',
      toast_removed: 'Đã xoá {detail}.',
      toast_switched: 'Đang dùng {detail}.',
      toast_renamed: 'Đã đổi tên thành {detail}.',
      toast_exists: 'Đã có tài khoản tên {detail}.',
      'toast_exists-as': 'Tài khoản này đã được lưu với tên {detail}.',
      'toast_bad-name': 'Chỉ dùng chữ, số và gạch ngang.',
      'toast_already-active': 'Bạn đang dùng {detail} rồi.',
      'toast_add-failed': 'Không thêm được {detail}.',
      'toast_switch-failed': 'Không chuyển được sang {detail}.',
      'toast_remove-failed': 'Không xoá được {detail}. Chuyển sang tài khoản khác trước.',
      'toast_rename-failed': 'Không đổi tên được {detail}.',
      'toast_unknown-profile': 'Tài khoản đó không còn nữa.',
      'toast_host-error': 'Có lỗi xảy ra. Xem codex-accounts.log.',
      toast_generic: 'Yêu cầu bị từ chối ({code}).'
    }
  };

  // Codex's own limit notice ("You've hit your usage limit. ... try again at ...").
  // Kept narrow on purpose: chats about API rate limits must not trigger it.
  var LIMIT_RE = /(you(?:'|’)ve hit your usage limit|you have hit your usage limit|usage limit reached|đã đạt giới hạn sử dụng)/i;
  // Last row of the Codex account menu, in a few UI languages.
  var LOGOUT_RE = /^\s*(log ?out|sign ?out|đăng xuất|abmelden|se déconnecter|cerrar sesión|sair|esci|退出登录|登出|ログアウト|로그아웃)/i;

  var S = {
    state: null,
    modal: null,          // { kind: 'add'|'remove'|'rename', profile, value, busy, error }
    switching: null,      // { profile, add }
    switchTimer: 0,
    toast: null,          // { level, text, action }
    toastTimer: 0,
    menuOpen: false,      // fallback menu
    trigger: null,        // Codex's own account button
    triggerSeenAt: 0,
    triggerClickAt: 0,
    nativeMenu: null,     // open Codex account menu element
    sections: [],         // injected sections: { host, shadow, menu }
    flash: null,
    flashUntil: 0,
    limitHit: false,
    limitDismissedUntil: 0,
    startedAt: Date.now(),
    lastHello: 0,
    dragging: false,
    renderPending: false
  };

  /* ---------- basics ---------- */
  function lang() {
    var pref = S.state && S.state.lang;
    if (pref === 'vi' || pref === 'en') { return pref; }
    // Codex sets <html lang> to its UI language; navigator.language is the OS/Chromium default.
    var ui = (document.documentElement.lang || navigator.language || 'en').toLowerCase();
    return ui.indexOf('vi') === 0 ? 'vi' : 'en';
  }
  function t(key, vars) {
    var table = I18N[lang()] || I18N.en;
    var s = table[key];
    if (s === undefined) { s = I18N.en[key]; }
    if (s === undefined) { s = key; }
    if (vars) { Object.keys(vars).forEach(function (k) { s = s.split('{' + k + '}').join(String(vars[k])); }); }
    return s;
  }
  function send(msg) {
    var fn = window[BINDING];
    if (typeof fn !== 'function') { return false; }
    try { fn(JSON.stringify(msg)); return true; } catch (e) { return false; }
  }
  function connected() { return typeof window[BINDING] === 'function' && !!S.state; }
  function profiles() { return (S.state && S.state.profiles) || []; }
  function find(name) {
    var list = profiles();
    for (var i = 0; i < list.length; i++) { if (list[i].name === name) { return list[i]; } }
    return null;
  }
  function activeProfile() {
    var list = profiles();
    for (var i = 0; i < list.length; i++) { if (list[i].active) { return list[i]; } }
    return null;
  }
  // Current account first, then the rest in router order.
  function orderedProfiles() {
    var list = profiles().slice();
    var cur = list.filter(function (p) { return p.active; });
    return cur.concat(list.filter(function (p) { return !p.active; }));
  }
  function switchTargets() { return orderedProfiles().filter(function (p) { return !p.active; }); }
  function toKey(raw) {
    var s = String(raw || '').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/g, 'd').replace(/Đ/g, 'D');
    return s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 64);
  }
  // Sign-in screen for an account being added (Codex has no avatar there).
  function pendingAdd() { return !!(S.state && S.state.pending && !S.state.signedIn); }

  /* ---------- DOM helpers (createElement only) ---------- */
  function h(tag, props, kids) {
    var el = document.createElement(tag);
    if (props) {
      Object.keys(props).forEach(function (k) {
        var v = props[k];
        if (v === null || v === undefined || v === false) { return; }
        if (k === 'class') { el.className = v; }
        else if (k === 'text') { el.textContent = v; }
        else if (k.indexOf('on') === 0) { el.addEventListener(k.slice(2), v); }
        else { el.setAttribute(k, v === true ? '' : String(v)); }
      });
    }
    (kids || []).forEach(function (c) {
      if (c === null || c === undefined || c === false) { return; }
      el.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
    });
    return el;
  }
  var SVGNS = 'http://www.w3.org/2000/svg';
  var ICONS = {
    check: ['M4.5 10.5l3.5 3.5 7.5-8'],
    plus: ['M10 4.5v11M4.5 10h11'],
    trash: ['M4.5 6h11', 'M8 6V4.8c0-.4.3-.8.8-.8h2.4c.5 0 .8.4.8.8V6', 'M6 6l.6 8.7c.1.8.7 1.3 1.5 1.3h3.8c.8 0 1.4-.5 1.5-1.3L14 6'],
    pencil: ['M12.8 4.2l3 3L8 15H5v-3z', 'M11.3 5.7l3 3'],
    alert: ['M10 7.5v3.2', 'M10 13.4v.1', 'M8.7 3.8L2.9 14c-.6 1 .1 2.2 1.3 2.2h11.6c1.2 0 1.9-1.2 1.3-2.2L11.3 3.8c-.6-1-2-1-2.6 0z'],
    x: ['M5.5 5.5l9 9M14.5 5.5l-9 9'],
    chevron: ['M6.5 8.5L10 12l3.5-3.5']
  };
  function icon(name, size) {
    var svg = document.createElementNS(SVGNS, 'svg');
    svg.setAttribute('viewBox', '0 0 20 20');
    svg.setAttribute('width', String(size || 16));
    svg.setAttribute('height', String(size || 16));
    svg.setAttribute('fill', 'none');
    svg.setAttribute('stroke', 'currentColor');
    svg.setAttribute('stroke-width', '1.5');
    svg.setAttribute('stroke-linecap', 'round');
    svg.setAttribute('stroke-linejoin', 'round');
    svg.setAttribute('aria-hidden', 'true');
    ICONS[name].forEach(function (d) {
      var p = document.createElementNS(SVGNS, 'path');
      p.setAttribute('d', d);
      svg.appendChild(p);
    });
    return svg;
  }
  var PALETTE = ['#10a37f', '#6e56cf', '#e5484d', '#0090ff', '#d6409f', '#f76b15', '#12a594', '#8e4ec6', '#3e63dd', '#ad7f58'];
  function colorFor(name) {
    var x = 0;
    for (var i = 0; i < name.length; i++) { x = ((x << 5) - x + name.charCodeAt(i)) | 0; }
    return PALETTE[Math.abs(x) % PALETTE.length];
  }
  function avatar(name) {
    var n = name || '?';
    var el = h('span', { class: 'av', text: n.charAt(0).toUpperCase() });
    el.style.background = colorFor(n);
    return el;
  }
  function luminanceOf(color) {
    var m = color && color.match(/[\d.]+/g);
    if (!m || m.length < 3) { return null; }
    if (m.length >= 4 && parseFloat(m[3]) === 0) { return null; }
    if (/^okl/.test(color)) { return parseFloat(m[0]); }
    return (0.299 * m[0] + 0.587 * m[1] + 0.114 * m[2]) / 255;
  }
  function pageTheme() {
    var de = document.documentElement;
    var dt = (de.getAttribute('data-theme') || '') + ' ' + (de.className || '') + ' ' + ((document.body && document.body.className) || '');
    if (/\bdark\b/.test(dt)) { return 'dark'; }
    if (/\blight\b/.test(dt)) { return 'light'; }
    try {
      var cs = getComputedStyle(de).colorScheme;
      if (cs === 'dark' || cs === 'light') { return cs; }
      var lum = luminanceOf(getComputedStyle(document.body || de).backgroundColor);
      if (lum !== null) { return lum < 0.5 ? 'dark' : 'light'; }
    } catch (e) { }
    return (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) ? 'dark' : 'light';
  }
  function themeOf(el) {
    // Inside Codex's menu, its text colour tells us the theme.
    try {
      var lum = luminanceOf(getComputedStyle(el).color);
      if (lum !== null) { return lum > 0.5 ? 'dark' : 'light'; }
    } catch (e) { }
    return pageTheme();
  }

  /* ---------- styles (Codex 26.9xx metrics and tokens) ---------- */
  var TOKENS = [
    '.t-dark{--fg:#fff;--fg2:rgba(255,255,255,.7);--fg3:rgba(255,255,255,.5);--hover:rgba(255,255,255,.08);',
    '--line:rgba(255,255,255,.06);--border:rgba(255,255,255,.08);--border-heavy:rgba(255,255,255,.16);',
    '--menu-bg:rgba(45,45,45,.94);--menu-bg:oklab(0.297161 0.0000135154 0.00000594556 / 0.9);--ring:rgba(255,255,255,.082);',
    '--surface:#282828;--btn2:rgba(255,255,255,.05);--btn2h:rgba(255,255,255,.08);--pri-bg:#fff;--pri-fg:#0d0d0d;',
    '--danger:#ff6764;--danger-bg:#4d100e;--danger-bgh:rgba(255,103,100,.17);--warn:#ff8549;--focus:#339cff;--flash:rgba(51,156,255,.16)}',
    '.t-light{--fg:#1a1c1f;--fg2:#5d5d5d;--fg3:#8f8f8f;--hover:rgba(26,28,31,.05);',
    '--line:rgba(26,28,31,.06);--border:rgba(26,28,31,.08);--border-heavy:rgba(26,28,31,.12);',
    '--menu-bg:rgba(255,255,255,.94);--menu-bg:oklab(0.999994 0.0000455678 0.0000200868 / 0.9);--ring:rgba(26,28,31,.08);',
    '--surface:#fff;--btn2:rgba(26,28,31,.05);--btn2h:rgba(26,28,31,.08);--pri-bg:#1a1c1f;--pri-fg:#fff;',
    '--danger:#ba2623;--danger-bg:#ffd9d9;--danger-bgh:rgba(186,38,35,.17);--warn:#923b0f;--focus:#0068c7;--flash:rgba(0,104,199,.1)}'
  ].join('\n');

  var ROWS_CSS = [
    '*{box-sizing:border-box}',
    '.sec{display:flex;flex-direction:column;color:var(--fg);font-size:13px;font-weight:430;line-height:18.5714px}',
    '.head{display:flex;align-items:center;justify-content:space-between;height:26.5625px;padding:4px 8px;color:var(--fg2)}',
    '.head .k{font-size:12px;color:var(--fg3)}',
    '.list{display:flex;flex-direction:column;max-height:214px;overflow-y:auto;overscroll-behavior:contain}',
    '.list::-webkit-scrollbar{width:6px}.list::-webkit-scrollbar-thumb{background:var(--border-heavy);border-radius:6px}',
    '.row{position:relative;display:flex;align-items:center;gap:8px;width:100%;min-height:42.5625px;padding:5px 8px;',
    'border:0;border-radius:15px;background:transparent;color:inherit;font:inherit;text-align:left;cursor:pointer;outline:none;',
    'transition:background-color .12s}',
    '.row.one{min-height:28.5625px}',
    '.row:hover,.row:focus-visible{background:var(--hover)}',
    '.row:focus-visible{box-shadow:inset 0 0 0 1.5px var(--focus)}',
    '.row.cur{cursor:default}.row.cur:hover{background:transparent}',
    '.row.flash{animation:flash 1.8s ease-out}',
    '@keyframes flash{0%,35%{background:var(--flash)}100%{background:transparent}}',
    '.av{flex:none;width:18px;height:18px;border-radius:50%;display:inline-flex;align-items:center;justify-content:center;',
    'font-size:9.5px;font-weight:650;line-height:1;color:#fff}',
    '.av-ico{background:var(--btn2h);color:var(--fg)}',
    '.ico{flex:none;width:18px;display:inline-flex;justify-content:center;color:inherit}',
    '.txt{min-width:0;flex:1;display:flex;flex-direction:column}',
    '.nm{display:flex;align-items:center;gap:6px;min-width:0}',
    '.nm b{font-weight:inherit;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
    '.tag{flex:none;font-size:11px;line-height:16px;padding:0 6px;border-radius:999px;background:var(--btn2);color:var(--warn)}',
    '.em{font-size:12px;line-height:16px;color:var(--fg2);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
    '.end{flex:none;display:flex;align-items:center;gap:2px;margin-left:4px;color:var(--fg2)}',
    '.kbd{min-width:16px;text-align:right;font-size:13px;color:var(--fg3)}',
    '.chk{display:inline-flex;color:var(--fg)}',
    '.del{display:none;width:26px;height:26px;margin:-4px -4px -4px 0;border:0;border-radius:10px;background:transparent;',
    'color:var(--fg2);align-items:center;justify-content:center;cursor:pointer}',
    '.row:hover .del,.row:focus-within .del{display:inline-flex}.row:hover .kbd,.row:focus-within .kbd{display:none}',
    '.del:hover{color:var(--danger);background:var(--hover)}.ren{margin-right:0}.ren:hover{color:var(--fg)}',
    '.del:focus-visible{outline:2px solid var(--focus);outline-offset:-2px}',
    '.div{height:9px;padding:4px 8px}.div>span{display:block;height:1px;background:var(--line)}',
    '.off{padding:4px 8px 8px;font-size:12px;line-height:16px;color:var(--fg2)}'
  ].join('\n');

  var LAYER_CSS = [
    ':host{font-family:inherit}',
    '.root{font-size:13px;font-weight:430;line-height:18.5714px;color:var(--fg);-webkit-font-smoothing:antialiased}',
    /* fallback account control (same height/radius as the sidebar footer account button) */
    '.ctl{position:fixed;z-index:2147483600;display:flex;align-items:center;gap:8px;height:32px;padding:0 10px 0 7px;max-width:220px;',
    'border:0;border-radius:12.5px;background:var(--menu-bg);box-shadow:0 0 0 .5px var(--ring),0 4px 12px -4px rgba(0,0,0,.18);',
    'color:var(--fg);font:inherit;cursor:pointer;user-select:none;-webkit-app-region:no-drag}',
    '.ctl:hover{background:var(--surface)}.ctl:focus-visible{outline:2px solid var(--focus);outline-offset:-2px}',
    '.ctl .lbl{white-space:nowrap;overflow:hidden;text-overflow:ellipsis;font-weight:445}',
    '.ctl .chev{display:inline-flex;color:var(--fg2)}',
    '.ctl.dragging{cursor:grabbing}',
    /* fallback menu = Codex account menu shell (306px, radius 20, 4px inset) */
    '.menu{position:fixed;z-index:2147483646;width:306px;max-height:calc(100vh - 24px);overflow:hidden;display:flex;flex-direction:column;',
    'padding:4px;border-radius:20px;background:var(--menu-bg);-webkit-backdrop-filter:blur(24px);backdrop-filter:blur(24px);',
    'box-shadow:0 0 0 .5px var(--ring),0 8px 16px -4px rgba(0,0,0,.12);color:var(--fg);-webkit-app-region:no-drag;',
    'animation:menuin .12s cubic-bezier(.2,0,0,1)}',
    '@keyframes menuin{from{opacity:0;transform:translateY(4px)}to{opacity:1;transform:none}}',
    /* dialog = Codex dialog (compact width, radius 16, padding 16) */
    '.backdrop{position:fixed;inset:0;z-index:2147483647;display:flex;align-items:center;justify-content:center;padding:16px;',
    'background:rgba(0,0,0,.45);-webkit-app-region:no-drag;animation:fade .14s ease-out}',
    '@keyframes fade{from{opacity:0}to{opacity:1}}',
    '.dlg{width:min(400px,100%);padding:16px;border-radius:16px;border:.5px solid var(--border);background:var(--surface);color:var(--fg);',
    'box-shadow:0 0 0 .5px var(--border),0 8px 16px -4px rgba(0,0,0,.12),0 16px 32px -8px rgba(0,0,0,.19);outline:none;',
    'animation:enter .14s cubic-bezier(.2,0,0,1)}',
    '@keyframes enter{from{opacity:0;transform:scale(.98) translateY(4px)}to{opacity:1;transform:none}}',
    '.dlg h2{margin:0;font-size:18px;font-weight:600;line-height:28px}',
    '.dlg .desc{margin:4px 0 0;font-size:14px;line-height:18px;color:var(--fg2)}',
    '.dlg .body{margin-top:16px;display:flex;flex-direction:column;gap:6px}',
    '.dlg label{font-size:13px;line-height:18px;color:var(--fg2)}',
    '.field{height:36px;width:100%;padding:0 10px;border-radius:10px;border:1px solid var(--border-heavy);background:transparent;',
    'color:var(--fg);font:inherit;font-size:14px;outline:none}',
    '.field::placeholder{color:var(--fg3)}',
    '.field:focus{border-color:var(--focus);box-shadow:0 0 0 1px var(--focus)}',
    '.field.bad{border-color:var(--danger);box-shadow:0 0 0 1px var(--danger)}',
    '.hint{font-size:12px;line-height:16px;color:var(--fg2);min-height:16px}.hint.err{color:var(--danger)}',
    '.foot{margin-top:16px;display:flex;justify-content:flex-end;gap:8px}',
    '.btn{height:36px;padding:0 12px;border-radius:10px;border:1px solid transparent;background:var(--btn2);color:var(--fg);',
    'font:inherit;font-size:14px;font-weight:500;line-height:18px;cursor:pointer;display:inline-flex;align-items:center;gap:6px;white-space:nowrap;',
    'transition:background-color .12s,opacity .12s}',
    '.btn:hover{background:var(--btn2h)}',
    '.btn.pri{background:var(--pri-bg);color:var(--pri-fg)}.btn.pri:hover{opacity:.9}',
    '.btn.danger{background:var(--danger-bg);color:var(--danger)}.btn.danger:hover{background:var(--danger-bgh)}',
    '.btn.sm{height:28px;padding:0 10px;border-radius:8px;font-size:13px}',
    '.btn:disabled{opacity:.5;cursor:default}',
    '.btn:focus-visible{outline:2px solid var(--focus);outline-offset:1px}',
    '.bspin{width:14px;height:14px;border-radius:50%;border:2px solid currentColor;border-right-color:transparent;animation:sp .7s linear infinite}',
    /* switching card */
    '.card{display:flex;align-items:center;gap:12px;min-width:300px;padding:16px 18px;border-radius:16px;background:var(--surface);color:var(--fg);',
    'box-shadow:0 0 0 .5px var(--border),0 16px 32px -8px rgba(0,0,0,.25);animation:enter .14s cubic-bezier(.2,0,0,1)}',
    '.card .t1{font-size:14px;font-weight:500;line-height:18px}.card .t2{font-size:13px;line-height:18px;color:var(--fg2)}',
    '.spin{flex:none;width:18px;height:18px;border-radius:50%;border:2px solid var(--border-heavy);border-top-color:var(--fg);animation:sp .7s linear infinite}',
    '@keyframes sp{to{transform:rotate(360deg)}}',
    /* toast */
    '.toast{position:fixed;left:50%;bottom:24px;z-index:2147483647;transform:translateX(-50%);display:flex;align-items:center;gap:10px;',
    'max-width:min(480px,calc(100vw - 32px));padding:6px 6px 6px 12px;border-radius:14px;background:var(--surface);color:var(--fg);',
    'box-shadow:0 0 0 .5px var(--border),0 8px 16px -4px rgba(0,0,0,.12),0 16px 32px -8px rgba(0,0,0,.19);font-size:13px;line-height:18px;',
    'animation:toastin .16s cubic-bezier(.2,0,0,1)}',
    '@keyframes toastin{from{opacity:0;transform:translate(-50%,6px)}to{opacity:1;transform:translate(-50%,0)}}',
    '.toast .ti{display:inline-flex;color:var(--fg2)}.toast.error .ti{color:var(--danger)}',
    '.toast .tt{padding:4px 4px 4px 0}',
    '.x{flex:none;width:28px;height:28px;border:0;border-radius:8px;background:transparent;color:var(--fg2);display:inline-flex;align-items:center;justify-content:center;cursor:pointer}',
    '.x:hover{background:var(--btn2h);color:var(--fg)}',
    /* usage-limit card */
    '.limit{position:fixed;z-index:2147483645;left:12px;bottom:52px;width:300px;padding:12px;border-radius:16px;background:var(--surface);',
    'box-shadow:0 0 0 .5px var(--border),0 8px 16px -4px rgba(0,0,0,.12),0 16px 32px -8px rgba(0,0,0,.19);color:var(--fg);',
    'animation:enter .14s cubic-bezier(.2,0,0,1);-webkit-app-region:no-drag}',
    '.limit .t1{display:flex;gap:8px;align-items:center;font-weight:500}.limit .t1 span{display:inline-flex;color:var(--warn)}',
    '.limit .t2{margin-top:2px;color:var(--fg2)}',
    '.limit .foot{margin-top:12px}'
  ].join('\n');

  function adopt(shadow, css) {
    try {
      if ('adoptedStyleSheets' in shadow && typeof CSSStyleSheet === 'function') {
        var sheet = new CSSStyleSheet();
        sheet.replaceSync(css);
        shadow.adoptedStyleSheets = [sheet];
        return;
      }
    } catch (e) { }
    shadow.appendChild(h('style', { text: css }));
  }

  /* ---------- account rows (shared by the Codex menu section and the fallback menu) ---------- */
  function buildSection(opts) {
    var sec = h('div', { class: 'sec', role: 'group', 'aria-label': t('accounts') });
    sec.appendChild(h('div', { class: 'head' }, [h('span', { text: t('accounts') }), h('span', { class: 'k', text: (S.state && S.state.hotkey) || 'Ctrl+Alt+A' })]));
    if (!connected()) {
      sec.appendChild(h('div', { class: 'off', text: t('offlineHint') }));
      if (opts.divider) { sec.appendChild(h('div', { class: 'div' }, [h('span')])); }
      return sec;
    }
    var list = h('div', { class: 'list' });
    var n = 0;
    orderedProfiles().forEach(function (p) {
      var cur = !!p.active;
      var hint = null;
      if (!cur) { n += 1; if (n <= 9) { hint = String(n); } }
      var sub = p.needsLogin ? t('needsLogin') : p.account;
      var nameLine = h('span', { class: 'nm' }, [h('b', { text: p.name }), p.depleted ? h('span', { class: 'tag', text: t('depleted') }) : null]);
      var end = h('span', { class: 'end' });
      var ren = h('button', { class: 'del ren', type: 'button', title: t('renameTip'), 'aria-label': t('renameTip') + ' ' + p.name }, [icon('pencil', 16)]);
      ren.addEventListener('click', function (e) { e.preventDefault(); e.stopPropagation(); opts.onRename(p.name); });
      ren.addEventListener('pointerdown', function (e) { e.stopPropagation(); });
      end.appendChild(ren);
      if (cur) {
        end.appendChild(h('span', { class: 'chk', title: t('current') }, [icon('check', 16)]));
      } else {
        if (hint) { end.appendChild(h('span', { class: 'kbd', text: hint })); }
        var del = h('button', { class: 'del', type: 'button', title: t('removeTip'), 'aria-label': t('remove') + ' ' + p.name }, [icon('trash', 16)]);
        del.addEventListener('click', function (e) { e.preventDefault(); e.stopPropagation(); opts.onRemove(p.name); });
        del.addEventListener('pointerdown', function (e) { e.stopPropagation(); });
        end.appendChild(del);
      }
      var row = h('div', {
        class: 'row' + (cur ? ' cur' : '') + (S.flash === p.name && Date.now() < S.flashUntil ? ' flash' : ''),
        role: 'menuitemradio', 'aria-checked': cur ? 'true' : 'false', tabindex: cur ? '-1' : '0',
        title: cur ? t('current') : null, 'data-profile': p.name
      }, [avatar(p.name), h('span', { class: 'txt' }, [nameLine, h('span', { class: 'em', text: sub })]), end]);
      if (!cur) {
        row.addEventListener('click', function () { opts.onPick(p.name); });
        row.addEventListener('keydown', function (e) {
          if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); e.stopPropagation(); opts.onPick(p.name); }
          if (e.key === 'Delete') { e.preventDefault(); e.stopPropagation(); opts.onRemove(p.name); }
        });
      }
      list.appendChild(row);
    });
    sec.appendChild(list);
    var add = h('div', { class: 'row one', role: 'menuitem', tabindex: '0', 'data-add': 'true' }, [h('span', { class: 'ico' }, [icon('plus', 16)]), h('span', { class: 'txt', text: t('add') })]);
    add.addEventListener('click', function () { opts.onAdd(); });
    add.addEventListener('keydown', function (e) { if (e.key === 'Enter') { e.preventDefault(); e.stopPropagation(); opts.onAdd(); } });
    sec.appendChild(add);
    if (opts.extra) { opts.extra.forEach(function (x) { sec.appendChild(x); }); }
    if (opts.divider) { sec.appendChild(h('div', { class: 'div' }, [h('span')])); }
    return sec;
  }

  function sectionActions(closeFirst) {
    return {
      onPick: function (name) { closeFirst(); pickProfile(name); },
      onRemove: function (name) { closeFirst(); openModal({ kind: 'remove', profile: name }); },
      onAdd: function () { closeFirst(); openModal({ kind: 'add', value: '' }); },
      onRename: function (name) { closeFirst(); openModal({ kind: 'rename', profile: name, value: name }); }
    };
  }

  /* ---------- Codex's own account menu ---------- */
  function isOurs(node) {
    return !!(node && (node === layerHost || (node.closest && node.closest('[data-codex-multi-profile]'))));
  }

  function findTrigger() {
    var best = null, bestScore = 0;
    var vh = window.innerHeight;
    var nodes = document.querySelectorAll('button,[role="button"]');
    for (var i = 0; i < nodes.length; i++) {
      var b = nodes[i];
      if (isOurs(b)) { continue; }
      var r = b.getBoundingClientRect();
      if (r.width < 24 || r.height < 20 || r.height > 52 || r.left > 48 || r.bottom < vh - 72 || r.width > 420) { continue; }
      var score = 0;
      if (b.querySelector('img')) { score += 3; }
      if ((b.getAttribute('aria-haspopup') || '') === 'menu' || b.hasAttribute('aria-expanded')) { score += 2; }
      if (/account|profile|tài khoản/i.test((b.getAttribute('aria-label') || '') + ' ' + (typeof b.className === 'string' ? b.className : ''))) { score += 2; }
      if ((b.textContent || '').trim().length > 0) { score += 1; }
      if (score > bestScore) { best = b; bestScore = score; }
    }
    return bestScore >= 3 ? best : null;
  }

  function isAccountMenu(menu) {
    if (isOurs(menu)) { return false; }
    var r = menu.getBoundingClientRect();
    if (r.width < 120 || r.height < 40 || r.left > 420) { return false; }
    if (/account|tài khoản/i.test(menu.getAttribute('aria-label') || '')) { return true; }
    if (Date.now() - S.triggerClickAt < 2000) { return true; }
    var items = menu.querySelectorAll('[role="menuitem"]');
    return items.length >= 3 && LOGOUT_RE.test(items[items.length - 1].textContent || '');
  }

  function closeNativeMenu() {
    var menu = S.nativeMenu;
    if (!menu || !menu.isConnected) { return; }
    var esc = { key: 'Escape', code: 'Escape', keyCode: 27, which: 27, bubbles: true, cancelable: true, composed: true };
    try { menu.dispatchEvent(new KeyboardEvent('keydown', esc)); } catch (e) { }
    setTimeout(function () {
      if (menu.isConnected && menu.getBoundingClientRect().height > 0) {
        try { document.dispatchEvent(new KeyboardEvent('keydown', esc)); } catch (e) { }
      }
      setTimeout(function () {
        if (menu.isConnected && menu.getBoundingClientRect().height > 0 && S.trigger && S.trigger.isConnected) { S.trigger.click(); }
      }, 60);
    }, 30);
  }

  function renderSectionInto(entry) {
    var shadow = entry.shadow;
    while (shadow.firstChild) { shadow.removeChild(shadow.firstChild); }
    var wrap = h('div', { class: 't-' + themeOf(entry.menu) });
    wrap.appendChild(buildSection(Object.assign({ divider: true }, sectionActions(closeNativeMenu))));
    shadow.appendChild(wrap);
  }

  // Codex's menu separator: an empty, non-interactive row (26.9xx: a 9 px div with app-menu-separator classes).
  function isSeparator(el) {
    if (!el || isOurs(el) || (el.textContent || '').trim() || el.querySelector('button,[role^="menuitem"],input')) { return false; }
    if (el.getAttribute('role') === 'separator' || /separator/.test(String(el.className || ''))) { return true; }
    var r = el.getBoundingClientRect();
    return r.height > 0 && r.height <= 16;
  }

  function injectInto(menu) {
    for (var i = 0; i < S.sections.length; i++) {
      if (S.sections[i].menu === menu && S.sections[i].host.isConnected) { return; }
    }
    var items = menu.querySelectorAll('[role="menuitem"],[role="menuitemradio"],[role="menuitemcheckbox"]');
    var host = document.createElement('div');
    host.setAttribute('data-codex-multi-profile', 'accounts');
    host.style.display = 'block';
    var shadow = host.attachShadow({ mode: 'closed' });
    adopt(shadow, TOKENS + '\n' + ROWS_CSS);
    // Under the identity row (first item), after Codex's own separator when it has one, so the menu reads
    // identity / --- / Accounts / --- / Usage, Settings, Log out with one line between groups.
    var identity = items.length ? items[0] : null;
    var anchor = identity;
    if (identity && isSeparator(identity.nextElementSibling)) { anchor = identity.nextElementSibling; }
    if (anchor && anchor.parentNode) { anchor.parentNode.insertBefore(host, anchor.nextSibling); }
    else { menu.insertBefore(host, menu.firstChild); }
    var entry = { host: host, shadow: shadow, menu: menu };
    S.sections = S.sections.filter(function (s) { return s.host.isConnected && s.menu !== menu; });
    S.sections.push(entry);
    renderSectionInto(entry);
    send({ type: 'refresh' });
  }

  function scanMenus() {
    var menus = document.querySelectorAll('[role="menu"]');
    var open = null;
    for (var i = 0; i < menus.length; i++) {
      if (isAccountMenu(menus[i])) { open = menus[i]; injectInto(menus[i]); }
    }
    S.nativeMenu = open;
    S.sections = S.sections.filter(function (s) { return s.host.isConnected; });
  }

  function refreshSections() {
    S.sections = S.sections.filter(function (s) { return s.host.isConnected; });
    S.sections.forEach(renderSectionInto);
  }

  var scanQueued = false;
  // Look for Codex's avatar button again only when the one we know is gone (cheap check first).
  function refreshTrigger() {
    if (S.trigger && S.trigger.isConnected) { return; }
    var before = S.trigger;
    S.trigger = findTrigger();
    S.triggerSeenAt = Date.now();
    if (!!before !== !!S.trigger) { render(); }
  }

  function queueScan() {
    if (scanQueued) { return; }
    scanQueued = true;
    setTimeout(function () {
      scanQueued = false;
      scanMenus();
      refreshTrigger();
    }, 0);
  }

  // The account menu mounts a moment after the avatar click; look right then instead of watching the whole DOM.
  function scanSoon() { [0, 40, 120, 300].forEach(function (ms) { setTimeout(scanMenus, ms); }); }

  document.addEventListener('pointerdown', function (e) {
    var path = e.composedPath ? e.composedPath() : [];
    if (S.trigger && path.indexOf(S.trigger) >= 0) { S.triggerClickAt = Date.now(); scanSoon(); }
    if (S.menuOpen && layerHost && path.indexOf(layerHost) < 0) { S.menuOpen = false; render(); }
  }, true);

  /* ---------- actions ---------- */
  function beginSwitching(profile, add) {
    S.switching = { profile: profile, add: !!add };
    S.menuOpen = false;
    S.modal = null;
    clearTimeout(S.switchTimer);
    // The launcher closes this window within seconds. Still here after 25 s = it failed.
    S.switchTimer = setTimeout(function () {
      S.switching = null;
      showToast('error', t('switchFailed'));
    }, 25000);
    render();
  }
  function pickProfile(name) {
    var p = find(name);
    if (!p || p.active || S.switching) { return; }
    // Fast switch (new app-server, same window) only from the normal signed-in UI; from a sign-in
    // screen Codex has to restart to leave it.
    var fast = !!(S.trigger && S.trigger.isConnected) && !pendingAdd();
    if (!send({ type: 'switch', profile: name, fast: fast })) { showToast('error', t('offlineHint')); return; }
    beginSwitching(name, false);
  }
  function openModal(m) {
    S.menuOpen = false;
    S.modal = m;
    render();
    // Codex's menu hands focus back to its trigger as it closes; take it after that.
    setTimeout(function () {
      var el = layerShadow && (layerShadow.querySelector('.dlg .field') || layerShadow.querySelector('.dlg .btn.pri,.dlg .btn.danger'));
      if (el) { el.focus(); }
    }, 120);
  }
  function closeModal() { S.modal = null; render(); }
  function submitModal() {
    var m = S.modal;
    if (!m || m.busy) { return; }
    if (m.kind === 'add') {
      var key = toKey(m.value);
      if (!key) { m.error = t('toast_bad-name'); render(); return; }
      if (find(key)) { m.error = t('toast_exists', { detail: key }); render(); return; }
      m.busy = true; m.error = ''; m.key = key;
      if (!send({ type: 'add', name: key })) { m.busy = false; m.error = t('offlineHint'); }
      render();
    } else if (m.kind === 'rename') {
      var nk = toKey(m.value);
      if (!nk) { m.error = t('toast_bad-name'); render(); return; }
      if (nk === m.profile) { closeModal(); return; }
      if (find(nk)) { m.error = t('toast_exists', { detail: nk }); render(); return; }
      m.busy = true; m.error = '';
      send({ type: 'rename', profile: m.profile, name: nk });
      render();
    } else if (m.kind === 'remove') {
      m.busy = true; m.error = '';
      send({ type: 'remove', profile: m.profile });
      render();
    }
  }
  function showToast(level, text, action) {
    S.toast = { level: level, text: text, action: action || null };
    clearTimeout(S.toastTimer);
    S.toastTimer = setTimeout(function () { S.toast = null; render(); }, action ? 8000 : 4200);
    render();
  }

  /* ---------- body-level layer: fallback control, dialogs, toasts ---------- */
  var layerHost = null, layerShadow = null, layerRoot = null, ctlEl = null;

  function mountLayer() {
    if (layerHost && layerHost.isConnected) { return true; }
    var parent = document.body || document.documentElement;
    if (!parent) { return false; }
    layerHost = document.createElement('div');
    layerHost.id = 'cmp-switcher-root';
    layerHost.setAttribute('data-codex-multi-profile', 'switcher');
    // Codex sends printable keys typed "nowhere" to the composer. Inside a closed shadow root our
    // inputs look like a plain div to it, so opt out the way Codex's own terminal / editors do.
    layerHost.setAttribute('data-codex-character-input-boundary', '');
    parent.appendChild(layerHost);
    layerShadow = layerHost.attachShadow({ mode: 'closed' });
    adopt(layerShadow, TOKENS + '\n' + ROWS_CSS + '\n' + LAYER_CSS);
    layerRoot = h('div', { class: 'root' });
    layerShadow.appendChild(layerRoot);
    render();
    return true;
  }

  function loadPos() {
    try {
      var p = JSON.parse(localStorage.getItem(POS_KEY) || 'null');
      if (p && typeof p.x === 'number' && typeof p.y === 'number') { return p; }
    } catch (e) { }
    return null;
  }
  function savePos(p) { try { localStorage.setItem(POS_KEY, JSON.stringify(p)); } catch (e) { } }

  function enableDrag(el) {
    var start = null, moved = false;
    el.addEventListener('pointerdown', function (e) {
      if (e.button !== 0) { return; }
      start = { x: e.clientX, y: e.clientY, l: el.offsetLeft, t: el.offsetTop };
      moved = false;
      try { el.setPointerCapture(e.pointerId); } catch (x) { }
    });
    el.addEventListener('pointermove', function (e) {
      if (!start) { return; }
      var dx = e.clientX - start.x, dy = e.clientY - start.y;
      if (!moved && Math.abs(dx) + Math.abs(dy) < 5) { return; }
      moved = true; S.dragging = true;
      el.classList.add('dragging');
      el.style.left = Math.max(4, Math.min(start.l + dx, window.innerWidth - el.offsetWidth - 4)) + 'px';
      el.style.top = Math.max(4, Math.min(start.t + dy, window.innerHeight - el.offsetHeight - 4)) + 'px';
    });
    el.addEventListener('pointerup', function (e) {
      if (!start) { return; }
      try { el.releasePointerCapture(e.pointerId); } catch (x) { }
      el.classList.remove('dragging');
      S.dragging = false;
      if (moved) {
        savePos({ x: el.offsetLeft, y: el.offsetTop });
        el.__cmpSuppressClick = true;
        setTimeout(function () { el.__cmpSuppressClick = false; }, 0);
      }
      start = null;
      if (S.renderPending) { S.renderPending = false; setTimeout(render, 0); }
    });
  }

  function useFallback() {
    // Only when Codex's own avatar button could not be found for a while (a hidden window has no layout).
    return !S.trigger && Date.now() - S.startedAt > 5000 && document.visibilityState === 'visible';
  }

  function renderControl() {
    var act = activeProfile();
    var off = !connected();
    var label = off ? t('offline') : (act ? act.name : (S.state && S.state.active) || 'Codex');
    var el = h('button', {
      class: 'ctl', type: 'button', 'aria-haspopup': 'menu', 'aria-expanded': S.menuOpen ? 'true' : 'false',
      title: off ? t('offlineHint') : label + (act && act.account ? ' · ' + act.account : '')
    }, [avatar(off ? '?' : label), h('span', { class: 'lbl', text: label }), h('span', { class: 'chev' }, [icon('chevron', 14)])]);
    var p = loadPos();
    var x = p ? p.x : 10, y = p ? p.y : window.innerHeight - 32 - 10;
    el.style.left = Math.max(4, Math.min(x, window.innerWidth - 120)) + 'px';
    el.style.top = Math.max(4, Math.min(y, window.innerHeight - 36)) + 'px';
    el.addEventListener('click', function () {
      if (el.__cmpSuppressClick) { return; }
      S.menuOpen = !S.menuOpen;
      if (S.menuOpen) { send({ type: 'refresh' }); }
      render();
    });
    enableDrag(el);
    return el;
  }

  function renderFallbackMenu() {
    var menu = h('div', { class: 'menu', role: 'menu', 'aria-label': t('accounts') });
    menu.appendChild(buildSection(Object.assign({ divider: false }, sectionActions(function () { S.menuOpen = false; }))));
    // Anchored above the control, like Codex anchors its account menu above the avatar.
    var left = ctlEl ? ctlEl.offsetLeft - 1 : 9;
    menu.style.left = Math.max(8, Math.min(left, window.innerWidth - 314)) + 'px';
    var ctlTop = ctlEl ? ctlEl.offsetTop : window.innerHeight - 42;
    if (ctlTop < 320) { menu.style.top = (ctlTop + 40) + 'px'; }
    else { menu.style.bottom = Math.max(8, window.innerHeight - ctlTop + 7) + 'px'; }
    return menu;
  }

  function renderModal() {
    var m = S.modal;
    var dlg = h('div', { class: 'dlg', role: 'dialog', 'aria-modal': 'true', tabindex: '-1' });
    var foot = h('div', { class: 'foot' });
    var cancel = h('button', { class: 'btn', type: 'button', text: t('cancel'), disabled: m.busy ? true : null, onclick: closeModal });
    if (m.kind === 'add' || m.kind === 'rename') {
      var isAdd = m.kind === 'add';
      var title = isAdd ? t('addTitle') : t('renameTitle', { name: m.profile });
      dlg.setAttribute('aria-label', title);
      dlg.appendChild(h('h2', { text: title }));
      if (isAdd) { dlg.appendChild(h('p', { class: 'desc', text: t('addBody') })); }
      var field = h('input', { class: 'field' + (m.error ? ' bad' : ''), id: 'cmp-add-name', placeholder: t('addPlaceholder'), maxlength: '48', spellcheck: 'false', autocomplete: 'off' });
      field.value = m.value || '';
      var hint = h('div', { class: 'hint' + (m.error ? ' err' : '') });
      var setHint = function () {
        if (m.error) { hint.textContent = m.error; return; }
        var key = toKey(field.value);
        hint.textContent = key && key !== field.value.trim() ? t('addSaves', { key: key }) : '';
      };
      field.addEventListener('input', function () {
        m.value = field.value;
        if (m.error) { m.error = ''; field.classList.remove('bad'); hint.classList.remove('err'); }
        setHint();
      });
      setHint();
      if (m.busy) { field.disabled = true; }
      dlg.appendChild(h('div', { class: 'body' }, [h('label', { for: 'cmp-add-name', text: t('addLabel') }), field, hint]));
      foot.appendChild(cancel);
      foot.appendChild(h('button', { class: 'btn pri', type: 'button', disabled: m.busy ? true : null, onclick: submitModal },
        [m.busy ? h('span', { class: 'bspin' }) : null, m.busy ? (isAdd ? t('adding') : t('renaming')) : (isAdd ? t('addBtn') : t('renameBtn'))]));
    } else if (m.kind === 'remove') {
      dlg.setAttribute('aria-label', t('removeTitle', { name: m.profile }));
      dlg.appendChild(h('h2', { text: t('removeTitle', { name: m.profile }) }));
      dlg.appendChild(h('p', { class: 'desc', text: t('removeBody', { name: m.profile }) }));
      if (m.error) { dlg.appendChild(h('div', { class: 'body' }, [h('div', { class: 'hint err', text: m.error })])); }
      foot.appendChild(cancel);
      foot.appendChild(h('button', { class: 'btn danger', type: 'button', disabled: m.busy ? true : null, onclick: submitModal },
        [m.busy ? h('span', { class: 'bspin' }) : null, m.busy ? t('removing') : t('removeBtn')]));
    }
    dlg.appendChild(foot);
    dlg.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') { e.preventDefault(); if (!m.busy) { closeModal(); } }
      else if (e.key === 'Enter' && !(e.target && e.target.tagName === 'BUTTON')) { e.preventDefault(); submitModal(); }
      else if (e.key === 'Tab') {
        var f = Array.prototype.slice.call(dlg.querySelectorAll('input:not([disabled]),button:not([disabled])'));
        if (!f.length) { return; }
        var i = f.indexOf(layerShadow.activeElement);
        if (e.shiftKey && i <= 0) { e.preventDefault(); f[f.length - 1].focus(); }
        else if (!e.shiftKey && i === f.length - 1) { e.preventDefault(); f[0].focus(); }
      }
      // Keep Codex shortcuts from firing while typing in the dialog.
      e.stopPropagation();
    });
    var back = h('div', { class: 'backdrop' }, [dlg]);
    back.addEventListener('pointerdown', function (e) { if (e.target === back && !m.busy) { closeModal(); } });
    return back;
  }

  function renderSwitching() {
    var sw = S.switching;
    return h('div', { class: 'backdrop', role: 'alert', 'aria-live': 'assertive' }, [
      h('div', { class: 'card' }, [h('span', { class: 'spin' }), h('div', {}, [
        h('div', { class: 't1', text: sw.add ? t('switchingAdd', { name: sw.profile }) : t('switching', { name: sw.profile }) }),
        h('div', { class: 't2', text: t('switchingSub') })])])
    ]);
  }

  function renderToast() {
    var tt = S.toast;
    var el = h('div', { class: 'toast' + (tt.level === 'error' ? ' error' : ''), role: 'status' }, [
      h('span', { class: 'ti' }, [icon(tt.level === 'error' ? 'alert' : 'check', 16)]),
      h('span', { class: 'tt', text: tt.text })
    ]);
    if (tt.action) {
      el.appendChild(h('button', {
        class: 'btn sm pri', type: 'button', text: tt.action.label,
        onclick: function () { var fn = tt.action.run; S.toast = null; render(); fn(); }
      }));
    }
    el.appendChild(h('button', { class: 'x', type: 'button', 'aria-label': 'Close', onclick: function () { S.toast = null; render(); } }, [icon('x', 14)]));
    return el;
  }

  function renderLimit() {
    var act = activeProfile();
    var next = S.state && S.state.suggestion;
    if (!act || !next) { return null; }
    var el = h('div', { class: 'limit', role: 'status' }, [
      h('div', { class: 't1' }, [h('span', {}, [icon('alert', 16)]), t('limitTitle', { name: act.name })]),
      h('div', { class: 't2', text: t('limitBody', { next: next }) }),
      h('div', { class: 'foot' }, [
        h('button', { class: 'btn sm', type: 'button', text: t('dismiss'), onclick: function () { S.limitHit = false; S.limitDismissedUntil = Date.now() + 30 * 60000; render(); } }),
        h('button', { class: 'btn sm pri', type: 'button', text: t('limitSwitch', { next: next }), onclick: function () {
          S.limitHit = false;
          send({ type: 'depleted', profile: act.name, value: true });
          setTimeout(function () { pickProfile(next); }, 150);
        } })
      ])
    ]);
    if (ctlEl) { el.style.bottom = (window.innerHeight - ctlEl.offsetTop + 8) + 'px'; }
    return el;
  }

  function renderPending() {
    var name = S.state.pending;
    var el = h('div', { class: 'limit', role: 'status' }, [
      h('div', { class: 't1' }, [h('span', {}, [icon('plus', 16)]), t('pendingTitle', { name: name })]),
      h('div', { class: 't2', text: t('pendingBody', { name: name }) }),
      h('div', { class: 'foot' }, [
        h('button', { class: 'btn sm', type: 'button', text: t('pendingCancel'), onclick: function () {
          if (send({ type: 'cancel-add' })) { beginSwitching('', false); }
        } })
      ])
    ]);
    if (ctlEl) { el.style.bottom = (window.innerHeight - ctlEl.offsetTop + 8) + 'px'; }
    return el;
  }

  function render() {
    if (!layerRoot) { return; }
    if (S.dragging) { S.renderPending = true; return; }
    var act = layerShadow.activeElement;
    var keepFocus = S.modal && act && act.classList && act.classList.contains('field');
    var caret = keepFocus ? act.selectionStart : 0;
    layerRoot.className = 'root t-' + pageTheme();
    while (layerRoot.firstChild) { layerRoot.removeChild(layerRoot.firstChild); }
    ctlEl = null;
    if (useFallback() && !S.switching) {
      ctlEl = renderControl();
      layerRoot.appendChild(ctlEl);
      if (S.menuOpen) { layerRoot.appendChild(renderFallbackMenu()); }
    }
    if (pendingAdd() && !S.switching && !S.modal) { layerRoot.appendChild(renderPending()); }
    if (S.limitHit && !S.switching && !S.modal && Date.now() > S.limitDismissedUntil) {
      var lim = renderLimit();
      if (lim) { layerRoot.appendChild(lim); }
    }
    if (S.modal && !S.switching) { layerRoot.appendChild(renderModal()); }
    if (S.switching) { layerRoot.appendChild(renderSwitching()); }
    if (S.toast && !S.switching) { layerRoot.appendChild(renderToast()); }
    if (keepFocus) {
      var f = layerShadow.querySelector('.dlg .field');
      if (f && !f.disabled) { f.focus(); try { f.setSelectionRange(caret, caret); } catch (e) { } }
    }
  }

  /* ---------- host -> page ---------- */
  function receive(evt) {
    if (!evt || typeof evt !== 'object') { return; }
    if (evt.kind === 'state' && evt.state) {
      S.state = evt.state;
      refreshSections();
      render();
    } else if (evt.kind === 'switching') {
      if (!S.switching) { beginSwitching(evt.profile || '', !!evt.add); }
    } else if (evt.kind === 'switched') {
      // Fast switch: the window stayed, Codex picked the new login up by itself.
      clearTimeout(S.switchTimer);
      S.switching = null;
      S.modal = null;
      if (!evt.add) {
        S.flash = evt.profile; S.flashUntil = Date.now() + 2500;
        refreshSections();
        showToast('info', t('toast_switched', { detail: evt.profile }));
      }
      render();
    } else if (evt.kind === 'toast') {
      var code = String(evt.code || '');
      var detail = evt.detail || '';
      var table = I18N[lang()] || I18N.en;
      var key = 'toast_' + code;
      var text = (table[key] || I18N.en[key]) ? t(key, { detail: detail }) : t('toast_generic', { code: code });
      var m = S.modal;
      if (code === 'added') {
        if (m && m.kind === 'add') { S.modal = null; }
        S.flash = detail; S.flashUntil = Date.now() + 2500;
        refreshSections();
        showToast('info', text);
        return;
      }
      if (code === 'removed' || code === 'renamed') {
        if (m && (m.kind === 'remove' || m.kind === 'rename')) { S.modal = null; }
        showToast('info', text);
        return;
      }
      if (code === 'unknown-profile') { send({ type: 'refresh' }); }
      if (evt.level === 'error' && S.switching) { clearTimeout(S.switchTimer); S.switching = null; }
      if (m && m.busy) { m.busy = false; m.error = text; render(); return; }
      showToast(evt.level === 'error' ? 'error' : 'info', text);
    }
  }

  /* ---------- keyboard ---------- */
  window.addEventListener('keydown', function (e) {
    var altGr = e.getModifierState && e.getModifierState('AltGraph');
    if (e.ctrlKey && e.altKey && !e.shiftKey && !e.metaKey && !altGr && (e.key === 'a' || e.key === 'A' || e.code === 'KeyA')) {
      e.preventDefault(); e.stopPropagation();
      if (S.modal || S.switching) { return; }
      if (S.trigger && S.trigger.isConnected) {
        if (S.nativeMenu && S.nativeMenu.isConnected) { closeNativeMenu(); }
        else { S.triggerClickAt = Date.now(); S.trigger.click(); scanSoon(); }
      } else {
        S.menuOpen = !S.menuOpen;
        if (S.menuOpen) { send({ type: 'refresh' }); }
        render();
      }
      return;
    }
    if (S.modal || S.switching) { return; }
    var menuUp = (S.nativeMenu && S.nativeMenu.isConnected) || S.menuOpen;
    if (!menuUp) { return; }
    var tgt = (e.composedPath && e.composedPath()[0]) || e.target;
    if (tgt && (tgt.tagName === 'INPUT' || tgt.tagName === 'TEXTAREA' || tgt.isContentEditable)) { return; }
    if (e.key === 'Escape' && S.menuOpen) { e.preventDefault(); S.menuOpen = false; render(); return; }
    // 1-9 picks the n-th other account, matching the hint on the right of each row.
    if (/^[1-9]$/.test(e.key) && !e.ctrlKey && !e.altKey && !e.metaKey && connected()) {
      var target = switchTargets()[parseInt(e.key, 10) - 1];
      if (target) {
        e.preventDefault(); e.stopPropagation();
        if (S.menuOpen) { S.menuOpen = false; } else { closeNativeMenu(); }
        pickProfile(target.name);
      }
    }
  }, true);

  window.addEventListener('resize', function () { if (layerRoot) { render(); } });
  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState === 'visible' && layerRoot) { S.trigger = null; refreshTrigger(); render(); }
  });

  /* ---------- observers ---------- */
  var themeObs = new MutationObserver(function () {
    if (layerRoot) { layerRoot.className = 'root t-' + pageTheme(); }
  });

  /* Usage-limit hint. Codex adds DOM all the time while it streams, so the observer only collects
     small new nodes and checks them at most once a second; big subtrees (messages) are skipped. */
  var limitCandidates = [];
  var limitTimer = 0;
  function limitWatching() {
    return !S.limitHit && !S.switching && !!S.state && !!S.state.suggestion && Date.now() > S.limitDismissedUntil;
  }
  function checkLimitCandidates() {
    limitTimer = 0;
    var list = limitCandidates;
    limitCandidates = [];
    if (!limitWatching()) { return; }
    for (var i = 0; i < list.length; i++) {
      var n = list[i];
      if (!n.isConnected) { continue; }
      var txt = n.nodeType === 3 ? n.nodeValue : n.textContent;
      if (txt && txt.length < 600 && LIMIT_RE.test(txt)) { S.limitHit = true; render(); return; }
    }
  }
  var limitObs = new MutationObserver(function (records) {
    if (!limitWatching()) { return; }
    for (var i = 0; i < records.length; i++) {
      var added = records[i].addedNodes;
      for (var j = 0; j < added.length; j++) {
        var n = added[j];
        if (n.nodeType === 3 ? n.nodeValue.length < 600 : (n.nodeType === 1 && n.childElementCount <= 12 && !isOurs(n))) {
          if (limitCandidates.length < 200) { limitCandidates.push(n); }
        }
      }
    }
    if (limitCandidates.length && !limitTimer) { limitTimer = setTimeout(checkLimitCandidates, 1000); }
  });

  /* Codex menus are portals appended to <body>: watching body's direct children is enough.
     Also keeps our layer attached if something removes it. */
  var domObs = new MutationObserver(function (records) {
    if (layerHost && !layerHost.isConnected) { layerHost = null; mountLayer(); }
    for (var i = 0; i < records.length; i++) {
      if (records[i].addedNodes.length) { queueScan(); return; }
    }
  });

  function hello() {
    var now = Date.now();
    if (now - S.lastHello < 1500) { return; }
    S.lastHello = now;
    send({ type: 'hello' });
  }

  function start() {
    if (!mountLayer()) { return; }
    try {
      themeObs.observe(document.documentElement, { attributes: true, attributeFilter: ['class', 'data-theme', 'style'] });
      if (document.body) { themeObs.observe(document.body, { attributes: true, attributeFilter: ['class', 'data-theme', 'style'] }); }
      domObs.observe(document.body || document.documentElement, { childList: true });
      limitObs.observe(document.body || document.documentElement, { childList: true, subtree: true });
    } catch (e) { }
    queueScan();
    hello();
    var tries = 0;
    var iv = setInterval(function () {
      tries++;
      if (S.state || tries > 20) { clearInterval(iv); render(); return; }
      S.lastHello = 0;
      hello();
    }, 750);
    // Decide about the fallback control once Codex had time to render its sidebar, then only
    // look again when the avatar button went away (sign-in screen, re-render).
    setTimeout(function () { S.trigger = null; refreshTrigger(); render(); }, 5200);
    setInterval(refreshTrigger, 10000);
  }

  window.__cmpSwitcher = {
    receive: receive,
    open: function () {
      if (S.trigger && S.trigger.isConnected) { S.triggerClickAt = Date.now(); S.trigger.click(); scanSoon(); }
      else { S.menuOpen = true; render(); }
    },
    // Read-only summary for diagnostics (masked data only).
    status: function () {
      var act = activeProfile();
      return {
        connected: connected(), native: !!S.trigger, nativeMenuOpen: !!(S.nativeMenu && S.nativeMenu.isConnected),
        sections: S.sections.filter(function (s) { return s.host.isConnected; }).length,
        fallback: useFallback(), menuOpen: S.menuOpen, modal: S.modal ? S.modal.kind : null,
        modalError: S.modal ? (S.modal.error || null) : null,
        switching: S.switching ? S.switching.profile : null, pending: S.state ? S.state.pending : null,
        limitHit: S.limitHit, active: act ? act.name : null, profiles: profiles().length,
        names: profiles().map(function (p) { return p.name; }), toast: S.toast ? S.toast.text : null
      };
    },
    version: 2
  };

  if (document.readyState === 'loading') { document.addEventListener('DOMContentLoaded', start); }
  else { start(); }
})();
