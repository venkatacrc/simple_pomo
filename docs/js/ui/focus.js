import {
  state, PHASES, PHASE_ORDER, PRESETS, AREAS, categoriesFor, activeTask, setActiveTask, setActive,
  appendNote, orderedNotes, setCompleted, updateSettings, walmartFiscal, seasonClock, SEASONS, rgb,
} from '../core.js';
import * as timer from '../timer.js';
import {
  $, esc, register, badge, ICONS, fmtDateTime, toast,
} from './common.js';
import { openNotesSheet } from './sheets.js';

// Draft state for the capture card (kept outside the DOM so re-renders never lose typing).
const draft = { text: '', cat: '', note: '' };

export function syncDraft() {
  const area = state.settings.activeArea;
  const t = activeTask();
  if (t && t.area === area) { draft.text = t.title; draft.cat = t.category; }
  else { draft.text = ''; draft.cat = categoriesFor(area)[0] || AREAS[area].label; }
  draft.note = '';
}

/** Append any pending note to the active task (called when a focus block ends). */
export function flushDraftNote(taskId = state.activeTaskId) {
  if (!draft.note.trim() || !taskId) return;
  if (appendNote(taskId, draft.note)) draft.note = '';
}

// ───────────── timer card ─────────────

const RING_C = 2 * Math.PI * 54;

function presetRow() {
  const s = state.settings;
  return `<div class="presets" role="tablist" aria-label="Timer presets">${PRESETS.map((p) => {
    const on = p.f === s.focusMinutes && p.s === s.shortBreakMinutes && p.l === s.longBreakMinutes;
    return `<button class="chip ${on ? 'on' : ''}" data-act="preset" data-id="${p.id}" title="${p.title}: ${p.f}m focus / ${p.s}m break / ${p.l}m long break">
      <b>${p.f}</b><small>+${p.s}</small></button>`;
  }).join('')}</div>`;
}

function phaseTabs(S) {
  return `<div class="phase-tabs">${PHASE_ORDER.map((p) =>
    `<button class="${p === S.phase ? 'on' : ''}" data-act="phase" data-p="${p}">${PHASES[p].title}</button>`).join('')}</div>`;
}

function timerCard(S) {
  return `
  <div class="card timer-card">
    <div class="ring-wrap">
      <svg viewBox="0 0 120 120" aria-hidden="true">
        <circle class="ring-bg" cx="60" cy="60" r="54"/>
        <circle id="ringFg" class="ring-fg" cx="60" cy="60" r="54" transform="rotate(-90 60 60)"
          stroke-dasharray="${RING_C.toFixed(2)}" stroke-dashoffset="${(RING_C * (1 - Math.max(0.001, S.progress))).toFixed(2)}"/>
      </svg>
      <div class="ring-text">
        <div id="timeText" class="time" aria-live="off">${timer.displayTime(S.remainingMs)}</div>
        <div class="phase-lbl">${PHASES[S.phase].title.toUpperCase()}</div>
      </div>
    </div>
    <div class="controls">
      <button class="round" data-act="t-reset" aria-label="Reset">↺</button>
      <button class="big" id="toggleBtn" data-act="t-toggle">${S.running ? '❚❚ PAUSE' : '▶ START'}</button>
      <button class="round" data-act="t-skip" aria-label="Skip to next phase">⏭</button>
    </div>
  </div>`;
}

/** Per-second update that avoids re-rendering the whole view. */
export function updateTick() {
  const S = timer.snapshot();
  const tt = $('#timeText');
  if (tt) tt.textContent = timer.displayTime(S.remainingMs);
  const ring = $('#ringFg');
  if (ring) ring.setAttribute('stroke-dashoffset', (RING_C * (1 - Math.max(0.001, S.progress))).toFixed(2));
}

// ───────────── quick capture ─────────────

