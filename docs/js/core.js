// Simple Pomo (web) — data model, storage, date helpers, Walmart fiscal calendar.
// The JSON shape intentionally matches the macOS app's store.json so data can
// be exported from one and imported into the other.

export const LS_KEY = 'simplepomo.store.v1';
export const LS_PREFS = 'simplepomo.prefs.v1';

// ───────────────────────────── Constants ─────────────────────────────

export const PHASES = {
  focus:      { title: 'Pomodoro',    tint: '#db4f4f', bg: '#bd4545' },
  shortBreak: { title: 'Short Break', tint: '#459e8c', bg: '#3b8578' },
  longBreak:  { title: 'Long Break',  tint: '#4d78bd', bg: '#40669e' },
};
export const PHASE_ORDER = ['focus', 'shortBreak', 'longBreak'];

export const PRESETS = [
  { id: 'micro',        title: 'Micro',     f: 5,   s: 1,  l: 5 },
  { id: 'sprint',       title: 'Sprint',    f: 10,  s: 2,  l: 10 },
  { id: 'short',        title: 'Short',     f: 15,  s: 3,  l: 10 },
  { id: 'focus',        title: 'Focus',     f: 20,  s: 5,  l: 15 },
  { id: 'classic',      title: 'Classic',   f: 25,  s: 5,  l: 15 },
  { id: 'halfHour',     title: 'Half Hour', f: 30,  s: 5,  l: 15 },
  { id: 'power',        title: 'Power',     f: 40,  s: 8,  l: 20 },
  { id: 'threeQuarter', title: '¾ Hour',    f: 45,  s: 10, l: 20 },
  { id: 'extended',     title: 'Extended',  f: 50,  s: 10, l: 20 },
  { id: 'hour',         title: 'Hour',      f: 60,  s: 10, l: 20 },
  { id: 'long',         title: 'Long',      f: 75,  s: 15, l: 25 },
  { id: 'deepWork',     title: 'Deep Work', f: 90,  s: 20, l: 30 },
  { id: 'marathon',     title: 'Marathon',  f: 120, s: 25, l: 40 },
];

export const AREAS = { work: { label: 'Work' }, personal: { label: 'Personal' } };
const PERSONAL_NAMES = new Set([
  'personal', 'reading', 'health', 'home', 'family', 'hobby', 'life', 'errands', 'fitness',
]);
export const inferArea = (category) =>
  PERSONAL_NAMES.has(String(category || '').trim().toLowerCase()) ? 'personal' : 'work';

export const SOUNDS = ['Glass', 'Ping', 'Tink', 'Pop', 'Hero', 'Funk', 'Submarine'];

// ───────────────────────────── Utilities ─────────────────────────────

export function uuid() {
  if (globalThis.crypto && crypto.randomUUID) return crypto.randomUUID().toUpperCase();
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
  }).toUpperCase();
}

/** ISO-8601 without fractional seconds (what Swift's .iso8601 strategy expects). */
export const toISO = (d) => new Date(d).toISOString().replace(/\.\d{3}Z$/, 'Z');
export const toDate = (s) => {
  const d = new Date(s);
  return Number.isNaN(d.getTime()) ? new Date() : d;
};

export const startOfDay = (d) => { const x = new Date(d); x.setHours(0, 0, 0, 0); return x; };
export const endOfDay = (d) => { const x = new Date(d); x.setHours(23, 59, 59, 999); return x; };
export const addDays = (d, n) => { const x = new Date(d); x.setDate(x.getDate() + n); return x; };
export const sameDay = (a, b) => startOfDay(a).getTime() === startOfDay(b).getTime();
/** Whole calendar days from a to b (DST-safe). */
export const dayDiff = (a, b) => Math.round((startOfDay(b) - startOfDay(a)) / 864e5);

export function startOfWeek(d, weekStart = 0) {
  const x = startOfDay(d);
  return addDays(x, -((x.getDay() - weekStart + 7) % 7));
}

