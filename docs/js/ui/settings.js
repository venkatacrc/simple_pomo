import {
  state, AREAS, SOUNDS, updateSettings, updatePrefs, addCategory, removeCategory, exportData, importData,
  resetSessions, resetTasks, saveNow,
} from '../core.js';
import { refreshForSettings, playSound, unlockAudio } from '../timer.js';
import { esc, register, openSheet, toast, $ } from './common.js';

let sheet = null;
let importMode = 'merge';

const numRow = (label, key, min, max) => `
  <label class="field-row"><span>${label}</span>
    <input type="number" inputmode="numeric" min="${min}" max="${max}" value="${state.settings[key]}" data-change="set-num" data-k="${key}"></label>`;
const switchRow = (label, kind, key, on, hint = '') => `
  <label class="switch-row"><span>${label}${hint ? `<small>${hint}</small>` : ''}</span>
    <input type="checkbox" data-change="set-bool" data-kind="${kind}" data-k="${key}" ${on ? 'checked' : ''}></label>`;

function catSection(area) {
  const list = area === 'work' ? state.settings.workCategories : state.settings.personalCategories;
  return `
  <div class="cat-block">
    <h4>${AREAS[area].label} categories</h4>
    <div class="chips-wrap">${list.map((c) =>
    `<span class="chip rm">${esc(c)}<button data-act="set-cat-rm" data-area="${area}" data-c="${esc(c)}" aria-label="Remove ${esc(c)}">✕</button></span>`).join('')}</div>
    <div class="quick-add">
      <input type="text" id="newCat-${area}" placeholder="New ${AREAS[area].label.toLowerCase()} category" data-enter="set-cat-add" data-area="${area}" autocomplete="off">
      <button class="btn sm" data-act="set-cat-add" data-area="${area}">Add</button>
    </div>
  </div>`;
}

function body() {
  const s = state.settings, p = state.prefs;
  const standalone = window.matchMedia?.('(display-mode: standalone)').matches || navigator.standalone;
  return `
  <section><h4>Timer (minutes)</h4>
    ${numRow('Focus', 'focusMinutes', 1, 180)}
    ${numRow('Short break', 'shortBreakMinutes', 1, 60)}
    ${numRow('Long break', 'longBreakMinutes', 1, 90)}
    ${numRow('Long break every N focus', 'longBreakEvery', 2, 12)}
    ${switchRow('Auto-start breaks', 'settings', 'autoStartBreaks', s.autoStartBreaks)}
    ${switchRow('Auto-start focus', 'settings', 'autoStartPomodoros', s.autoStartPomodoros)}
  </section>

  <section><h4>Alerts</h4>
    ${switchRow('Play sound', 'settings', 'playSound', s.playSound)}
    <label class="field-row"><span>Sound</span>
      <select data-change="set-sound">${SOUNDS.map((n) => `<option ${n === s.soundName ? 'selected' : ''}>${n}</option>`).join('')}</select></label>
    ${switchRow('Vibrate', 'prefs', 'vibrate', p.vibrate, 'Android only; iOS ignores it')}
    ${switchRow('Keep screen awake while running', 'prefs', 'keepAwake', p.keepAwake, 'Phones pause timers in the background')}
  </section>

  <section><h4>Calendar</h4>
    <label class="field-row"><span>Week starts on</span>
      <select data-change="set-weekstart"><option value="0" ${p.weekStart === 0 ? 'selected' : ''}>Sunday</option><option value="1" ${p.weekStart === 1 ? 'selected' : ''}>Monday</option></select></label>
  </section>

  <section>${catSection('work')}${catSection('personal')}</section>

  <section><h4>Data</h4>
    <p class="muted small">Everything is stored on this device only. Use a file to move data between your Mac and phone (same format as the Mac app’s <code>store.json</code>).</p>
    <div class="btn-row">
      <button class="btn" data-act="set-export">Export JSON</button>
      <button class="btn" data-act="set-share">Share…</button>
    </div>
    <label class="field-row"><span>Import mode</span>
      <select data-change="set-import-mode">
        <option value="merge" ${importMode === 'merge' ? 'selected' : ''}>Merge into current</option>
        <option value="replace" ${importMode === 'replace' ? 'selected' : ''}>Replace everything</option></select></label>
    <label class="btn file-btn">Import JSON file<input type="file" accept="application/json,.json" data-change="set-import" hidden></label>
  </section>

  <section><h4>Install on your phone</h4>
    ${standalone ? '<p class="muted small">✅ Running as an installed app.</p>' : `
    <p class="muted small"><b>iPhone (Safari):</b> Share ▸ Add to Home Screen.<br><b>Android (Chrome):</b> ⋮ ▸ Install app / Add to Home screen.</p>`}
  </section>

  <section class="danger"><h4>Danger zone</h4>
    <div class="btn-row">
      <button class="btn bad" data-act="set-reset-sessions">Clear sessions</button>
      <button class="btn bad" data-act="set-reset-tasks">Clear tasks</button>
    </div>
  </section>`;
}

