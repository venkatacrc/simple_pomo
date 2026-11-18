import {
  state, AREAS, categoriesFor, setCompleted, setActive, plannedDayRange, orderedNotes, notesLog, sameDay,
} from '../core.js';
import { esc, register, badge, ICONS, fmtShort, toast, app } from './common.js';
import { openTaskSheet, openNotesSheet, openTaskMenu } from './sheets.js';

const filter = { cat: 'All', showCompleted: false };
export const resetFilter = () => { filter.cat = 'All'; };

function categoriesInView() {
  const area = state.settings.activeArea;
  const seen = new Set();
  const out = ['All'];
  for (const c of categoriesFor(area)) if (!seen.has(c)) { seen.add(c); out.push(c); }
  for (const t of state.tasks) {
    if (t.area === area && t.category && !seen.has(t.category)) { seen.add(t.category); out.push(t.category); }
  }
  return out;
}

function visibleTasks() {
  const area = state.settings.activeArea;
  return state.tasks
    .filter((t) => !t.isArchived && t.area === area)
    .filter((t) => filter.showCompleted || !t.isCompleted)
    .filter((t) => filter.cat === 'All' || t.category === filter.cat)
    .sort((a, b) => (Number(a.isCompleted) - Number(b.isCompleted)) || (a.createdAt - b.createdAt));
}

function planSpan(t) {
  const r = plannedDayRange(t);
  if (!r) return '';
  return sameDay(r.start, r.end) ? fmtShort(r.start) : `${fmtShort(r.start)}–${fmtShort(r.end)}`;
}

function taskRow(t) {
  const active = state.activeTaskId === t.id;
  const hasNotes = orderedNotes(t).length > 0;
  const preview = hasNotes ? notesLog(t).split('\n').pop().replace(/^\[[^\]]*\]\s*/, '') : '';
  return `
  <div class="row task ${active ? 'active' : ''} ${t.isCompleted ? 'done' : ''}">
    <button class="check ${t.isCompleted ? 'on' : ''}" data-act="task-toggle" data-id="${t.id}" aria-label="${t.isCompleted ? 'Mark not done' : 'Mark done'}">${t.isCompleted ? ICONS.check : ''}</button>
    <div class="grow" data-act="task-edit" data-id="${t.id}">
      <div class="t-title">${esc(t.title)}${t.isPlanned ? ` <span class="plan-tag">📅 ${esc(planSpan(t))}</span>` : ''}</div>
      <div class="t-meta">${badge(t.category)}<span class="pill">${t.completedPomodoros}/${t.estimatedPomodoros} 🍅</span>
        ${preview ? `<span class="preview">${esc(preview)}</span>` : ''}</div>
    </div>
    <button class="icon-btn ${hasNotes ? 'has' : ''}" data-act="notes" data-id="${t.id}" aria-label="Notes">${ICONS.note}</button>
    <button class="icon-btn ${active ? 'on' : ''}" data-act="task-pick" data-id="${t.id}" aria-label="${active ? 'Active task' : 'Make active'}">${active ? ICONS.target : ICONS.play}</button>
    <button class="icon-btn" data-act="task-menu" data-id="${t.id}" aria-label="More">${ICONS.more}</button>
  </div>`;
}

export function render() {
  const area = state.settings.activeArea;
  const label = AREAS[area].label;
  const list = visibleTasks();
  return `
  <div class="page">
    <div class="page-head">
      <h1>${label} tasks</h1>
      <button class="btn primary sm" data-act="task-add">${ICONS.plus}<span>Add</span></button>
    </div>
    <div class="chips-scroll">${categoriesInView().map((c) =>
    `<button class="chip pill-chip ${filter.cat === c ? 'on' : ''}" data-act="task-filter" data-c="${esc(c)}">${esc(c)}</button>`).join('')}</div>
    <label class="switch-row slim"><span>Show completed</span>
      <input type="checkbox" data-change="task-showdone" ${filter.showCompleted ? 'checked' : ''}></label>
    <div class="list">
      ${list.length ? list.map(taskRow).join('') : `
        <div class="empty-state">
          <div class="big-emoji">🗂️</div>
          <h3>No ${label.toLowerCase()} tasks</h3>
          <p>Tasks you add here stay in ${label}. Use the switch at the top to see the other list.</p>
          <button class="btn primary" data-act="task-add">Add your first task</button>
        </div>`}
    </div>
  </div>`;
}

export function init({ goTab }) {
  register('change', {
    'task-showdone': (_, el) => { filter.showCompleted = el.checked; app.render(); },
  });
  register('click', {
    'task-add': () => openTaskSheet({}),
    'task-edit': ({ id }) => openTaskSheet({ taskId: id }),
    'task-filter': ({ c }) => { filter.cat = c; app.render(); },
    'task-toggle': ({ id }) => {
      const t = state.tasks.find((x) => x.id === id);
      if (t) setCompleted(id, !t.isCompleted);
    },
    'task-pick': ({ id }) => {
      if (state.activeTaskId === id) { setActive(null); return; }
      setActive(id);
      toast('Active task set');
      goTab('focus');
    },
    'task-menu': ({ id }) => openTaskMenu(id, { goFocus: () => goTab('focus') }),
  });
  register('click', { notes: ({ id }) => openNotesSheet(id) });
}
