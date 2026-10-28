// Comfort gate for dashboard/index.html in a stub Dashboard host (fixture data, no network).
// Run: NODE_PATH=<dir with playwright axe-core d3> node dashboard_comfort.cjs <fragment.html> <prefix>
// Writes <prefix>-<theme>-<size>.{html,png} under $TMPDIR and prints JSON. Exit 1 when a gate fails:
// serious axe issue, text under 14 px, touch target under 44 px, sideways scroll, a word split mid-word in a
// table cell, or a runs table that shows more than 5 rows before "Show N more". d3 and axe-core files are found on NODE_PATH.
// usage: node harness.cjs <fragment.html> <prefix>
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
// Both packages hide files behind an exports map, so look the files up on the module search path.
const findFile = rel => { const p = require.resolve.paths(rel).map(d => path.join(d, rel)).find(f => fs.existsSync(f)); if (!p) throw new Error('not found on NODE_PATH: ' + rel); return p; };
const axeSrc = fs.readFileSync(findFile('axe-core/axe.min.js'), 'utf8');
const d3src = fs.readFileSync(findFile('d3/dist/d3.min.js'), 'utf8');
const frag = fs.readFileSync(process.argv[2], 'utf8');
const prefix = process.argv[3];
const TMP = process.env.TMPDIR;
const day = i => new Date(Date.UTC(2026, 9, 1 + i)).toISOString().slice(0, 10);
const runs = Array.from({ length: 20 }, (_, i) => ({ time: new Date(Date.UTC(2026, 9, 1 + i, 9)).toISOString(), status: ['healthy', 'gaps', 'broken'][i % 3], machine_overload_rows_24h: (i * 7) % 11, agent_tool_hours_7d: 10 + i, verdict: 'Synthetic verdict text for row ' + i + ' with a long sentence that wraps on phones' }));
const data = {
  latest: { status: 'ok', data: [{ ...runs[19], status: 'gaps', machine_peak_load1_24h: 6.4, claude_echo_p95_ms: 220 }] },
  runs: { status: 'ok', data: runs },
  gate: { status: 'ok', data: Array.from({ length: 14 }, (_, i) => ({ day: day(i), median_total_s: 60 + i * 3 })) },
  doctor: { status: 'ok', data: Array.from({ length: 14 }, (_, i) => ({ day: day(i), fail: i % 4 })) },
  load: { status: 'ok', data: Array.from({ length: 168 }, (_, i) => ({ hour: day(Math.floor(i / 24)) + 'T' + String(i % 24).padStart(2, '0') + ':00', samples: 12, peak_load1: Math.round((2 + 3 * Math.abs(Math.sin(i / 9)) + (i % 24 > 9 && i % 24 < 18 ? 2 : 0)) * 10) / 10 })) },
  agent_time: { status: 'ok', data: ['agentbrew', 'dotfiles', 'minsky', 'other'].flatMap(p => Array.from({ length: 14 }, (_, i) => ({ day: day(i), project: p, tool_hours: 0.5 + i / 10, calls: 100 + i, failed_calls: i % 3 }))) },
};
const themes = {
  light: '--color-fg:#1f1e1d;--color-fg-muted:#5c5a55;--color-panel:#ffffff;--color-border-line:#d9d6cf;--color-ok:#1a7f37;--color-warn:#8a5a00;--color-bad:#b3261e;--bg:#faf9f5;',
  dark: '--color-fg:#ece9e2;--color-fg-muted:#aaa69d;--color-panel:#262624;--color-border-line:#44423e;--color-ok:#5ac27a;--color-warn:#e0b04a;--color-bad:#ff8a80;--bg:#1a1a18;',
};
const page = t => `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Tooling health</title><style>:root{${themes[t]}--font-anthropic-sans:system-ui,sans-serif;--font-anthropic-serif:Georgia,serif}body{margin:0;padding:16px;background:var(--bg);font-family:system-ui}</style></head><body><script>${d3src}</script><script>window.dash={colors:['#c96442','#3b6ea5','#6a8f3a','#8a5aa8','#b08a1e'],_cb:[],onData(f){this._cb.push(f)},data(n){return ${JSON.stringify(data)}[n]}};</script><main>${frag}</main><script>dash._cb.forEach(function(f){f()})</script></body></html>`;
(async () => {
  const b = await chromium.launch();
  const out = {};
  const sizes = { phone: [375, 812], desktop: [1280, 800] };
  for (const t of ['light', 'dark']) for (const [sn, [w, h]] of Object.entries(sizes)) {
    const ctx = await b.newContext({ viewport: { width: w, height: h }, colorScheme: t, reducedMotion: 'reduce', hasTouch: sn === 'phone' });
    const p = await ctx.newPage();
    const file = path.join(TMP, `wD-${prefix}-${t}-${sn}.html`);
    fs.writeFileSync(file, page(t));
    const errs = []; p.on('pageerror', e => errs.push(String(e)));
    await p.goto('file://' + file); await p.waitForTimeout(500);
    await p.addScriptTag({ content: axeSrc });
    const axe = await p.evaluate(async () => { const r = await axe.run(document, { runOnly: ['wcag2a', 'wcag2aa', 'wcag22aa', 'best-practice'] }); return r.violations.filter(v => ['serious', 'critical'].includes(v.impact)).map(v => v.id + ':' + v.nodes.length); });
    const m = await p.evaluate(() => {
      const small = new Set();
      document.querySelectorAll('main *').forEach(el => {
        const own = [...el.childNodes].some(n => n.nodeType === 3 && n.textContent.trim());
        if (own && parseFloat(getComputedStyle(el).fontSize) < 14) small.add(el.tagName.toLowerCase() + '.' + (el.className.baseVal ?? el.className));
      });
      const targets = [...document.querySelectorAll('a,button,input,select,textarea,[tabindex]:not([tabindex="-1"]),[role=button]')].filter(e => { const r = e.getBoundingClientRect(); return r.width < 44 || r.height < 44; }).length;
      const splitWords = [];
      document.querySelectorAll('td,th').forEach(c => {
        if (!c.getClientRects().length) return;
        const w = document.createTreeWalker(c, NodeFilter.SHOW_TEXT);
        for (let n; (n = w.nextNode());) {
          const re = /\S+/g; let m;
          while ((m = re.exec(n.textContent))) { const r = document.createRange(); r.setStart(n, m.index); r.setEnd(n, m.index + m[0].length); if (r.getClientRects().length > 1) splitWords.push(m[0]); }
        }
      });
      const runsRows = document.querySelectorAll('#tc-runs tbody tr').length, runsVisible = [...document.querySelectorAll('#tc-runs tbody tr')].filter(r => r.getClientRects().length).length;
      return { splitWords, runsRows, runsVisible, smallText: [...small], smallTargets: targets, sideways: document.documentElement.scrollWidth > innerWidth + 1, scrollW: document.documentElement.scrollWidth, innerW: innerWidth };
    });
    out[`${t}-${sn}`] = { axeSerious: axe, ...m, pageErrors: errs };
    await p.screenshot({ path: path.join(TMP, `wD-${prefix}-${t}-${sn}.png`), fullPage: true });
    await ctx.close();
  }
  await b.close();
  console.log(JSON.stringify(out));
  const bad = Object.values(out).some(r => r.axeSerious.length || r.smallText.length || r.smallTargets || r.sideways || r.splitWords.length || r.runsVisible > 5 || r.pageErrors.length);
  process.exit(bad ? 1 : 0);
})();
