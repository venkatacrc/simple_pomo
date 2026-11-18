// Pomodoro engine. Works off an absolute end timestamp (not tick counting) so
// it stays accurate when the phone throttles or suspends the page.

import {
  state, PHASES, uuid, getTask, activeTask, incrementCompleted, recordSession,
  categoriesFor, AREAS, SOUNDS,
} from './core.js';

const LS = 'simplepomo.timer.v1';
const listeners = new Set();
export const onTimer = (fn) => { listeners.add(fn); return () => listeners.delete(fn); };
const emit = (type, detail) => listeners.forEach((f) => f(type, detail));

const T = {
  phase: 'focus', totalMs: 25 * 60000, remainingMs: 25 * 60000,
  running: false, endAt: 0, phaseStartedAt: 0, cycle: 0,
};
let ticker = null;
let lastShown = -1;
let wakeLock = null;
let audioCtx = null;

const phaseMs = (p) => ({
  focus: state.settings.focusMinutes,
  shortBreak: state.settings.shortBreakMinutes,
  longBreak: state.settings.longBreakMinutes,
}[p]) * 60000;

function persist() {
  try { localStorage.setItem(LS, JSON.stringify(T)); } catch { /* ignore */ }
}

export function remainingMs() { return T.running ? Math.max(0, T.endAt - Date.now()) : T.remainingMs; }

export function snapshot() {
  const rem = remainingMs();
  return {
    phase: T.phase, running: T.running, totalMs: T.totalMs, remainingMs: rem,
    progress: T.totalMs ? Math.min(1, Math.max(0, 1 - rem / T.totalMs)) : 0,
    cycle: T.cycle, started: !!T.phaseStartedAt,
  };
}

export function displayTime(ms) {
  const s = Math.ceil(ms / 1000);
  return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
}

function configure(phase, reset = true) {
  T.phase = phase;
  T.totalMs = phaseMs(phase);
  if (reset) T.remainingMs = T.totalMs;
  T.phaseStartedAt = 0;
}

// ───────────── controls ─────────────

export function start() {
  if (T.running) return;
  unlockAudio();
  askNotificationPermission();
  const now = Date.now();
  if (!T.phaseStartedAt) T.phaseStartedAt = now;
  T.endAt = now + T.remainingMs;
  T.running = true;
  startTicker();
  requestWake();
  persist();
  emit('state');
}

export function pause() {
  if (!T.running) return;
  T.remainingMs = Math.max(0, T.endAt - Date.now());
  T.running = false;
  stopTicker();
  releaseWake();
  persist();
  emit('state');
}

export const toggle = () => (T.running ? pause() : start());

export function reset() {
  freeze();
  configure(T.phase, true);
  persist();
  emit('state');
}

export function switchPhase(p) {
  freeze();
  configure(p, true);
  persist();
  emit('state');
}

export function skip() {
  const elapsed = T.totalMs - remainingMs();
  const started = T.phaseStartedAt;
  freeze();
  if (T.phase === 'focus' && started && elapsed >= 60000) logSession(started, elapsed);
  advance(false);
}

/** Re-read durations after the user changes them (only if this phase hasn't started). */
export function refreshForSettings() {
  if (!T.running && !T.phaseStartedAt) {
    configure(T.phase, true);
    persist();
    emit('state');
  }
}

function freeze() {
  if (T.running) T.remainingMs = Math.max(0, T.endAt - Date.now());
  T.running = false;
  stopTicker();
  releaseWake();
}

// ───────────── completion ─────────────

function logSession(startMs, durMs) {
  const task = activeTask();
  const area = task ? task.area : state.settings.activeArea;
  const category = task ? task.category : (categoriesFor(area)[0] || AREAS[area].label);
  recordSession({
    id: uuid(),
    taskId: task ? task.id : null,
    taskTitle: task ? task.title : 'Focus',
    category, area, phase: 'focus',
    startedAt: new Date(startMs),
    endedAt: new Date(startMs + durMs),
    isManual: false,
  });
}

function complete() {
  const wasFocus = T.phase === 'focus';
  const endAt = T.endAt || Date.now();
  const started = T.phaseStartedAt || endAt - T.totalMs;
  T.remainingMs = 0;
  T.running = false;
  stopTicker();
  releaseWake();
  if (wasFocus) {
    logSession(started, T.totalMs);
    T.cycle += 1;
    if (state.activeTaskId && getTask(state.activeTaskId)) incrementCompleted(state.activeTaskId);
  }
  alertUser(wasFocus);
  emit('complete', { wasFocus });
  advance(true);
}

function advance(natural) {
  const every = state.settings.longBreakEvery;
  const from = T.phase;
  const next = from === 'focus'
    ? (T.cycle > 0 && T.cycle % every === 0 ? 'longBreak' : 'shortBreak')
    : 'focus';
  configure(next, true);
  persist();
  emit('phase', { from, to: next });
  emit('state');
  if (natural) {
    const auto = next === 'focus' ? state.settings.autoStartPomodoros : state.settings.autoStartBreaks;
    if (auto) start();
  }
}