/** Week info using US-style numbering (the week containing Jan 1 is week 1). */
export function weekInfo(d, weekStart = 0) {
  const start = startOfWeek(d, weekStart);
  const end = addDays(start, 6);
  const year = end.getFullYear();
  const w1 = startOfWeek(new Date(year, 0, 1), weekStart);
  const week = Math.round((start - w1) / (7 * 864e5)) + 1;
  return { start, end, week, year };
}

// ───────────────────────────── Walmart fiscal calendar ─────────────────────────────
// FY runs Feb 1 → Jan 31 and is named by the calendar year in which it ends.

export function quarterBounds(quarter, fiscalYear) {
  const y = fiscalYear - 1;
  const defs = {
    1: [new Date(y, 1, 1), new Date(y, 3, 30)],
    2: [new Date(y, 4, 1), new Date(y, 6, 31)],
    3: [new Date(y, 7, 1), new Date(y, 9, 31)],
    4: [new Date(y, 10, 1), new Date(fiscalYear, 0, 31)],
  };
  const [s, e] = defs[quarter];
  return { start: startOfDay(s), end: endOfDay(e) };
}

export const fiscalLabel = (q, fy) => `Q${q}FY${String(fy % 100).padStart(2, '0')}`;

export function fiscalYearRange(fy) {
  return { start: startOfDay(new Date(fy - 1, 1, 1)), end: endOfDay(new Date(fy, 0, 31)) };
}

export function walmartFiscal(now = new Date()) {
  const today = startOfDay(now);
  const y = today.getFullYear();
  const m = today.getMonth() + 1;
  const fiscalYear = m === 1 ? y : y + 1;
  const quarter = m >= 2 && m <= 4 ? 1 : m >= 5 && m <= 7 ? 2 : m >= 8 && m <= 10 ? 3 : 4;
  const { start, end } = quarterBounds(quarter, fiscalYear);
  const nextQuarter = quarter === 4 ? 1 : quarter + 1;
  const nextFiscalYear = quarter === 4 ? fiscalYear + 1 : fiscalYear;
  const nextStart = quarterBounds(nextQuarter, nextFiscalYear).start;
  return {
    quarter, fiscalYear, start, end,
    nextQuarter, nextFiscalYear, nextStart,
    label: fiscalLabel(quarter, fiscalYear),
    longLabel: `Q${quarter} FY${fiscalYear}`,
    nextLabel: fiscalLabel(nextQuarter, nextFiscalYear),
    daysUntilNextQuarter: Math.max(0, dayDiff(today, nextStart)),
  };
}

// ───────────────────────────── "The Present" season clock ─────────────────────────────

export const SEASONS = {
  winter: { label: 'Winter', color: [245, 250, 255] },
  spring: { label: 'Spring', color: [46, 191, 77] },
  summer: { label: 'Summer', color: [255, 214, 33] },
  autumn: { label: 'Autumn', color: [219, 56, 46] },
};
const SEASON_ORDER = ['winter', 'spring', 'summer', 'autumn'];
export const rgb = (c) => `rgb(${c[0] | 0},${c[1] | 0},${c[2] | 0})`;

export function seasonClock(now = new Date()) {
  const y = now.getFullYear();
  const thisWinter = new Date(y, 11, 21);
  const start = now >= thisWinter ? thisWinter : new Date(y - 1, 11, 21);
  const end = new Date(start.getFullYear() + 1, 11, 21);
  const total = end - start;
  const progress = Math.max(0, Math.min(1, (now - start) / total));
  const idx = progress < 0.25 ? 0 : progress < 0.5 ? 1 : progress < 0.75 ? 2 : 3;
  const target = [0.25, 0.5, 0.75, 1][idx];
  const targetDate = new Date(start.getTime() + total * target);
  return {
    progress,
    season: SEASON_ORDER[idx],
    nextSeason: SEASON_ORDER[(idx + 1) % 4],
    cycleDay: dayDiff(start, now) + 1,
    cycleLength: dayDiff(start, end),
    daysUntilNextSeason: Math.max(0, dayDiff(now, targetDate)),
  };
}

