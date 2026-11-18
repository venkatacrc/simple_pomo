import {
  state, PHASES, AREAS, load, subscribe, saveNow, updateSettings, weekInfo, focusSessionsIn,
  startOfDay, endOfDay, getTask,
} from './core.js';
import * as timer from './timer.js';
import { $, $$, register, initEvents, ICONS, fmtShort, toast, app } from './ui/common.js';
import * as focus from './ui/focus.js';
import * as tasks from './ui/tasks.js';
import * as plan from './ui/plan.js';
import * as reports from './ui/reports.js';
import * as settings from './ui/settings.js';

const TABS = [
  ['focus', 'Focus', ICONS.timer, focus],
  ['tasks', 'Tasks', ICONS.tasks, tasks],
  ['plan', 'Plan', ICONS.plan, plan],
  ['reports', 'Reports', ICONS.reports, reports],
];
const TAB_KEY = 'simplepomo.tab';
let tab = localStorage.getItem(TAB_KEY);
if (!TABS.some((t) => t[0] === tab)) tab = 'focus';

function goTab(name) {
  if (!TABS.some((t) => t[0] === name)) return;
  tab = name;
  try { localStorage.setItem(TAB_KEY, name); } catch { /* ignore */ }
  render({ keepScroll: false });
  window.scrollTo(0, 0);
}

// ───────────── header / tabs ─────────────

function headerHtml() {
  const week = weekInfo(new Date(), state.prefs.weekStart || 0);
  const today = focusSessionsIn({ start: startOfDay(new Date()), end: endOfDay(new Date()) }, state.settings.activeArea).length;
  const area = state.settings.activeArea;
  return `
  <div class="hdr-in">
    <div class="area-seg" role="tablist" aria-label="Area">${Object.entries(AREAS).map(([k, v]) =>
    `<button class="${k === area ? 'on' : ''}" data-act="area" data-a="${k}" role="tab" aria-selected="${k === area}">${v.label}</button>`).join('')}</div>
    <div class="week-badge"><b>Week ${week.week}</b><span>${fmtShort(week.start)} – ${fmtShort(week.end)}</span></div>
    <div class="hdr-right">
      <span class="today-pill" title="Pomodoros today">🍅 ${today}</span>
      <button class="icon-btn" data-act="open-settings" aria-label="Settings">${ICONS.gear}</button>
    </div>
  </div>`;
}

function tabsHtml() {
  return TABS.map(([k, label, icon]) =>
    `<button class="${k === tab ? 'on' : ''}" data-act="tab" data-t="${k}" aria-current="${k === tab}">${icon}<span>${label}</span></button>`).join('');
}

// ───────────── theme ─────────────

function applyTheme() {
  const S = timer.snapshot();
  const p = PHASES[S.phase];
  document.documentElement.style.setProperty('--bg', p.bg);
  document.documentElement.style.setProperty('--tint', p.tint);
  document.body.dataset.phase = S.phase;
  $('meta[name="theme-color"]')?.setAttribute('content', p.bg);
  updateTitle();
}

function updateTitle() {
  const S = timer.snapshot();
  document.title = S.running
    ? `${timer.displayTime(S.remainingMs)} · ${PHASES[S.phase].title}`
    : 'Simple Pomo';
}

// ───────────── render (preserves scroll + focus + horizontal scrollers) ─────────────

const H_SCROLLERS = '.presets, .chips-scroll, .day-chips';

function render({ keepScroll = true } = {}) {
  const y = window.scrollY;
  const ae = document.activeElement;
  const focusId = ae && ae.id && ae !== document.body ? ae.id : null;
  const sel = focusId && typeof ae.selectionStart === 'number' ? [ae.selectionStart, ae.selectionEnd] : null;
  const hs = $$(H_SCROLLERS).map((el) => el.scrollLeft);

  const mod = TABS.find((t) => t[0] === tab)[3];
  $('#hdr').innerHTML = headerHtml();
  $('#view').innerHTML = mod.render();
  $('#tabs').innerHTML = tabsHtml();
  applyTheme();

  $$(H_SCROLLERS).forEach((el, i) => { if (hs[i] != null) el.scrollLeft = hs[i]; });
  if (keepScroll) window.scrollTo(0, y);
  if (focusId) {
    const el = document.getElementById(focusId);
    if (el) {
      el.focus({ preventScroll: true });
      if (sel && el.setSelectionRange) { try { el.setSelectionRange(sel[0], sel[1]); } catch { /* ignore */ } }
    }
  }
}

// ───────────── boot ─────────────

function boot() {
  load();
  initEvents();
  app.render = render;
  app.goTab = goTab;

  register('click', {
    tab: ({ t }) => goTab(t),
    area: ({ a }) => {
      if (state.settings.activeArea === a) return;
      updateSettings({ activeArea: a });
      tasks.resetFilter();
      focus.syncDraft();
    },
  });
  focus.init();
  tasks.init({ goTab });
  plan.init({ goTab });
  reports.init();
  settings.init();

  focus.syncDraft();
  let lastActive = state.activeTaskId;
  subscribe(() => {
    if (state.activeTaskId !== lastActive) {
      const prev = lastActive;
      lastActive = state.activeTaskId;
      if (prev && getTask(prev)) focus.flushDraftNote(prev);
      focus.syncDraft();
    }
    render();
  });

  timer.onTimer((type, detail) => {
    if (type === 'tick') { focus.updateTick(); updateTitle(); }
    else if (type === 'state') render();
    else if (type === 'phase') focus.flushDraftNote();
    else if (type === 'complete') {
      toast(detail?.wasFocus ? '🍅 Pomodoro complete — take a break' : 'Break over — back to focus', 4000);
    }
  });

  timer.initTimer();
  render();

  setInterval(() => { focus.updateClock(); }, 60000);
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) saveNow();
    else { render(); focus.updateClock(); }
  });
  addEventListener('pagehide', saveNow);

  if ('serviceWorker' in navigator && location.protocol.startsWith('http')) {
    const hadController = !!navigator.serviceWorker.controller;
    navigator.serviceWorker.register('./sw.js').catch((e) => console.warn('SW registration failed', e));
    navigator.serviceWorker.addEventListener('controllerchange', () => {
      if (hadController) toast('Updated — reload to get the latest version', 5000);
    });
  }
}

boot();