function captureCard() {
  const area = state.settings.activeArea;
  const t = activeTask();
  const mine = t && t.area === area ? t : null;
  const cats = [...categoriesFor(area)];
  if (draft.cat && !cats.includes(draft.cat)) cats.push(draft.cat);
  const notes = mine ? orderedNotes(mine) : [];
  return `
  <div class="card capture">
    <div class="cap-row">
      <input id="capText" data-input="cap-text" data-enter="cap-commit" type="text" enterkeyhint="go"
        placeholder="What are you working on?" value="${esc(draft.text)}" autocomplete="off">
      <select id="capCat" data-change="cap-cat" aria-label="Category">
        ${cats.map((c) => `<option ${c === draft.cat ? 'selected' : ''}>${esc(c)}</option>`).join('')}
      </select>
      <button class="icon-btn go" data-act="cap-commit" aria-label="Set as active task">→</button>
    </div>
    ${mine ? `
      <div class="active-info">
        <span class="area-tag ${mine.area}">${AREAS[mine.area].label}</span>
        <span class="muted">${mine.completedPomodoros}/${mine.estimatedPomodoros} pomodoros logged</span>
        <span class="grow"></span>
        <button class="link" data-act="cap-clear">Clear</button>
      </div>
      <div class="notes-head">${ICONS.note}<span>Session notes</span><em>append-only</em></div>
      ${notes.length ? `<div class="notes-list">${notes.map((n) =>
        `<div class="note"><time>${esc(fmtDateTime(n.createdAt))}</time><p>${esc(n.text)}</p></div>`).join('')}</div>` : ''}
      <div class="note-add">
        <textarea id="capNote" data-input="cap-note" rows="2" placeholder="Add a note for this session…">${esc(draft.note)}</textarea>
        <button class="icon-btn go" data-act="note-add" aria-label="Add note">＋</button>
      </div>` : ''}
  </div>`;
}

// ───────────── up next ─────────────

function upNext() {
  const area = state.settings.activeArea;
  const open = state.tasks.filter((t) => !t.isArchived && !t.isCompleted && t.area === area);
  return `
  <div class="up-next">
    <div class="sec-head"><h2>Up next</h2><span class="muted">${open.length} open</span></div>
    ${open.length ? open.slice(0, 5).map((t) => {
    const on = state.activeTaskId === t.id;
    return `<div class="row ${on ? 'active' : ''}">
        <button class="check" data-act="up-done" data-id="${t.id}" aria-label="Mark done"></button>
        <div class="grow"><div class="t-title">${esc(t.title)}</div>
          <div class="t-meta">${badge(t.category)}<span class="pill">${t.completedPomodoros}/${t.estimatedPomodoros} 🍅</span></div></div>
        <button class="icon-btn ${orderedNotes(t).length ? 'has' : ''}" data-act="notes" data-id="${t.id}" aria-label="Notes">${ICONS.note}</button>
        <button class="icon-btn ${on ? 'on' : ''}" data-act="up-pick" data-id="${t.id}" aria-label="${on ? 'Active' : 'Make active'}">${on ? ICONS.target : ICONS.play}</button>
      </div>`;
  }).join('') : `<p class="empty">No open ${AREAS[area].label.toLowerCase()} tasks. Add some in the Tasks tab, or switch area at the top.</p>`}
  </div>`;
}

// ───────────── "The Present" clock ─────────────

function lerp(a, b, t) { return a.map((v, i) => v + (b[i] - v) * t); }
function ringColor(f) {
  const stops = ['winter', 'spring', 'summer', 'autumn', 'winter'].map((s) => SEASONS[s].color);
  const x = Math.min(0.9999, Math.max(0, f)) * 4;
  const i = Math.floor(x);
  return rgb(lerp(stops[i], stops[i + 1], x - i));
}
const polar = (cx, cy, r, deg) => {
  const a = ((deg - 90) * Math.PI) / 180;
  return [cx + r * Math.cos(a), cy + r * Math.sin(a)];
};