// ───────────────────────────── State ─────────────────────────────

export const defaultSettings = () => ({
  focusMinutes: 25, shortBreakMinutes: 5, longBreakMinutes: 15, longBreakEvery: 4,
  autoStartBreaks: true, autoStartPomodoros: false, playSound: true, soundName: 'Glass',
  workCategories: ['Work', 'Study', 'Side Project'],
  personalCategories: ['Personal', 'Reading', 'Health'],
  activeArea: 'work',
});

export const defaultPrefs = () => ({ keepAwake: true, vibrate: true, weekStart: 0 });

export const state = {
  tasks: [],
  sessions: [],
  settings: defaultSettings(),
  prefs: defaultPrefs(),
  activeTaskId: null,
};

const listeners = new Set();
export const subscribe = (fn) => { listeners.add(fn); return () => listeners.delete(fn); };
let notifyQueued = false;
function notify() {
  if (notifyQueued) return;
  notifyQueued = true;
  queueMicrotask(() => { notifyQueued = false; listeners.forEach((f) => f()); });
}

// ── normalisation (tolerant of older / Mac-written files) ──

export function normalizeSettings(r = {}) {
  const s = defaultSettings();
  for (const k of ['focusMinutes', 'shortBreakMinutes', 'longBreakMinutes', 'longBreakEvery']) {
    if (Number.isFinite(r[k]) && r[k] > 0) s[k] = Math.round(r[k]);
  }
  for (const k of ['autoStartBreaks', 'autoStartPomodoros', 'playSound']) {
    if (typeof r[k] === 'boolean') s[k] = r[k];
  }
  if (typeof r.soundName === 'string') s.soundName = r.soundName;
  if (r.activeArea === 'work' || r.activeArea === 'personal') s.activeArea = r.activeArea;
  if (Array.isArray(r.workCategories) || Array.isArray(r.personalCategories)) {
    if (Array.isArray(r.workCategories)) s.workCategories = r.workCategories.filter(Boolean);
    if (Array.isArray(r.personalCategories)) s.personalCategories = r.personalCategories.filter(Boolean);
  } else if (Array.isArray(r.categories)) {
    s.workCategories = r.categories.filter((c) => inferArea(c) === 'work');
    s.personalCategories = r.categories.filter((c) => inferArea(c) === 'personal');
    if (!s.workCategories.length) s.workCategories = ['Work'];
    if (!s.personalCategories.length) s.personalCategories = ['Personal'];
  }
  return s;
}

export function normalizeTask(r) {
  const t = {
    id: r.id || uuid(),
    title: String(r.title ?? ''),
    category: String(r.category ?? 'Work'),
    area: r.area === 'work' || r.area === 'personal' ? r.area : inferArea(r.category),
    estimatedPomodoros: Number.isFinite(r.estimatedPomodoros) ? r.estimatedPomodoros : 1,
    completedPomodoros: Number.isFinite(r.completedPomodoros) ? r.completedPomodoros : 0,
    notes: String(r.notes ?? ''),
    noteEntries: (r.noteEntries || []).map((n) => ({
      id: n.id || uuid(), text: String(n.text ?? ''), createdAt: toDate(n.createdAt),
    })),
    isCompleted: !!r.isCompleted,
    isArchived: !!r.isArchived,
    createdAt: r.createdAt ? toDate(r.createdAt) : new Date(),
    plannedFor: r.plannedFor ? toDate(r.plannedFor) : null,
    plannedUntil: r.plannedUntil ? toDate(r.plannedUntil) : null,
    isPlanned: !!r.isPlanned,
  };
  if (!t.noteEntries.length && t.notes.trim()) {
    t.noteEntries = [{ id: uuid(), text: t.notes.trim(), createdAt: t.createdAt }];
  }
  return t;
}

