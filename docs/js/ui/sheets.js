// Reusable sheets: task editor (optionally with plan dates), notes, session
// editor / group, and the task action menu.

import {
  state, AREAS, categoriesFor, getTask, newTask, addTask, updateTask, deleteTask, setCompleted,
  appendNoteTo, appendNote, planTask, unplanTask, orderedNotes, plannedDayRange, startOfDay, sameDay,
  setActive, upsertSession, deleteSession, manualSession, durationMinutes, inferArea, toISO,
  notesLog, save,
} from '../core.js';
import {
  $, $$, esc, openSheet, toast, badge, fmtDateTime, fmtShort, fmtTime, fmtDay, fmtMinutes,
  dateToInput, inputToDate, ICONS,
} from './common.js';

const areaOptions = (sel) =>
  Object.entries(AREAS).map(([k, v]) => `<option value="${k}" ${k === sel ? 'selected' : ''}>${v.label}</option>`).join('');
const catOptions = (area, sel) => {
  const list = [...categoriesFor(area)];
  if (sel && !list.includes(sel)) list.push(sel);
  return list.map((c) => `<option ${c === sel ? 'selected' : ''}>${esc(c)}</option>`).join('');
};

// ─────────────────────────── Task editor ───────────────────────────

/**
 * opts.taskId   edit an existing task
 * opts.plan     start with "Plan on a date" switched on
 * opts.day      default plan start day
 * opts.onDone   called after save
 */
