// Comfort gate for dashboard/index.html in a stub Dashboard host (fixture data, no network).
//
// Run: NODE_PATH=<dir with playwright axe-core d3> node dashboard_comfort.cjs <fragment.html> <prefix>
// Writes <prefix>-<theme>-<size>.{html,png} under $DASH_OUT (default: $TMPDIR, else os.tmpdir()) and prints
// JSON. Exit 1 when a check fails, naming it on stderr. Checks, on phone and desktop, light and dark, with
// reduced motion:
//   axe          serious or critical axe issue
//   smallText    text under 14 px
//   targets      touch target under 44 px
//   overflow     the document, .tc-wrap, a panel or a plot scrolls sideways (scrollWidth > clientWidth), or any
//                element ends past the viewport. The element check sees through `overflow-x: clip`.
//   splitWords   a word breaks across two lines in a table cell although it fits on a line by itself
//   runsCap      the runs table shows more than 5 rows before "Show N more"
//   tableRoles   a table, row, header or cell lacks its ARIA role (phone CSS drops native table semantics)
//   charts       a chart has no svg role=img, no aria-label, no visible latest value, or no tooltip on focus/tap
//   resize       after the window narrows, a chart svg is scaled below 97% (14 px text would shrink)
//   badDay       a calendar day that does not exist (2026-02-30) is drawn as a point
//   noData       a dataset that dash.data() returns as undefined must not stop the other panels from drawing
//   pageErrors   an uncaught page error
// The fixture holds a word wider than a phone cell (a long verdict and a long project name), so a rule that
// breaks words anywhere has something to break.
// DASH_PLANT=overflow|breakall adds one known violation, to prove the gate fails on it (tests/tooling-checkup-dashboard.bats).
// d3 and axe-core hide files behind an exports map, so their files are looked up on NODE_PATH.
const { chromium } = require('playwright');
const fs = require('fs'), os = require('os'), path = require('path');
const findFile = rel => { const p = require.resolve.paths(rel).map(d => path.join(d, rel)).find(f => fs.existsSync(f)); if (!p) throw new Error('not found on NODE_PATH: ' + rel); return p; };
const axeSrc = fs.readFileSync(findFile('axe-core/axe.min.js'), 'utf8');
const d3src = fs.readFileSync(findFile('d3/dist/d3.min.js'), 'utf8');
const frag = fs.readFileSync(process.argv[2], 'utf8');
const prefix = process.argv[3];
const OUT = process.env.DASH_OUT || process.env.TMPDIR || os.tmpdir();
const PLANT = process.env.DASH_PLANT || '';
const DROP = process.env.DASH_DROP || '';
const day = i => new Date(Date.UTC(2026, 9, 1 + i)).toISOString().slice(0, 10);
const LONG_WORD = 'agentbrew-doctor-gate-timing-regression-investigation-2026';
const runs = Array.from({ length: 20 }, (_, i) => ({
  time: new Date(Date.UTC(2026, 9, 1 + i, 9)).toISOString(),
  status: ['healthy', 'gaps', 'broken'][i % 3],
  machine_overload_rows_24h: (i * 7) % 11,
  agent_tool_hours_7d: 10 + i,
  verdict: i === 3 ? 'See ' + LONG_WORD + ' for the full trace' : 'Synthetic verdict text for row ' + i + ' with a long sentence that wraps on phones',
}));
const data = {
  latest: { status: 'ok', data: [{ ...runs[19], status: 'gaps', machine_peak_load1_24h: 6.4, claude_echo_p95_ms: 220 }] },
  runs: { status: 'ok', data: runs },
  gate: { status: 'ok', data: Array.from({ length: 14 }, (_, i) => ({ day: day(i), median_total_s: 60 + i * 3 })) },
  // One impossible day (Feb 30) must be dropped, not rolled over to Mar 2.
  doctor: { status: 'ok', data: [...Array.from({ length: 14 }, (_, i) => ({ day: day(i), fail: i % 4 })), { day: '2026-02-30', fail: 9 }] },
  // UTC keys cover either clock change; only their displayed labels use local time.
  load: { status: 'ok', data: Array.from({ length: 168 }, (_, i) => ({ hour: new Date(Date.UTC(2026, process.env.DASH_DST === 'spring' ? 2 : 9, process.env.DASH_DST === 'spring' ? 5 : 29, i)).toISOString(), samples: 12, peak_load1: Math.round((2 + 3 * Math.abs(Math.sin(i / 9)) + (i % 24 > 9 && i % 24 < 18 ? 2 : 0)) * 10) / 10 })) },
  agent_time: { status: 'ok', data: ['agentbrew', 'dotfiles', 'minsky', 'tooling-checkup-dashboard-fixture-repo-name'].flatMap(p => Array.from({ length: 14 }, (_, i) => ({ day: day(i), project: p, tool_hours: 0.5 + i / 10, calls: 100 + i, failed_calls: i % 3 }))) },
};
if (DROP) delete data[DROP];
const themes = {
  light: '--color-fg:#1f1e1d;--color-fg-muted:#5c5a55;--color-panel:#ffffff;--color-border-line:#d9d6cf;--color-ok:#1a7f37;--color-warn:#8a5a00;--color-bad:#b3261e;--bg:#faf9f5;',
  dark: '--color-fg:#ece9e2;--color-fg-muted:#aaa69d;--color-panel:#262624;--color-border-line:#44423e;--color-ok:#5ac27a;--color-warn:#e0b04a;--color-bad:#ff8a80;--bg:#1a1a18;',
};
const planted = PLANT === 'overflow' ? '<div style="width:2000px;height:10px"></div>' : PLANT === 'breakall' ? '<style>.tc-table td{word-break:break-all}</style>' : PLANT === 'chartcontrast' ? '<style>.tc-chart path[stroke-width="2"]{stroke:var(--tc-panel)}</style>' : '';
const page = t => `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Tooling health</title><style>:root{${themes[t]}--font-anthropic-sans:system-ui,sans-serif;--font-anthropic-serif:Georgia,serif}body{margin:0;padding:16px;background:var(--bg);font-family:system-ui}</style></head><body><script>${d3src}</script><script>window.dash={colors:['#c96442','#3b6ea5','#6a8f3a','#8a5aa8','#b08a1e'],_cb:[],onData(f){this._cb.push(f)},data(n){return ${JSON.stringify(data)}[n]}};</script><main>${frag}${planted}</main><script>dash._cb.forEach(function(f){f()})</script></body></html>`;