export function normalizeSession(r) {
  return {
    id: r.id || uuid(),
    taskId: r.taskId || null,
    taskTitle: String(r.taskTitle ?? 'Focus'),
    category: String(r.category ?? 'Uncategorized'),
    area: r.area === 'work' || r.area === 'personal' ? r.area : inferArea(r.category),
    phase: r.phase || 'focus',
    startedAt: toDate(r.startedAt),
    endedAt: toDate(r.endedAt),
    isManual: !!r.isManual,
  };
}

// ── persistence ──

export function exportData() {
  const s = state.settings;
  return {
    tasks: state.tasks.map((t) => ({
      id: t.id, title: t.title, category: t.category, area: t.area,
      estimatedPomodoros: t.estimatedPomodoros, completedPomodoros: t.completedPomodoros,
      notes: t.notes,
      noteEntries: t.noteEntries.map((n) => ({ id: n.id, text: n.text, createdAt: toISO(n.createdAt) })),
      isCompleted: t.isCompleted, isArchived: t.isArchived,
      createdAt: toISO(t.createdAt),
      plannedFor: t.plannedFor ? toISO(t.plannedFor) : undefined,
      plannedUntil: t.plannedUntil ? toISO(t.plannedUntil) : undefined,
      isPlanned: t.isPlanned,
    })),
    sessions: state.sessions.map((x) => ({
      id: x.id, taskId: x.taskId || undefined, taskTitle: x.taskTitle, category: x.category,
      area: x.area, phase: x.phase, startedAt: toISO(x.startedAt), endedAt: toISO(x.endedAt),
      isManual: x.isManual,
    })),
    settings: {
      focusMinutes: s.focusMinutes, shortBreakMinutes: s.shortBreakMinutes,
      longBreakMinutes: s.longBreakMinutes, longBreakEvery: s.longBreakEvery,
      autoStartBreaks: s.autoStartBreaks, autoStartPomodoros: s.autoStartPomodoros,
      playSound: s.playSound, soundName: s.soundName,
      workCategories: s.workCategories, personalCategories: s.personalCategories,
      activeArea: s.activeArea,
    },
  };
}

/** mode: 'replace' swaps everything; 'merge' adds/overwrites by id and keeps the rest. */
export function importData(obj, mode = 'replace') {
  if (!obj || typeof obj !== 'object') throw new Error('Not a Simple Pomo file');
  const tasks = (obj.tasks || []).map(normalizeTask);
  const sessions = (obj.sessions || []).map(normalizeSession);
  if (mode === 'merge') {
    const tmap = new Map(state.tasks.map((t) => [t.id, t]));
    tasks.forEach((t) => tmap.set(t.id, t));
    state.tasks = [...tmap.values()];
    const smap = new Map(state.sessions.map((x) => [x.id, x]));
    sessions.forEach((x) => smap.set(x.id, x));
    state.sessions = [...smap.values()];
  } else {
    state.tasks = tasks;
    state.sessions = sessions;
    if (obj.settings) state.settings = normalizeSettings(obj.settings);
  }
}

let saveTimer = null;
export function saveNow() {
  clearTimeout(saveTimer);
  try {
    localStorage.setItem(LS_KEY, JSON.stringify(exportData()));
    localStorage.setItem(LS_PREFS, JSON.stringify({ ...state.prefs, activeTaskId: state.activeTaskId }));
  } catch (e) {
    console.error('Simple Pomo: save failed', e);
  }
}
export function save() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(saveNow, 300);
  notify();
}

export function load() {
  try {
    const raw = localStorage.getItem(LS_KEY);
    if (raw) importData(JSON.parse(raw), 'replace');
  } catch (e) {
    console.error('Simple Pomo: load failed', e);
  }
  try {
    const p = JSON.parse(localStorage.getItem(LS_PREFS) || '{}');
    state.prefs = { ...defaultPrefs(), ...p };
    delete state.prefs.activeTaskId;
    state.activeTaskId = p.activeTaskId && state.tasks.some((t) => t.id === p.activeTaskId) ? p.activeTaskId : null;
  } catch { /* ignore */ }
}