// ───────────── ticking ─────────────

function tick() {
  if (!T.running) return;
  const rem = T.endAt - Date.now();
  if (rem <= 0) { complete(); return; }
  const sec = Math.ceil(rem / 1000);
  if (sec !== lastShown) { lastShown = sec; emit('tick'); }
}
function startTicker() { stopTicker(); lastShown = -1; ticker = setInterval(tick, 250); }
function stopTicker() { if (ticker) clearInterval(ticker); ticker = null; }

document.addEventListener('visibilitychange', () => {
  if (document.hidden) return;
  tick();
  if (T.running) requestWake();
  emit('tick');
});
addEventListener('pageshow', () => { tick(); emit('tick'); });

// ───────────── alerts (sound / vibration / notification) ─────────────

const SOUND_DEFS = {
  Glass:     { f: [1318, 1760], type: 'sine',     d: 0.45 },
  Ping:      { f: [1568],       type: 'sine',     d: 0.5 },
  Tink:      { f: [2093, 2093], type: 'triangle', d: 0.18 },
  Pop:       { f: [440, 660],   type: 'sine',     d: 0.14 },
  Hero:      { f: [523, 659, 784], type: 'triangle', d: 0.28 },
  Funk:      { f: [196, 262, 196], type: 'square', d: 0.16 },
  Submarine: { f: [330, 247],   type: 'sine',     d: 0.55 },
};

export function unlockAudio() {
  try {
    if (!audioCtx) {
      const AC = globalThis.AudioContext || globalThis.webkitAudioContext;
      if (AC) audioCtx = new AC();
    }
    if (audioCtx && audioCtx.state === 'suspended') audioCtx.resume();
  } catch { /* ignore */ }
}

export function playSound(name = state.settings.soundName) {
  unlockAudio();
  if (!audioCtx) return;
  const def = SOUND_DEFS[name] || SOUND_DEFS.Glass;
  let t = audioCtx.currentTime + 0.02;
  def.f.forEach((freq) => {
    const osc = audioCtx.createOscillator();
    const gain = audioCtx.createGain();
    osc.type = def.type;
    osc.frequency.value = freq;
    gain.gain.setValueAtTime(0.0001, t);
    gain.gain.exponentialRampToValueAtTime(0.35, t + 0.02);
    gain.gain.exponentialRampToValueAtTime(0.0001, t + def.d);
    osc.connect(gain).connect(audioCtx.destination);
    osc.start(t);
    osc.stop(t + def.d + 0.02);
    t += def.d * 0.85;
  });
}
export { SOUNDS };

function askNotificationPermission() {
  try {
    if ('Notification' in globalThis && Notification.permission === 'default') Notification.requestPermission();
  } catch { /* ignore */ }
}

async function alertUser(wasFocus) {
  if (state.settings.playSound) playSound();
  if (state.prefs.vibrate && navigator.vibrate) navigator.vibrate([200, 100, 200]);
  const title = wasFocus ? 'Pomodoro complete' : 'Break over';
  const body = wasFocus ? 'Nice work — time for a break.' : 'Ready for the next focus session?';
  try {
    if (document.hidden && 'Notification' in globalThis && Notification.permission === 'granted') {
      const reg = await navigator.serviceWorker?.ready;
      const opts = { body, icon: 'icons/icon-192.png', tag: 'simplepomo-phase' };
      if (reg) reg.showNotification(title, opts); else new Notification(title, opts);
    }
  } catch { /* ignore */ }
}

// ───────────── keep screen awake while running ─────────────

async function requestWake() {
  if (!state.prefs.keepAwake) return;
  try {
    if ('wakeLock' in navigator && !wakeLock) {
      wakeLock = await navigator.wakeLock.request('screen');
      wakeLock.addEventListener('release', () => { wakeLock = null; });
    }
  } catch { /* not allowed / unsupported */ }
}
function releaseWake() {
  try { wakeLock && wakeLock.release(); } catch { /* ignore */ }
  wakeLock = null;
}

// ───────────── init ─────────────

export function initTimer() {
  let saved = null;
  try { saved = JSON.parse(localStorage.getItem(LS) || 'null'); } catch { /* ignore */ }
  if (!saved || !PHASES[saved.phase]) {
    configure('focus', true);
    return;
  }
  Object.assign(T, {
    phase: saved.phase,
    totalMs: saved.totalMs || phaseMs(saved.phase),
    remainingMs: saved.remainingMs ?? phaseMs(saved.phase),
    running: false,
    endAt: saved.endAt || 0,
    phaseStartedAt: saved.phaseStartedAt || 0,
    cycle: saved.cycle || 0,
  });
  if (saved.running) {
    if (saved.endAt > Date.now()) {
      T.running = true;
      T.endAt = saved.endAt;
      startTicker();
      requestWake();
    } else {
      // The phase finished while the app was closed — count it with its real end time.
      T.endAt = saved.endAt;
      T.running = true;
      setTimeout(complete, 0);
    }
  }
}