function measure() {
  const small = new Set();
  document.querySelectorAll('main *').forEach(el => {
    const own = [...el.childNodes].some(n => n.nodeType === 3 && n.textContent.trim());
    if (own && parseFloat(getComputedStyle(el).fontSize) < 14) small.add(el.tagName.toLowerCase() + '.' + (el.className.baseVal ?? el.className));
  });
  const targets = [...document.querySelectorAll('a,button,input,select,textarea,[role=button]')].filter(e => { const r = e.getBoundingClientRect(); return r.width < 44 || r.height < 44; }).length;
  const overflow = [];
  const sw = (el, name) => { if (el.scrollWidth > el.clientWidth + 1) overflow.push(name + ' scrollWidth ' + el.scrollWidth + ' > clientWidth ' + el.clientWidth); };
  sw(document.documentElement, 'document');
  document.querySelectorAll('.tc-wrap, .tc-wrap > section, .tc-plot').forEach(el => sw(el, '#' + (el.id || el.className)));
  document.querySelectorAll('main *').forEach(el => {
    if (!el.getClientRects().length) return;
    const r = el.getBoundingClientRect();
    if (r.right > innerWidth + 1) overflow.push(el.tagName.toLowerCase() + '.' + (el.className.baseVal ?? el.className) + ' ends at ' + Math.round(r.right) + ' of ' + innerWidth);
  });
  const splitWords = [];
  document.querySelectorAll('td,th').forEach(c => {
    if (!c.getClientRects().length) return;
    const cellW = c.clientWidth;
    const w = document.createTreeWalker(c, NodeFilter.SHOW_TEXT);
    for (let n; (n = w.nextNode());) {
      const re = /\S+/g; let m;
      while ((m = re.exec(n.textContent))) {
        const r = document.createRange(); r.setStart(n, m.index); r.setEnd(n, m.index + m[0].length);
        if (r.getClientRects().length < 2) continue;
        // A word wider than its whole cell cannot stay whole: only a word that would fit counts.
        const probe = document.createElement('span');
        probe.style.cssText = 'position:absolute;visibility:hidden;white-space:nowrap;font:' + getComputedStyle(c).font;
        probe.textContent = m[0]; document.body.appendChild(probe);
        const fits = probe.getBoundingClientRect().width <= cellW; probe.remove();
        if (fits) splitWords.push(m[0]);
      }
    }
  });
  const rows = [...document.querySelectorAll('#tc-runs tbody tr')];
  const charts = [];
  const chartContrast = [];
  const luminance = value => {
    const c = d3.color(value).rgb();
    const rgb = [c.r, c.g, c.b].map(v => { v /= 255; return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; });
    return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722;
  };
  document.querySelectorAll('.tc-chart').forEach(sec => {
    const svg = sec.querySelector('svg');
    if (!svg) { if (sec.querySelector('.tc-plot').textContent !== 'no data') charts.push(sec.id + ': no svg'); return; }
    if (svg.getAttribute('role') !== 'img') charts.push(sec.id + ': svg has no role=img');
    if (!/latest .*min .*max /.test(svg.getAttribute('aria-label') || '')) charts.push(sec.id + ': aria-label lacks latest, min, max');
    if (!sec.querySelector('.tc-now').textContent.trim()) charts.push(sec.id + ': no visible latest value');
    const panel = luminance(getComputedStyle(sec).getPropertyValue('--tc-panel').trim());
    svg.querySelectorAll('path[stroke-width="2"][fill="none"]').forEach(line => {
      const stroke = luminance(getComputedStyle(line).stroke);
      const ratio = (Math.max(stroke, panel) + 0.05) / (Math.min(stroke, panel) + 0.05);
      if (ratio < 3) chartContrast.push(sec.id + ': ' + ratio.toFixed(2) + ':1');
    });
  });
  const tableRoles = [];
  document.querySelectorAll('table').forEach(t => {
    const id = t.closest('section').id;
    if (t.getAttribute('role') !== 'table') tableRoles.push(id + ': table has no role=table');
    if (t.querySelectorAll('thead th:not([role=columnheader])').length) tableRoles.push(id + ': th without role=columnheader');
    if (t.querySelectorAll('tr:not([role=row])').length) tableRoles.push(id + ': tr without role=row');
    if (t.querySelectorAll('tbody td:not([role=cell])').length) tableRoles.push(id + ': td without role=cell');
  });
  const loadPoints = [...document.querySelectorAll('#tc-load svg circle[r="4"]')].map(circle => circle.__data__);
  return { tableRoles, splitWords, overflow, runsRows: rows.length, runsVisible: rows.filter(r => r.getClientRects().length).length, smallText: [...small], smallTargets: targets, charts, chartContrast, loadHours: new Set(loadPoints.map(point => +point.x)).size, shiftedHours: loadPoints.filter(point => +point.x !== Date.parse(point.r.hour)).length };
}