export function openTaskSheet(opts = {}) {
  const existing = opts.taskId ? getTask(opts.taskId) : null;
  const area0 = existing ? existing.area : state.settings.activeArea;
  const cat0 = existing ? existing.category : categoriesFor(area0)[0];
  const range = existing ? plannedDayRange(existing) : null;
  const planOn = existing ? existing.isPlanned : !!opts.plan;
  const startDay = range ? range.start : startOfDay(opts.day || new Date());
  const endDay = range ? range.end : startDay;
  const multi = !sameDay(startDay, endDay);

  const prior = existing && orderedNotes(existing).length
    ? `<div class="notes-list small">${orderedNotes(existing).map((n) =>
      `<div class="note"><time>${esc(fmtDateTime(n.createdAt))}</time><p>${esc(n.text)}</p></div>`).join('')}</div>`
    : '';

  openSheet({
    title: existing ? 'Edit task' : (opts.plan ? 'Plan a task' : 'New task'),
    body: `
      <label class="fld">Title<input id="ts-title" type="text" placeholder="What needs doing?" value="${esc(existing?.title || '')}" autocomplete="off"></label>
      <div class="two">
        <label class="fld">Area<select id="ts-area">${areaOptions(area0)}</select></label>
        <label class="fld">Category<select id="ts-cat">${catOptions(area0, cat0)}</select></label>
      </div>
      <label class="fld">New category <span class="hint">(optional, added to the chosen area)</span>
        <input id="ts-newcat" type="text" placeholder="e.g. Finance" autocomplete="off"></label>
      <label class="fld">Estimated pomodoros
        <input id="ts-est" type="number" inputmode="numeric" min="1" max="40" value="${existing?.estimatedPomodoros ?? 1}"></label>

      <label class="switch-row"><span>Plan on a date</span><input id="ts-plan" type="checkbox" ${planOn ? 'checked' : ''}></label>
      <div id="ts-plan-fields" class="${planOn ? '' : 'hidden'}">
        <div class="two">
          <label class="fld">Starts<input id="ts-start" type="date" value="${dateToInput(startDay)}"></label>
          <label class="fld ${multi ? '' : 'dim'}" id="ts-end-wrap">Ends<input id="ts-end" type="date" value="${dateToInput(endDay)}" ${multi ? '' : 'disabled'}></label>
        </div>
        <label class="switch-row"><span>Spans multiple days</span><input id="ts-multi" type="checkbox" ${multi ? 'checked' : ''}></label>
      </div>

      <div class="fld">Notes <span class="hint">(append-only — earlier notes are kept)</span>
        ${prior}
        <textarea id="ts-note" rows="3" placeholder="Jot down thoughts, links, next steps…"></textarea>
      </div>`,
    footer: `${existing ? '<button class="btn danger" id="ts-del">Delete</button>' : ''}
             <span class="grow"></span>
             <button class="btn" data-close>Cancel</button>
             <button class="btn primary" id="ts-save">${existing ? 'Save' : 'Add'}</button>`,
    onMount(sheet) {
      const el = sheet.el;
      const q = (s) => $(s, el);
      q('#ts-area').addEventListener('change', () => {
        q('#ts-cat').innerHTML = catOptions(q('#ts-area').value, null);
      });
      q('#ts-plan').addEventListener('change', (e) => q('#ts-plan-fields').classList.toggle('hidden', !e.target.checked));
      q('#ts-multi').addEventListener('change', (e) => {
        q('#ts-end').disabled = !e.target.checked;
        q('#ts-end-wrap').classList.toggle('dim', !e.target.checked);
        if (!e.target.checked) q('#ts-end').value = q('#ts-start').value;
      });
      q('#ts-start').addEventListener('change', () => {
        if (!q('#ts-multi').checked || q('#ts-end').value < q('#ts-start').value) q('#ts-end').value = q('#ts-start').value;
      });
      if (existing) {
        q('#ts-del').addEventListener('click', () => {
          if (confirm(`Delete “${existing.title}”? Logged sessions are kept in Reports.`)) {
            deleteTask(existing.id); sheet.close(); opts.onDone?.();
          }
        });
      }
      q('#ts-save').addEventListener('click', () => {
        const title = q('#ts-title').value.trim();
        if (!title) { q('#ts-title').focus(); return; }
        const area = q('#ts-area').value;
        const newCat = q('#ts-newcat').value.trim();
        let category = q('#ts-cat').value;
        if (newCat) {
          category = newCat;
          const key = area === 'work' ? 'workCategories' : 'personalCategories';
          const other = area === 'work' ? 'personalCategories' : 'workCategories';
          state.settings[key] = [...state.settings[key].filter((c) => c !== newCat), newCat];
          state.settings[other] = state.settings[other].filter((c) => c !== newCat);
        }
        const est = Math.min(40, Math.max(1, parseInt(q('#ts-est').value, 10) || 1));
        const t = existing || newTask({ title, category, area, estimatedPomodoros: est });
        t.title = title; t.area = area; t.category = category; t.estimatedPomodoros = est;
        appendNoteTo(t, q('#ts-note').value);
        if (!existing) addTask(t); else updateTask(t);
        if (q('#ts-plan').checked) {
          const s = inputToDate(q('#ts-start').value);
          const e = q('#ts-multi').checked ? inputToDate(q('#ts-end').value) : s;
          planTask(t, s, e);
        } else if (t.isPlanned) {
          unplanTask(t.id);
        }
        save();
        sheet.close();
        opts.onDone?.(t);
      });
      setTimeout(() => !existing && q('#ts-title').focus(), 280);
    },
  });
}

// ─────────────────────────── Notes ───────────────────────────

