import {
  state, AREAS, focusSessionsIn, durationMinutes, startOfDay, endOfDay, addDays, sameDay, weekInfo,
  walmartFiscal, quarterBounds, fiscalLabel, fiscalYearRange,
} from '../core.js';
import { esc, register, ICONS, fmtMinutes, fmtDay, fmtShort, catColor, app } from './common.js';
import { openGroupSheet, openSessionSheet } from './sheets.js';

const PERIODS = [['day', 'Day'], ['week', 'Week'], ['month', 'Month'], ['quarter', 'Quarter'], ['year', 'Year']];
const view = { period: 'week', offset: 0 };

// ───────────── ranges ─────────────

function rangeFor(period, offset) {
  const now = new Date();
  switch (period) {
    case 'day': {
      const d = addDays(startOfDay(now), offset);
      return { start: d, end: endOfDay(d), title: offset === 0 ? 'Today' : offset === -1 ? 'Yesterday' : fmtDay(d), sub: d.toLocaleDateString(undefined, { dateStyle: 'long' }) };
    }
    case 'week': {
      const s = addDays(weekInfo(now, state.prefs.weekStart || 0).start, offset * 7);
      const info = weekInfo(s, state.prefs.weekStart || 0);
      return { start: s, end: endOfDay(addDays(s, 6)), title: `Week ${info.week}`, sub: `${fmtShort(s)} – ${fmtShort(addDays(s, 6))}, ${info.year}` };
    }
    case 'month': {
      const s = new Date(now.getFullYear(), now.getMonth() + offset, 1);
      const e = endOfDay(new Date(s.getFullYear(), s.getMonth() + 1, 0));
      return { start: s, end: e, title: s.toLocaleDateString(undefined, { month: 'long', year: 'numeric' }), sub: '' };
    }
    case 'quarter': {
      const f = walmartFiscal(now);
      const idx = f.fiscalYear * 4 + (f.quarter - 1) + offset;
      const fy = Math.floor(idx / 4), q = (idx % 4 + 4) % 4 + 1;
      const b = quarterBounds(q, fy);
      return { ...b, title: fiscalLabel(q, fy), sub: `${fmtShort(b.start)} – ${fmtShort(b.end)}, Walmart fiscal` };
    }
    default: {
      const fy = walmartFiscal(now).fiscalYear + offset;
      const b = fiscalYearRange(fy);
      return { ...b, title: `FY${fy}`, sub: `${fmtShort(b.start)} ${b.start.getFullYear()} – ${fmtShort(b.end)} ${b.end.getFullYear()}` };
    }
  }
}

// ───────────── data ─────────────

function bucketsFor(period, range) {
  const out = [];
  if (period === 'day') {
    for (let h = 0; h < 24; h++) out.push({ label: h % 6 === 0 ? String(h) : '', test: (d) => d.getHours() === h });
  } else if (period === 'week' || period === 'month') {
    const days = Math.round((startOfDay(range.end) - range.start) / 864e5) + 1;
    for (let i = 0; i < days; i++) {
      const d = addDays(range.start, i);
      const label = period === 'week' ? d.toLocaleDateString(undefined, { weekday: 'short' }) : (d.getDate() % 5 === 1 ? String(d.getDate()) : '');
      out.push({ label, test: (x) => sameDay(x, d) });
    }
  } else if (period === 'quarter') {
    let i = 0;
    for (let s = range.start; s <= range.end; s = addDays(s, 7), i++) {
      const a = s, b = endOfDay(addDays(s, 6));
      out.push({ label: `W${i + 1}`, test: (x) => x >= a && x <= b });
    }
  } else {
    for (let i = 0; i < 12; i++) {
      const a = new Date(range.start.getFullYear(), range.start.getMonth() + i, 1);
      const b = endOfDay(new Date(a.getFullYear(), a.getMonth() + 1, 0));
      out.push({ label: a.toLocaleDateString(undefined, { month: 'narrow' }), test: (x) => x >= a && x <= b });
    }
  }
  return out;
}

