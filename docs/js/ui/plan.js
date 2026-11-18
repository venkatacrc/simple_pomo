import {
  state, AREAS, categoriesFor, newTask, addTask, planTask, setCompleted, setActive, getTask, orderedNotes,
  notesLog, plannedTasksIn, plannedTasksOn, focusSessionCount, focusMinutes, focusSessionsIn, planWindowOpen,
  startOfDay, endOfDay, addDays, sameDay, weekInfo,
} from '../core.js';
import { esc, register, badge, ICONS, fmtShort, fmtMinutes, toast, app } from './common.js';
import { openTaskSheet, openNotesSheet } from './sheets.js';

const view = { weekOffset: 0, selectedDay: startOfDay(new Date()), quickTitle: '' };

const weekStart = () => state.prefs.weekStart || 0;
function weekRange() {
  const base = addDays(weekInfo(new Date(), weekStart()).start, view.weekOffset * 7);
  return { start: base, end: endOfDay(addDays(base, 6)) };
}
const weekDays = () => { const { start } = weekRange(); return [...Array(7)].map((_, i) => addDays(start, i)); };

function moveWeek(delta) {
  view.weekOffset += delta;
  view.selectedDay = startOfDay(addDays(view.selectedDay, delta * 7));
  app.render();
}

// ───────────── status logic ─────────────
// Missed only after the planned days have passed with no work; items still
// ahead stay "Upcoming" so future events never show as missed.

const STATUS = {
  done:      { label: 'Done',      cls: 'st-done',     rank: 3 },
  partial:   { label: 'Partial',   cls: 'st-partial',  rank: 1 },
  missed:    { label: 'Missed',    cls: 'st-missed',   rank: 0 },
  upcoming:  { label: 'Upcoming',  cls: 'st-upcoming', rank: 2 },
  unplanned: { label: 'Unplanned', cls: 'st-unplanned', rank: 4 },
};

function statusFor(t, sessions, minutes) {
  if (t.isCompleted || sessions >= Math.max(t.estimatedPomodoros, 1)) return 'done';
  if (sessions > 0 || minutes > 0) return 'partial';
  if (planWindowOpen(t)) return 'upcoming';
  return 'missed';
}

function comparisonRows() {
  const range = weekRange();
  const area = state.settings.activeArea;
  const rows = [];
  const covered = new Set();
  for (const t of plannedTasksIn(range, area)) {
    const n = focusSessionCount(t, range), m = focusMinutes(t, range);
    rows.push({ id: t.id, task: t, title: t.title, category: t.category, planned: true, est: t.estimatedPomodoros, n, m, status: statusFor(t, n, m) });
    covered.add(t.title.toLowerCase());
  }
  const byTitle = new Map();
  for (const s of focusSessionsIn(range, area)) {
    if (covered.has(s.taskTitle.toLowerCase())) continue;
    const g = byTitle.get(s.taskTitle) || { cat: s.category, n: 0, m: 0 };
    g.n += 1; g.m += Math.max(0, (s.endedAt - s.startedAt) / 60000);
    byTitle.set(s.taskTitle, g);
  }
  for (const [title, g] of byTitle) {
    rows.push({ id: `u-${title}`, task: null, title, category: g.cat, planned: false, est: 0, n: g.n, m: g.m, status: 'unplanned' });
  }
  return rows.sort((a, b) => (STATUS[a.status].rank - STATUS[b.status].rank) || a.title.localeCompare(b.title));
}

// ───────────── sections ─────────────

function weekNav() {
  const { start } = weekRange();
  const info = weekInfo(start, weekStart());
  const lbl = view.weekOffset === 0 ? 'This week' : view.weekOffset === -1 ? 'Last week' : view.weekOffset === 1 ? 'Next week' : `Week ${info.week}`;
  const atToday = view.weekOffset === 0 && sameDay(view.selectedDay, new Date());
  return `
  <div class="week-nav card slim">
    <button class="icon-btn" data-act="wk-prev" aria-label="Previous week">${ICONS.chevL}</button>
    <div class="wk-mid"><strong>${lbl}</strong><span>${fmtShort(start)} – ${fmtShort(addDays(start, 6))}</span></div>
    <button class="icon-btn" data-act="wk-next" aria-label="Next week">${ICONS.chevR}</button>
    ${atToday ? '' : '<button class="link today-btn" data-act="wk-today">Today</button>'}
  </div>`;
}

function dayChips() {
  const area = state.settings.activeArea;
  return `<div class="day-chips">${weekDays().map((d) => {
    const n = plannedTasksOn(d, area).length;
    const sel = sameDay(d, view.selectedDay), today = sameDay(d, new Date());
    return `<button class="day-chip ${sel ? 'sel' : ''} ${today ? 'today' : ''}" data-act="day-pick" data-d="${d.getTime()}">
      <small>${d.toLocaleDateString(undefined, { weekday: 'narrow' })}</small>
      <b>${d.getDate()}</b>
      <em>${n || '—'}</em></button>`;
  }).join('')}</div>`;
}