addEventListener('pagehide', saveNow);
addEventListener('visibilitychange', () => { if (document.hidden) saveNow(); });

// ───────────────────────────── Settings / prefs ─────────────────────────────

export function updateSettings(patch) {
  state.settings = { ...state.settings, ...patch };
  save();
}
export function updatePrefs(patch) {
  state.prefs = { ...state.prefs, ...patch };
  save();
}
export const categoriesFor = (area) => {
  const list = area === 'work' ? state.settings.workCategories : state.settings.personalCategories;
  return list.length ? list : [AREAS[area].label];
};
export function addCategory(name, area) {
  const n = String(name || '').trim();
  if (!n) return;
  const s = state.settings;
  const w = s.workCategories.filter((c) => c !== n);
  const p = s.personalCategories.filter((c) => c !== n);
  if (area === 'work') w.push(n); else p.push(n);
  updateSettings({ workCategories: w, personalCategories: p });
}
export function removeCategory(name, area) {
  const key = area === 'work' ? 'workCategories' : 'personalCategories';
  updateSettings({ [key]: state.settings[key].filter((c) => c !== name) });
}

// ───────────────────────────── Tasks ─────────────────────────────

export const getTask = (id) => state.tasks.find((t) => t.id === id) || null;
export const activeTask = () => (state.activeTaskId ? getTask(state.activeTaskId) : null);

export function newTask({ title, category, area, estimatedPomodoros = 1 }) {
  return normalizeTask({ title, category, area, estimatedPomodoros, createdAt: toISO(new Date()) });
}

export function notesLog(t) {
  const entries = [...t.noteEntries].sort((a, b) => a.createdAt - b.createdAt);
  if (!entries.length) return t.notes;
  const fmt = (d) => d.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });
  return entries.map((n) => `[${fmt(n.createdAt)}] ${n.text}`).join('\n');
}
export const orderedNotes = (t) => [...t.noteEntries].sort((a, b) => a.createdAt - b.createdAt);

export function appendNoteTo(t, text, at = new Date()) {
  const trimmed = String(text || '').trim();
  if (!trimmed) return false;
  t.noteEntries.push({ id: uuid(), text: trimmed, createdAt: at });
  t.notes = notesLog(t);
  return true;
}

export function addTask(t) { state.tasks.push(t); save(); return t; }
export function updateTask(t) {
  const i = state.tasks.findIndex((x) => x.id === t.id);
  if (i >= 0) { state.tasks[i] = t; save(); }
}
export function deleteTask(id) {
  state.tasks = state.tasks.filter((t) => t.id !== id);
  if (state.activeTaskId === id) state.activeTaskId = null;
  save();
}
export function setCompleted(id, done) {
  const t = getTask(id);
  if (t) { t.isCompleted = done; save(); }
}
export function incrementCompleted(id) {
  const t = getTask(id);
  if (t) { t.completedPomodoros += 1; save(); }
}
export function appendNote(id, text) {
  const t = getTask(id);
  if (!t) return false;
  const ok = appendNoteTo(t, text);
  if (ok) save();
  return ok;
}
export function setActive(id) { state.activeTaskId = id; save(); }

/** Quick capture: reuse an open task with the same title/category/area, else create one. */
export function setActiveTask(title, category, area) {
  const trimmed = String(title || '').trim();
  if (!trimmed) return null;
  let t = state.tasks.find((x) =>
    !x.isCompleted && !x.isArchived && x.area === area && x.category === category &&
    x.title.toLowerCase() === trimmed.toLowerCase());
  if (!t) {
    t = newTask({ title: trimmed, category, area });
    state.tasks.push(t);
  }
  state.activeTaskId = t.id;
  save();
  return t;
}