function chartHtml(period, range, sessions) {
  const buckets = bucketsFor(period, range).map((b) => ({ ...b, byCat: new Map(), total: 0 }));
  for (const s of sessions) {
    const b = buckets.find((x) => x.test(s.startedAt));
    if (!b) continue;
    const m = durationMinutes(s);
    b.total += m;
    b.byCat.set(s.category, (b.byCat.get(s.category) || 0) + m);
  }
  const max = Math.max(1, ...buckets.map((b) => b.total));
  const dense = buckets.length > 14;
  return `<div class="chart ${dense ? 'dense' : ''}">${buckets.map((b) => `
    <div class="col" title="${fmtMinutes(b.total)}">
      <div class="stack-bar" style="height:${(b.total / max) * 100}%">
        ${[...b.byCat].map(([c, m]) => `<i style="flex:${m};background:${catColor(c)}"></i>`).join('')}
      </div>
      <span>${esc(b.label)}</span>
    </div>`).join('')}</div>`;
}

function donutHtml(sessions) {
  const byCat = new Map();
  let total = 0;
  for (const s of sessions) {
    const m = durationMinutes(s);
    total += m;
    byCat.set(s.category, (byCat.get(s.category) || 0) + m);
  }
  if (!total) return '<p class="empty">No focus time in this period.</p>';
  const entries = [...byCat].sort((a, b) => b[1] - a[1]);
  let acc = 0;
  const stops = entries.map(([c, m]) => {
    const a = (acc / total) * 100; acc += m;
    return `${catColor(c)} ${a}% ${(acc / total) * 100}%`;
  }).join(',');
  return `
  <div class="donut-wrap">
    <div class="donut" style="background:conic-gradient(${stops})"><span>${fmtMinutes(total)}</span></div>
    <ul class="legend">${entries.map(([c, m]) =>
    `<li><i style="background:${catColor(c)}"></i><span>${esc(c)}</span><b>${fmtMinutes(m)}</b><em>${Math.round((m / total) * 100)}%</em></li>`).join('')}</ul>
  </div>`;
}

function topTasks(sessions) {
  const m = new Map();
  for (const s of sessions) {
    const k = `${s.taskTitle}\u0000${s.category}`;
    const g = m.get(k) || { title: s.taskTitle, cat: s.category, n: 0, min: 0 };
    g.n += 1; g.min += durationMinutes(s);
    m.set(k, g);
  }
  return [...m.values()].sort((a, b) => b.min - a.min).slice(0, 6);
}

function accomplishments(period, sessions) {
  const byMonth = period === 'quarter' || period === 'year';
  const groups = new Map();
  for (const s of sessions) {
    const d = byMonth ? new Date(s.startedAt.getFullYear(), s.startedAt.getMonth(), 1) : startOfDay(s.startedAt);
    const gk = d.getTime();
    const g = groups.get(gk) || { date: d, items: new Map() };
    const ik = `${s.taskTitle}\u0000${s.category}`;
    const it = g.items.get(ik) || { title: s.taskTitle, cat: s.category, n: 0, min: 0, date: startOfDay(s.startedAt) };
    it.n += 1; it.min += durationMinutes(s);
    if (!byMonth) it.date = d;
    g.items.set(ik, it);
    groups.set(gk, g);
  }
  return [...groups.values()].sort((a, b) => b.date - a.date).map((g) => ({
    label: byMonth ? g.date.toLocaleDateString(undefined, { month: 'long', year: 'numeric' }) : fmtDay(g.date),
    items: [...g.items.values()].sort((a, b) => b.min - a.min),
    total: [...g.items.values()].reduce((n, i) => n + i.min, 0),
    byMonth,
  }));
}

// ───────────── view ─────────────