function dailyRow(t) {
  const active = state.activeTaskId === t.id;
  const notes = orderedNotes(t);
  return `
  <div class="row ${active ? 'active' : ''}">
    <div class="grow">
      <div class="t-title ${t.isCompleted ? 'strike' : ''}">${esc(t.title)}${active ? ' <span class="active-tag">ACTIVE</span>' : ''}</div>
      <div class="t-meta">${badge(t.category)}<span class="pill">${t.estimatedPomodoros} 🍅</span>
        ${notes.length ? `<span class="preview">${esc(notesLog(t).split('\n').pop().replace(/^\[[^\]]*\]\s*/, ''))}</span>` : ''}</div>
    </div>
    <button class="icon-btn ${notes.length ? 'has' : ''}" data-act="notes" data-id="${t.id}" aria-label="Notes">${ICONS.note}</button>
    <button class="btn sm ${t.isCompleted ? '' : 'good'}" data-act="plan-done" data-id="${t.id}" data-v="${t.isCompleted ? 0 : 1}">${t.isCompleted ? 'Undo' : 'Done'}</button>
    <button class="btn sm ${active ? 'on' : 'primary'}" data-act="plan-start" data-id="${t.id}">${active ? 'Active' : 'Start'}</button>
  </div>`;
}

function dailySection() {
  const area = state.settings.activeArea;
  const day = view.selectedDay;
  const tasks = plannedTasksOn(day, area);
  const isToday = sameDay(day, new Date());
  return `
  <div class="card">
    <div class="sec-head">
      <div><h2>${isToday ? 'Today’s plan' : 'Day plan'}</h2>
        <span class="muted">${day.toLocaleDateString(undefined, { weekday: 'long', month: 'short', day: 'numeric' })}</span></div>
      <span class="muted">${tasks.length} to pick from</span>
    </div>
    ${dayChips()}
    ${tasks.length ? `<div class="list">${tasks.map(dailyRow).join('')}</div>`
      : '<p class="empty">Nothing planned for this day. Add a task below, or pick another day.</p>'}
    <div class="quick-add">
      <input id="planQuick" data-input="plan-quick" data-enter="plan-quick-add" type="text" enterkeyhint="done"
        placeholder="Plan for ${esc(fmtShort(day))}…" value="${esc(view.quickTitle)}" autocomplete="off">
      <button class="btn primary sm" data-act="plan-quick-add">Add</button>
      <button class="btn sm" data-act="plan-more" aria-label="More options">More…</button>
    </div>
  </div>`;
}

function comparisonSection() {
  const rows = comparisonRows();
  const planned = rows.filter((r) => r.planned).length;
  const done = rows.filter((r) => r.status === 'done').length;
  const count = (s) => rows.filter((r) => r.status === s).length;
  return `
  <div class="card">
    <div class="sec-head"><h2>Planned vs completed</h2></div>
    <p class="muted small">${done}/${planned} planned done · ${count('upcoming')} upcoming · ${count('missed')} missed · ${count('unplanned')} unplanned</p>
    ${planned ? `<div class="bar"><i style="width:${(done / planned) * 100}%"></i></div>` : ''}
    ${rows.length ? `<div class="list">${rows.map((r) => `
      <div class="row cmp">
        <div class="grow">
          <div class="t-title">${esc(r.title)}</div>
          <div class="t-meta">${badge(r.category)}
            ${r.planned ? `<span class="pill">plan ${r.est} 🍅</span>` : ''}
            <span class="pill">done ${r.n}</span><span class="pill">${fmtMinutes(r.m)}</span></div>
        </div>
        <span class="status ${STATUS[r.status].cls}">${STATUS[r.status].label}</span>
        ${r.task ? `<div class="stack">
          <button class="btn xs ${r.task.isCompleted ? '' : 'good'}" data-act="plan-done" data-id="${r.id}" data-v="${r.task.isCompleted ? 0 : 1}">${r.task.isCompleted ? 'Undo' : 'Mark Done'}</button>
          <button class="btn xs" data-act="plan-edit" data-id="${r.id}">Edit</button></div>` : ''}
      </div>`).join('')}</div>`
      : '<p class="empty">Nothing planned or logged this week yet.</p>'}
  </div>`;
}

export function render() {
  const label = AREAS[state.settings.activeArea].label;
  return `
  <div class="page">
    <div class="page-head">
      <div><h1>Plan</h1><p class="muted small">${label} only. Schedule ahead, then compare against what you finished.</p></div>
      <button class="btn primary sm" data-act="plan-new">${ICONS.plus}<span>Plan</span></button>
    </div>
    ${weekNav()}
    ${dailySection()}
    ${comparisonSection()}
  </div>`;
}

// ───────────── actions ─────────────

function quickAdd() {
  const title = view.quickTitle.trim();
  if (!title) return;
  const area = state.settings.activeArea;
  const t = newTask({ title, category: categoriesFor(area)[0], area });
  addTask(t);
  planTask(t, view.selectedDay);
  view.quickTitle = '';
  toast(`Planned for ${fmtShort(view.selectedDay)}`);
}

export function init({ goTab }) {
  register('input', { 'plan-quick': (_, el) => { view.quickTitle = el.value; } });
  register('enter', { 'plan-quick-add': quickAdd });
  register('click', {
    'wk-prev': () => moveWeek(-1),
    'wk-next': () => moveWeek(1),
    'wk-today': () => { view.weekOffset = 0; view.selectedDay = startOfDay(new Date()); app.render(); },
    'day-pick': ({ d }) => { view.selectedDay = startOfDay(new Date(Number(d))); app.render(); },
    'plan-new': () => openTaskSheet({ plan: true, day: view.selectedDay }),
    'plan-more': () => openTaskSheet({ plan: true, day: view.selectedDay }),
    'plan-quick-add': quickAdd,
    'plan-edit': ({ id }) => openTaskSheet({ taskId: id }),
    'plan-done': ({ id, v }) => setCompleted(id, v === '1'),
    'plan-start': ({ id }) => {
      const t = getTask(id);
      if (!t) return;
      if (t.isCompleted) setCompleted(id, false);
      setActive(id);
      toast(`Active: ${t.title}`);
      goTab('focus');
    },
  });
}