(async () => {
  const b = await chromium.launch();
  const out = {};
  const sizes = { phone: [375, 812], desktop: [1280, 800] };
  for (const t of ['light', 'dark']) for (const [sn, [w, h]] of Object.entries(sizes)) {
    const ctx = await b.newContext({ viewport: { width: w, height: h }, colorScheme: t, reducedMotion: 'reduce', hasTouch: sn === 'phone', timezoneId: 'America/Toronto' });
    const p = await ctx.newPage();
    const file = path.join(OUT, `${prefix}-${t}-${sn}.html`);
    fs.writeFileSync(file, page(t));
    const errs = []; p.on('pageerror', e => errs.push(String(e)));
    await p.goto('file://' + file); await p.waitForTimeout(500);
    await p.addScriptTag({ content: axeSrc });
    const axe = await p.evaluate(async () => { const r = await axe.run(document, { runOnly: ['wcag2a', 'wcag2aa', 'wcag22aa', 'best-practice'] }); return r.violations.filter(v => ['serious', 'critical'].includes(v.impact)).map(v => v.id + ':' + v.nodes.length); });
    const m = await p.evaluate(measure);
    // Tooltip on keyboard focus and on tap or click, not only on hover.
    const tipOf = id => p.evaluate(i => getComputedStyle(document.querySelector('#' + i + ' .tc-tip')).display, id);
    const interaction = [];
    if (!DROP) {
      await p.focus('#tc-gate svg');
      if (await tipOf('tc-gate') !== 'block') interaction.push('no tooltip on focus');
      const beforeArrow = await p.locator('#tc-gate .tc-tip').textContent();
      await p.keyboard.press('ArrowLeft');
      if (await p.locator('#tc-gate .tc-tip').textContent() === beforeArrow) interaction.push('ArrowLeft did not change tooltip');
      await p.evaluate(() => document.activeElement.blur());
      await p.focus('#tc-doctor svg');
      const latestDoctor = await p.locator('#tc-doctor .tc-tip').textContent();
      await p.evaluate(() => document.activeElement.blur());
      if (sn === 'phone') {
        await p.locator('#tc-doctor svg').scrollIntoViewIfNeeded();
        const rect = await p.locator('#tc-doctor svg').boundingBox();
        await p.touchscreen.tap(rect.x + 120, rect.y + 60);
      } else await p.click('#tc-doctor svg', { position: { x: 120, y: 60 } });
      if (await tipOf('tc-doctor') !== 'block') interaction.push('no tooltip on tap');
      else if (await p.locator('#tc-doctor .tc-tip').textContent() === latestDoctor) interaction.push('tap did not select an earlier point');
    }
    const badDay = await p.evaluate(() => document.querySelectorAll('#tc-doctor svg circle[r="4"]').length);
    if (!DROP && badDay !== 14) interaction.push('doctor chart drew ' + badDay + ' points, expected 14 (Feb 30 dropped)');
    let resize = [];
    if (!DROP && sn === 'desktop') {
      await p.setViewportSize({ width: 375, height: 812 });
      await p.waitForTimeout(600);
      resize = await p.evaluate(() => [...document.querySelectorAll('.tc-chart svg')].map(s => ({ id: s.closest('.tc-chart').id, scale: s.getBoundingClientRect().width / s.viewBox.baseVal.width })).filter(x => x.scale < 0.97 || x.scale > 1.03));
      await p.setViewportSize({ width: 1280, height: 800 });
      await p.waitForTimeout(600);
    }
    const more = await p.$('#tc-runs-more');
    if (more) {
      await more.focus(); await more.press('Enter');
      const ok = await p.evaluate(() => document.activeElement && document.activeElement.closest('#tc-runs tbody tr') === document.querySelectorAll('#tc-runs tbody tr')[5]);
      if (!ok) interaction.push('focus not moved to first new row');
      // Every run row is visible now: look for split words in all of them, not only the first 5.
      m.splitWords = (await p.evaluate(measure)).splitWords;
    }
    // A dataset that is missing must leave the other panels drawn.
    const noData = DROP ? await p.evaluate(d => ({ dropped: document.querySelector('[data-source="' + d + '"].tc-chart .tc-plot')?.textContent, others: document.querySelectorAll('.tc-chart svg').length }), DROP) : null;
    out[`${t}-${sn}`] = { axeSerious: axe, ...m, interaction, resize, noData, pageErrors: errs };
    await p.screenshot({ path: path.join(OUT, `${prefix}-${t}-${sn}.png`), fullPage: true });
    await ctx.close();
  }
  await b.close();
  console.log(JSON.stringify(out));
  const fails = [];
  for (const [k, r] of Object.entries(out)) {
    if (r.axeSerious.length) fails.push(k + ' axe ' + r.axeSerious);
    if (r.smallText.length) fails.push(k + ' smallText ' + r.smallText);
    if (r.smallTargets) fails.push(k + ' targets ' + r.smallTargets);
    if (r.overflow.length) fails.push(k + ' overflow ' + r.overflow.slice(0, 3));
    if (r.splitWords.length) fails.push(k + ' splitWords ' + r.splitWords.slice(0, 3));
    if (r.runsVisible > 5) fails.push(k + ' runsCap ' + r.runsVisible);
    if (r.tableRoles.length) fails.push(k + ' tableRoles ' + r.tableRoles.slice(0, 3));
    if (r.charts.length) fails.push(k + ' charts ' + r.charts.slice(0, 3));
    if (r.chartContrast.length) fails.push(k + ' chartContrast ' + r.chartContrast);
    if (!DROP && r.loadHours !== 168) fails.push(k + ' loadHours ' + r.loadHours + ' expected 168');
    if (!DROP && r.shiftedHours) fails.push(k + ' shiftedHours ' + r.shiftedHours);
    if (r.interaction.length) fails.push(k + ' interaction ' + r.interaction);
    if (r.resize.length) fails.push(k + ' resize ' + JSON.stringify(r.resize.slice(0, 2)));
    if (r.noData && (r.noData.dropped !== 'no data' || r.noData.others < 4)) fails.push(k + ' noData ' + JSON.stringify(r.noData));
    if (r.pageErrors.length) fails.push(k + ' pageErrors ' + r.pageErrors[0]);
  }
  if (fails.length) console.error('FAIL ' + fails.join('\nFAIL '));
  process.exit(fails.length ? 1 : 0);
})();