function redraw() { if (sheet) { const y = sheet.body.scrollTop; sheet.body.innerHTML = body(); sheet.body.scrollTop = y; } }

export function openSettings() {
  sheet = openSheet({ title: 'Settings', body: body() });
  const orig = sheet.close;
  sheet.close = () => { sheet = null; orig(); };
  sheet.el.addEventListener('click', (e) => { if (e.target.closest('[data-close]')) sheet = null; });
}

function download(name, text, type = 'application/json') {
  const url = URL.createObjectURL(new Blob([text], { type }));
  const a = Object.assign(document.createElement('a'), { href: url, download: name });
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 2000);
}
const fileName = () => `simple-pomo-${new Date().toISOString().slice(0, 10)}.json`;
const json = () => JSON.stringify(exportData(), null, 2);

function addCat(area) {
  const el = $(`#newCat-${area}`);
  if (!el || !el.value.trim()) return;
  addCategory(el.value, area);
  redraw();
}

export function init() {
  register('click', {
    'open-settings': openSettings,
    'set-cat-add': ({ area }) => addCat(area),
    'set-cat-rm': ({ area, c }) => { removeCategory(c, area); redraw(); },
    'set-export': () => { saveNow(); download(fileName(), json()); toast('Exported'); },
    'set-share': async () => {
      const file = new File([json()], fileName(), { type: 'application/json' });
      try {
        if (navigator.canShare?.({ files: [file] })) await navigator.share({ files: [file], title: 'Simple Pomo data' });
        else if (navigator.share) await navigator.share({ title: 'Simple Pomo data', text: json() });
        else { download(fileName(), json()); toast('Sharing not supported — downloaded instead'); }
      } catch (e) { if (e?.name !== 'AbortError') toast('Share failed'); }
    },
    'set-reset-sessions': () => { if (confirm('Delete ALL recorded sessions? This cannot be undone.')) { resetSessions(); toast('Sessions cleared'); } },
    'set-reset-tasks': () => { if (confirm('Delete ALL tasks? This cannot be undone.')) { resetTasks(); toast('Tasks cleared'); } },
  });
  register('enter', { 'set-cat-add': ({ area }) => addCat(area) });
  register('change', {
    'set-num': ({ k }, el) => {
      const v = Math.max(Number(el.min), Math.min(Number(el.max), Math.round(Number(el.value)) || Number(state.settings[k])));
      el.value = v;
      updateSettings({ [k]: v });
      refreshForSettings();
    },
    'set-bool': ({ kind, k }, el) => {
      if (kind === 'prefs') updatePrefs({ [k]: el.checked }); else updateSettings({ [k]: el.checked });
    },
    'set-sound': (_, el) => { updateSettings({ soundName: el.value }); unlockAudio(); playSound(el.value); },
    'set-weekstart': (_, el) => updatePrefs({ weekStart: Number(el.value) }),
    'set-import-mode': (_, el) => { importMode = el.value; },
    'set-import': async (_, el) => {
      const f = el.files?.[0];
      if (!f) return;
      try {
        const obj = JSON.parse(await f.text());
        if (importMode === 'replace' && !confirm('Replace all data on this device with the file?')) return;
        importData(obj, importMode);
        saveNow();
        toast(`Imported (${importMode})`);
        redraw();
      } catch (e) {
        toast(`Import failed: ${e.message || 'invalid file'}`, 3500);
      } finally { el.value = ''; }
    },
  });
}