// ── planning ──

export function plannedDayRange(t) {
  if (!t.isPlanned || !t.plannedFor) return null;
  const a = startOfDay(t.plannedFor);
  const b = startOfDay(t.plannedUntil || t.plannedFor);
  return a <= b ? { start: a, end: b } : { start: b, end: a };
}
export function isPlannedOn(t, day) {
  const r = plannedDayRange(t);
  if (!r) return false;
  const d = startOfDay(day);
  return d >= r.start && d <= r.end;
}
/** True while today is on/before the last planned day — still ahead, not missed. */
export function planWindowOpen(t, asOf = new Date()) {
  const r = plannedDayRange(t);
  return !!r && r.end >= startOfDay(asOf);
}

export function planTask(t, start, end) {
  const a = startOfDay(start);
  const b = startOfDay(end || start);
  t.isPlanned = true;
  t.plannedFor = a <= b ? a : b;
  t.plannedUntil = a <= b ? b : a;
  if (sameDay(t.plannedFor, t.plannedUntil)) t.plannedUntil = null;
  if (!state.tasks.includes(t)) {
    const i = state.tasks.findIndex((x) => x.id === t.id);
    if (i >= 0) state.tasks[i] = t; else state.tasks.push(t);
  }
  save();
}
export function unplanTask(id) {
  const t = getTask(id);
  if (!t) return;
  t.isPlanned = false; t.plannedFor = null; t.plannedUntil = null;
  save();
}

export function plannedTasksOn(day, area) {
  return state.tasks
    .filter((t) => t.isPlanned && !t.isArchived && (!area || t.area === area) && isPlannedOn(t, day))
    .sort((a, b) => (a.plannedFor - b.plannedFor) || a.title.localeCompare(b.title));
}
export function plannedTasksIn(range, area) {
  const rs = startOfDay(range.start), re = startOfDay(range.end);
  return state.tasks
    .filter((t) => {
      if (!t.isPlanned || t.isArchived || (area && t.area !== area)) return false;
      const r = plannedDayRange(t);
      return r && r.start <= re && r.end >= rs;
    })
    .sort((a, b) => (a.plannedFor - b.plannedFor) || a.title.localeCompare(b.title));
}

// ── sessions ──

const inRange = (s, r) => s.startedAt >= r.start && s.startedAt <= r.end;
const matchesTask = (s, t) => s.taskId === t.id || s.taskTitle.toLowerCase() === t.title.toLowerCase();

export const focusSessionsFor = (t, r) =>
  state.sessions.filter((s) => s.phase === 'focus' && inRange(s, r) && matchesTask(s, t));
export const focusSessionCount = (t, r) => focusSessionsFor(t, r).length;
export const focusMinutes = (t, r) =>
  focusSessionsFor(t, r).reduce((n, s) => n + durationMinutes(s), 0);
export const durationMinutes = (s) => Math.max(0, (s.endedAt - s.startedAt) / 60000);

export function focusSessionsIn(range, area) {
  return state.sessions.filter((s) => s.phase === 'focus' && (!area || s.area === area) && inRange(s, range));
}

export function recordSession(s) { state.sessions.push(s); save(); }
export function upsertSession(s) {
  const i = state.sessions.findIndex((x) => x.id === s.id);
  if (i >= 0) state.sessions[i] = s; else state.sessions.push(s);
  save();
}
export function deleteSession(id) {
  state.sessions = state.sessions.filter((s) => s.id !== id);
  save();
}
export function manualSession({ title, category, area, date, minutes }) {
  return normalizeSession({
    id: uuid(), taskTitle: title, category, area, phase: 'focus',
    startedAt: toISO(date), endedAt: toISO(new Date(date.getTime() + minutes * 60000)), isManual: true,
  });
}

export function resetSessions() { state.sessions = []; saveNow(); notify(); }
export function resetTasks() { state.tasks = []; state.activeTaskId = null; saveNow(); notify(); }