function clockSvg(c) {
  const cx = 130, cy = 130, SEG = 180, rMid = 119;
  let ring = '';
  for (let i = 0; i < SEG; i++) {
    const a0 = (i / SEG) * 360, a1 = ((i + 1.4) / SEG) * 360;
    const [x0, y0] = polar(cx, cy, rMid, a0), [x1, y1] = polar(cx, cy, rMid, a1);
    ring += `<path d="M${x0.toFixed(2)} ${y0.toFixed(2)} A${rMid} ${rMid} 0 0 1 ${x1.toFixed(2)} ${y1.toFixed(2)}" stroke="${ringColor((i + 0.5) / SEG)}"/>`;
  }
  let ticks = '';
  for (let i = 0; i < 12; i++) {
    const major = i % 3 === 0;
    const [x0, y0] = polar(cx, cy, 100, i * 30), [x1, y1] = polar(cx, cy, major ? 90 : 94, i * 30);
    ticks += `<line x1="${x0.toFixed(1)}" y1="${y0.toFixed(1)}" x2="${x1.toFixed(1)}" y2="${y1.toFixed(1)}" stroke="#fff" stroke-opacity="${major ? 0.9 : 0.35}" stroke-width="${major ? 2 : 1}"/>`;
  }
  const lab = (s, x, y) => `<text x="${x}" y="${y}" fill="${rgb(SEASONS[s].color)}" class="clk-lbl">${SEASONS[s].label.toUpperCase()}</text>`;
  const cur = SEASONS[c.season];
  const now = new Date();
  return `
  <svg viewBox="0 0 260 260" class="clock-svg" role="img" aria-label="Year clock: ${cur.label}, day ${c.cycleDay} of ${c.cycleLength}">
    <defs><radialGradient id="dial"><stop offset="0" stop-color="#000" stop-opacity=".55"/><stop offset="1" stop-color="#000" stop-opacity=".25"/></radialGradient></defs>
    <g fill="none" stroke-width="22">${ring}</g>
    <circle cx="${cx}" cy="${cy}" r="108" fill="url(#dial)"/>
    ${ticks}
    ${lab('winter', 130, 50)}${lab('spring', 214, 133)}${lab('summer', 130, 218)}${lab('autumn', 46, 133)}
    <text x="130" y="102" text-anchor="middle" class="clk-season" fill="${rgb(cur.color)}">${cur.label.toUpperCase()}</text>
    <text x="130" y="154" text-anchor="middle" class="clk-date">${now.toLocaleDateString(undefined, { month: 'short', day: 'numeric' })}</text>
    <text x="130" y="172" text-anchor="middle" class="clk-day">day ${c.cycleDay} / ${c.cycleLength}</text>
    <g transform="rotate(${(c.progress * 360).toFixed(3)} ${cx} ${cy})">
      <line x1="130" y1="130" x2="130" y2="30" stroke="#fff" stroke-width="3" stroke-linecap="round"/>
      <line x1="130" y1="130" x2="130" y2="148" stroke="#fff" stroke-opacity=".45" stroke-width="3" stroke-linecap="round"/>
      <circle cx="130" cy="130" r="5" fill="#fff" stroke="#000" stroke-opacity=".4"/>
    </g>
  </svg>`;
}

const days = (n) => `${n} day${n === 1 ? '' : 's'}`;

export function clockHtml() {
  const now = new Date();
  const c = seasonClock(now);
  const f = walmartFiscal(now);
  const next = SEASONS[c.nextSeason];
  return `
    <div class="clock-head"><div><strong>The Present</strong><span>A year at a glance</span></div></div>
    ${clockSvg(c)}
    <div class="clock-foot">
      <span class="left"><i style="background:${rgb(next.color)}"></i>${next.label} in ${days(c.daysUntilNextSeason)}</span>
      <span class="right">${f.nextLabel} in ${days(f.daysUntilNextQuarter)}</span>
    </div>`;
}
export function updateClock() {
  const el = $('#clockCard');
  if (el) el.innerHTML = clockHtml();
}

// ───────────── view ─────────────

export function render() {
  const S = timer.snapshot();
  return `
  <div class="focus-grid">
    <section class="col-a">
      ${presetRow()}
      ${phaseTabs(S)}
      ${timerCard(S)}
    </section>
    <section class="col-b">
      ${captureCard()}
      ${upNext()}
      <div id="clockCard" class="card clock-card">${clockHtml()}</div>
    </section>
  </div>`;
}

// ───────────── actions ─────────────

function commit() {
  const text = draft.text.trim();
  if (!text) return;
  const area = state.settings.activeArea;
  const cat = draft.cat || categoriesFor(area)[0];
  setActiveTask(text, cat, area);
  draft.cat = cat;
  document.activeElement?.blur?.();
  toast(`Active: ${text}`);
}

export function init() {
  register('input', {
    'cap-text': (_, el) => { draft.text = el.value; },
    'cap-note': (_, el) => { draft.note = el.value; },
  });
  register('change', { 'cap-cat': (_, el) => { draft.cat = el.value; } });
  register('enter', { 'cap-commit': commit });
  register('click', {
    'cap-commit': commit,
    'cap-clear': () => { setActive(null); syncDraft(); },
    'note-add': () => {
      if (!state.activeTaskId) return;
      if (appendNote(state.activeTaskId, draft.note)) { draft.note = ''; toast('Note added'); }
    },
    preset: ({ id }) => {
      const p = PRESETS.find((x) => x.id === id);
      if (!p) return;
      updateSettings({ focusMinutes: p.f, shortBreakMinutes: p.s, longBreakMinutes: p.l });
      timer.refreshForSettings();
    },
    phase: ({ p }) => timer.switchPhase(p),
    't-toggle': () => timer.toggle(),
    't-reset': () => timer.reset(),
    't-skip': () => timer.skip(),
    notes: ({ id }) => openNotesSheet(id),
    'up-done': ({ id }) => setCompleted(id, true),
    'up-pick': ({ id }) => { setActive(state.activeTaskId === id ? null : id); },
  });
}