export function render() {
  const area = state.settings.activeArea;
  const range = rangeFor(view.period, view.offset);
  const sessions = focusSessionsIn(range, area);
  const minutes = sessions.reduce((n, s) => n + durationMinutes(s), 0);
  const days = new Set(sessions.map((s) => startOfDay(s.startedAt).getTime())).size;
  const span = Math.max(1, Math.round((startOfDay(range.end) - range.start) / 864e5) + 1);
  const top = topTasks(sessions);
  const acc = accomplishments(view.period, sessions);

  return `
  <div class="page reports">
    <div class="page-head">
      <div><h1>Reports</h1><p class="muted small">${AREAS[area].label} only</p></div>
      <div class="head-btns no-print">
        <button class="btn sm" data-act="rep-log">${ICONS.plus}<span>Log work</span></button>
        <button class="btn sm" data-act="rep-print">Print / PDF</button>
      </div>
    </div>

    <div class="seg no-print">${PERIODS.map(([k, l]) =>
    `<button class="${view.period === k ? 'on' : ''}" data-act="rep-period" data-p="${k}">${l}</button>`).join('')}</div>

    <div class="week-nav card slim no-print">
      <button class="icon-btn" data-act="rep-prev" aria-label="Previous">${ICONS.chevL}</button>
      <div class="wk-mid"><strong>${esc(range.title)}</strong>${range.sub ? `<span>${esc(range.sub)}</span>` : ''}</div>
      <button class="icon-btn" data-act="rep-next" aria-label="Next">${ICONS.chevR}</button>
      ${view.offset !== 0 ? '<button class="link today-btn" data-act="rep-now">Now</button>' : ''}
    </div>
    <div class="print-only"><h2>${esc(AREAS[area].label)} report — ${esc(range.title)}</h2><p>${esc(range.sub)}</p></div>

    <div class="stat-grid">
      <div class="stat"><b>${sessions.length}</b><span>Pomodoros</span></div>
      <div class="stat"><b>${fmtMinutes(minutes)}</b><span>Focus time</span></div>
      <div class="stat"><b>${days}</b><span>Active days</span></div>
      <div class="stat"><b>${fmtMinutes(minutes / span)}</b><span>Avg / day</span></div>
    </div>

    <div class="card"><div class="sec-head"><h2>Focus time</h2></div>${chartHtml(view.period, range, sessions)}</div>
    <div class="card"><div class="sec-head"><h2>By category</h2></div>${donutHtml(sessions)}</div>

    ${top.length ? `<div class="card"><div class="sec-head"><h2>Top tasks</h2></div><div class="list">${top.map((t) => `
      <div class="row"><div class="grow"><div class="t-title">${esc(t.title)}</div>
        <div class="t-meta"><span class="badge" style="--c:${catColor(t.cat)}">${esc(t.cat)}</span></div></div>
        <div class="num"><b>${fmtMinutes(t.min)}</b><small>${t.n} 🍅</small></div></div>`).join('')}</div></div>` : ''}

    <div class="card">
      <div class="sec-head"><h2>Accomplishments</h2><span class="muted">${fmtMinutes(minutes)}</span></div>
      ${acc.length ? acc.map((g) => `
        <div class="acc-group"><div class="acc-head"><strong>${esc(g.label)}</strong><span>${fmtMinutes(g.total)}</span></div>
        ${g.items.map((i) => `
          <button class="row acc ${g.byMonth ? 'static' : ''}" ${g.byMonth ? '' : `data-act="rep-group" data-t="${i.date.getTime()}" data-title="${esc(i.title)}" data-cat="${esc(i.cat)}"`}>
            <i class="dot" style="background:${catColor(i.cat)}"></i>
            <div class="grow"><div class="t-title">${esc(i.title)}</div><div class="t-meta"><span>${esc(i.cat)}</span></div></div>
            <div class="num"><b>${fmtMinutes(i.min)}</b><small>${i.n} 🍅</small></div>
          </button>`).join('')}</div>`).join('')
    : '<p class="empty">No accomplishments in this period. Use “Log work” to add past sessions.</p>'}
    </div>
  </div>`;
}

export function init() {
  register('click', {
    'rep-period': ({ p }) => { view.period = p; view.offset = 0; app.render(); },
    'rep-prev': () => { view.offset -= 1; app.render(); },
    'rep-next': () => { view.offset += 1; app.render(); },
    'rep-now': () => { view.offset = 0; app.render(); },
    'rep-print': () => window.print(),
    'rep-log': () => openSessionSheet({ defaults: { area: state.settings.activeArea } }),
    'rep-group': ({ t, title, cat }) => openGroupSheet({
      date: new Date(Number(t)), title, category: cat, area: state.settings.activeArea,
    }),
  });
}
