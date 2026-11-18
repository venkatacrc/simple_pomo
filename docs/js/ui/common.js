// Shared UI helpers: escaping, delegated events, bottom sheets, toasts, formatting.

/** main.js points `app.render` at the real renderer; view modules call it after local state changes. */
export const app = { render: () => {}, goTab: () => {} };

export const $ = (sel, root = document) => root.querySelector(sel);
export const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

export const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => (
  { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

// ───────────── delegated events ─────────────
// Views render plain HTML with data-act="name" (click), data-change="name",
// data-input="name" and data-enter="name"; modules register handlers here.

const handlers = { click: {}, change: {}, input: {}, enter: {} };
export function register(kind, map) { Object.assign(handlers[kind], map); }

function dispatch(kind, attr, e) {
  const el = e.target.closest(`[${attr}]`);
  if (!el) return false;
  const fn = handlers[kind][el.getAttribute(attr)];
  if (!fn) return false;
  fn({ ...el.dataset }, el, e);
  return true;
}
export function initEvents() {
  document.addEventListener('click', (e) => {
    if (dispatch('click', 'data-act', e)) e.preventDefault();
  });
  document.addEventListener('change', (e) => dispatch('change', 'data-change', e));
  document.addEventListener('input', (e) => dispatch('input', 'data-input', e));
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey && e.target.matches('input')) dispatch('enter', 'data-enter', e);
  });
}

// ───────────── bottom sheets ─────────────

export function openSheet({ title, body, footer = '', onMount }) {
  const wrap = document.createElement('div');
  wrap.className = 'sheet-wrap';
  wrap.innerHTML = `
    <div class="sheet-bg" data-close></div>
    <div class="sheet" role="dialog" aria-modal="true" aria-label="${esc(title)}">
      <div class="sheet-head">
        <h3>${esc(title)}</h3>
        <button class="icon-btn" data-close aria-label="Close">✕</button>
      </div>
      <div class="sheet-body">${body}</div>
      ${footer ? `<div class="sheet-foot">${footer}</div>` : ''}
    </div>`;
  $('#sheets').appendChild(wrap);
  requestAnimationFrame(() => wrap.classList.add('open'));
  document.body.classList.add('sheet-open');

  const api = {
    el: wrap,
    body: $('.sheet-body', wrap),
    close() {
      wrap.classList.remove('open');
      wrap.classList.add('closing');
      setTimeout(() => {
        wrap.remove();
        document.body.classList.toggle('sheet-open', !!$('.sheet-wrap:not(.closing)'));
      }, 200);
    },
  };
  wrap.addEventListener('click', (e) => { if (e.target.closest('[data-close]')) api.close(); });
  if (onMount) onMount(api);
  return api;
}

let toastTimer = null;
export function toast(msg, ms = 2200) {
  const el = $('#toast');
  el.textContent = msg;
  el.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.remove('show'), ms);
}

// ───────────── formatting ─────────────

export function fmtMinutes(minutes) {
  const total = Math.round(minutes);
  if (total < 60) return `${total}m`;
  const h = Math.floor(total / 60), m = total % 60;
  return m === 0 ? `${h}h` : `${h}h${m}m`;
}
export const fmtDay = (d) => d.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' });
export const fmtShort = (d) => d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
export const fmtDateTime = (d) =>
  d.toLocaleString(undefined, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
export const fmtTime = (d) => d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });

export const pad2 = (n) => String(n).padStart(2, '0');
export const dateToInput = (d) => `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
export const inputToDate = (s) => {
  const [y, m, d] = String(s).split('-').map(Number);
  return new Date(y, (m || 1) - 1, d || 1);
};

const PALETTE = ['#db4f4f', '#459e8c', '#4d78bd', '#d4943d', '#8c5cbd', '#4d9966', '#c9608f', '#5fa8c9'];
export function catColor(name) {
  let h = 0;
  for (const ch of String(name || '')) h = (h * 31 + ch.charCodeAt(0)) >>> 0;
  return PALETTE[h % PALETTE.length];
}
export const badge = (name) =>
  `<span class="badge" style="--c:${catColor(name)}">${esc(name || 'Uncategorized')}</span>`;

export const ICONS = {
  timer: '<svg viewBox="0 0 24 24"><circle cx="12" cy="13.5" r="7.5"/><path d="M12 9.5v4l2.5 1.5M9.5 2.5h5"/></svg>',
  tasks: '<svg viewBox="0 0 24 24"><path d="M9.5 6.5h11M9.5 12h11M9.5 17.5h11M3.5 6.5l1.2 1.2 2.3-2.4M3.5 12l1.2 1.2 2.3-2.4M3.5 17.5l1.2 1.2 2.3-2.4"/></svg>',
  plan: '<svg viewBox="0 0 24 24"><rect x="3.5" y="5" width="17" height="15.5" rx="2.5"/><path d="M3.5 10h17M8 3v4M16 3v4"/></svg>',
  reports: '<svg viewBox="0 0 24 24"><path d="M5 20V11M11 20V4M17 20v-7M2.5 20.5h19"/></svg>',
  gear: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="3"/><path d="M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2.1 2.1M16.6 16.6l2.1 2.1M18.7 5.3l-2.1 2.1M7.4 16.6l-2.1 2.1"/></svg>',
  note: '<svg viewBox="0 0 24 24"><path d="M6 3.5h9l4 4v13H6z"/><path d="M15 3.5v4h4M9 12h7M9 16h5"/></svg>',
  play: '<svg viewBox="0 0 24 24"><path d="M8 5.5v13l11-6.5z" fill="currentColor"/></svg>',
  target: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3.5"/></svg>',
  more: '<svg viewBox="0 0 24 24"><circle cx="5" cy="12" r="1.6" fill="currentColor"/><circle cx="12" cy="12" r="1.6" fill="currentColor"/><circle cx="19" cy="12" r="1.6" fill="currentColor"/></svg>',
  check: '<svg viewBox="0 0 24 24"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>',
  chevL: '<svg viewBox="0 0 24 24"><path d="M15 5l-7 7 7 7"/></svg>',
  chevR: '<svg viewBox="0 0 24 24"><path d="M9 5l7 7-7 7"/></svg>',
  plus: '<svg viewBox="0 0 24 24"><path d="M12 5v14M5 12h14"/></svg>',
};