/** Read/add notes on any task without making it the active one. */
export function openNotesSheet(taskId) {
  const t0 = getTask(taskId);
  if (!t0) return;
  const draw = (api) => {
    const t = getTask(taskId);
    const list = orderedNotes(t);
    api.body.innerHTML = `
      <p class="muted small">${badge(t.category)} <span class="sp"></span>${esc(t.title)}</p>
      ${list.length ? `<div class="notes-list">${list.map((n) =>
        `<div class="note"><time>${esc(fmtDateTime(n.createdAt))}</time><p>${esc(n.text)}</p></div>`).join('')}</div>`
        : '<p class="empty">No notes yet. Dump your thoughts here — they’ll be waiting when you start.</p>'}
      <label class="fld">Add a note
        <textarea id="nt-text" rows="4" placeholder="Ideas, links, what to do first…"></textarea></label>`;
    const ta = $('#nt-text', api.body);
    $('#nt-add', api.el).onclick = () => {
      if (appendNote(taskId, ta.value)) { toast('Note added'); draw(api); $('#nt-text', api.body).focus(); }
    };
  };
  openSheet({
    title: 'Notes',
    body: '',
    footer: `<span class="grow"></span><button class="btn" data-close>Done</button><button class="btn primary" id="nt-add">Add note</button>`,
    onMount: (api) => { draw(api); setTimeout(() => $('#nt-text', api.body)?.focus(), 280); },
  });
}

// ─────────────────────────── Task action menu ───────────────────────────

export function openTaskMenu(taskId, { goFocus } = {}) {
  const t = getTask(taskId);
  if (!t) return;
  const items = [
    ['edit', 'Edit…'],
    ['notes', 'Notes…'],
    ['start', 'Start working'],
    t.isPlanned ? ['unplan', 'Remove from plan'] : ['plan', 'Plan for today'],
    [t.isCompleted ? 'undone' : 'done', t.isCompleted ? 'Mark not done' : 'Mark done'],
    ['delete', 'Delete'],
  ];
  openSheet({
    title: t.title,
    body: `<div class="menu-list">${items.map(([k, l]) =>
      `<button class="menu-item ${k === 'delete' ? 'danger' : ''}" data-k="${k}">${l}</button>`).join('')}</div>`,
    onMount(sheet) {
      sheet.body.addEventListener('click', (e) => {
        const k = e.target.closest('[data-k]')?.dataset.k;
        if (!k) return;
        sheet.close();
        if (k === 'edit') openTaskSheet({ taskId });
        else if (k === 'notes') openNotesSheet(taskId);
        else if (k === 'start') { setActive(taskId); goFocus?.(); }
        else if (k === 'plan') { planTask(t, new Date()); toast('Planned for today'); }
        else if (k === 'unplan') unplanTask(taskId);
        else if (k === 'done') setCompleted(taskId, true);
        else if (k === 'undone') setCompleted(taskId, false);
        else if (k === 'delete' && confirm(`Delete “${t.title}”?`)) deleteTask(taskId);
      });
    },
  });
}

// ─────────────────────────── Session editor ───────────────────────────

export function openSessionSheet({ sessionId, defaults = {}, onDone } = {}) {
  const existing = sessionId ? state.sessions.find((s) => s.id === sessionId) : null;
  const area0 = existing?.area || defaults.area || state.settings.activeArea;
  const cat0 = existing?.category || defaults.category || categoriesFor(area0)[0];
  const date0 = existing ? existing.startedAt : (defaults.date || new Date());
  const min0 = existing ? Math.max(5, Math.round(durationMinutes(existing))) : (defaults.minutes || 25);

  openSheet({
    title: existing ? 'Edit entry' : 'Log past work',
    body: `
      <label class="fld">What did you work on?
        <input id="se-title" type="text" value="${esc(existing?.taskTitle || defaults.title || '')}" autocomplete="off"></label>
      <div class="two">
        <label class="fld">Area<select id="se-area">${areaOptions(area0)}</select></label>
        <label class="fld">Category<select id="se-cat">${catOptions(area0, cat0)}</select></label>
      </div>
      <div class="two">
        <label class="fld">Date<input id="se-date" type="date" max="${dateToInput(new Date())}" value="${dateToInput(date0)}"></label>
        <label class="fld">Minutes<input id="se-min" type="number" inputmode="numeric" min="1" max="600" step="5" value="${min0}"></label>
      </div>
      <label class="fld">Session note <span class="hint">(appended to the task)</span>
        <textarea id="se-note" rows="3"></textarea></label>`,
    footer: `${existing ? '<button class="btn danger" id="se-del">Delete</button>' : ''}
             <span class="grow"></span><button class="btn" data-close>Cancel</button>
             <button class="btn primary" id="se-save">${existing ? 'Save' : 'Add'}</button>`,
    onMount(sheet) {
      const q = (s) => $(s, sheet.el);
      q('#se-area').addEventListener('change', () => { q('#se-cat').innerHTML = catOptions(q('#se-area').value, null); });
      if (existing) q('#se-del').addEventListener('click', () => {
        if (confirm('Delete this entry?')) { deleteSession(existing.id); sheet.close(); onDone?.(); }
      });
      q('#se-save').addEventListener('click', () => {
        const title = q('#se-title').value.trim();
        if (!title) { q('#se-title').focus(); return; }
        const area = q('#se-area').value, category = q('#se-cat').value;
        const minutes = Math.max(1, parseInt(q('#se-min').value, 10) || 25);
        const day = inputToDate(q('#se-date').value);
        // keep the original time of day when only the date changes; new entries start at 9:00
        const base = existing ? new Date(existing.startedAt) : new Date(day.getFullYear(), day.getMonth(), day.getDate(), 9, 0);
        const when = new Date(day.getFullYear(), day.getMonth(), day.getDate(), base.getHours(), base.getMinutes());
        let s = existing || manualSession({ title, category, area, date: when, minutes });
        s.taskTitle = title; s.area = area; s.category = category;
        s.startedAt = when; s.endedAt = new Date(when.getTime() + minutes * 60000); s.isManual = true;

        const noteText = q('#se-note').value.trim();
        if (noteText) {
          let t = (s.taskId && getTask(s.taskId)) ||
            state.tasks.find((x) => x.title.toLowerCase() === title.toLowerCase());
          if (!t) { t = newTask({ title, category, area }); addTask(t); }
          appendNote(t.id, noteText);
          s.taskId = t.id;
        }
        upsertSession(s);
        sheet.close();
        onDone?.();
      });
      setTimeout(() => !existing && q('#se-title').focus(), 280);
    },
  });
}

/** Several sessions make up one Accomplishments row — edit each, add more, or open notes. */
export function openGroupSheet({ date, title, category, area }) {
  const matching = () => state.sessions.filter((s) =>
    s.phase === 'focus' && sameDay(s.startedAt, date) && s.taskTitle === title && s.category === category)
    .sort((a, b) => a.startedAt - b.startedAt);
  const draw = (api) => {
    const list = matching();
    const task = state.tasks.find((t) => t.title.toLowerCase() === title.toLowerCase());
    api.body.innerHTML = `
      <p class="muted small">${esc(fmtDay(date))} <span class="sp"></span>${badge(category)}</p>
      <div class="menu-list">
        ${list.map((s) => `
          <button class="menu-item between" data-id="${s.id}">
            <span>${esc(fmtTime(s.startedAt))} · ${esc(fmtMinutes(durationMinutes(s)))}${s.isManual ? ' <em class="tag">Manual</em>' : ''}</span>
            <span class="muted">Edit</span>
          </button>`).join('') || '<p class="empty">No entries left.</p>'}
      </div>
      <div class="row-btns">
        <button class="btn" id="gr-add">+ Add more time</button>
        ${task ? '<button class="btn" id="gr-notes">Notes…</button>' : ''}
      </div>`;
    api.body.querySelectorAll('[data-id]').forEach((b) => b.addEventListener('click', () =>
      openSessionSheet({ sessionId: b.dataset.id, onDone: () => draw(api) })));
    $('#gr-add', api.body).onclick = () => openSessionSheet({
      defaults: { title, category, area, date, minutes: 25 }, onDone: () => draw(api) });
    if (task) $('#gr-notes', api.body).onclick = () => openNotesSheet(task.id);
  };
  openSheet({
    title,
    body: '',
    footer: '<span class="grow"></span><button class="btn" data-close>Done</button>',
    onMount: draw,
  });
}
