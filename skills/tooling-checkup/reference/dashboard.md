# Tooling health dashboard

One claude.ai Dashboard shows every checkup. It keeps one URL and updates in
place each run (Phase 10). Our data is local, so every dataset is an attached
JSON file that the checkup uploads. There are no live queries.

## Files

| What | Where |
|---|---|
| Run history (one row per `record`) | `~/.local/state/tooling-checkup/history.jsonl` |
| Exporter | `<skill-dir>/scripts/dashboard_export.py` |
| Dataset files + `manifest.json` | `~/.local/state/tooling-checkup/dashboard/` |
| Page template (reviewed in PRs) | `<skill-dir>/dashboard/index.html` |
| Dashboard URL (local only, never in a repo) | `~/.local/state/tooling-checkup/dashboard-url` |

## Datasets

| id | Rows | Source | staleAfterHours |
|---|---|---|---|
| `runs` | one per checkup: time, status, verdict, key metrics | `history.jsonl` (falls back to `last-run.json`) | 72 |
| `latest` | one: newest checkup, every numeric metric | same | 72 |
| `gate` | one per day: runs, failed runs, median `total` seconds | `~/.local/state/dotfiles/gate-timings.jsonl` | none |
| `doctor` | one per day: last pass, fail, warn, skip | `~/.dotfiles-stats.jsonl` (`task: doctor`) | none |
| `load` | one per UTC hour, last 7 days: samples, peak and mean load1, lowest free memory %, peak swap MB, overload samples (load1 > 2 x CPUs) | `~/.local/state/dotfiles/load-samples.tsv` | 24 |
| `agent_time` | one per day and project, last 14 days: tool hours, calls, failed calls | agentbrew perf log `~/.local/state/agentbrew/perf/*.jsonl` | 48 |

## Update steps (Phase 10 step 4)

1. Read the Dashboard type once: `Artifact action:"read" type_url:"https://claude.ai/artifact/GZLZthZ2sQjn7T16skfdeF"`.
2. No `dashboard-url` file: create it with `type_url`, title "Tooling health",
   and `auto_open:"after_first_write"`. Save the returned URL in `dashboard-url`.
3. Upload each file in `manifest.json` as an asset of that URL.
4. Write one `ArtifactData` batch: `dash/meta` `{title}` (on create), and per
   manifest entry `datasets/<id>` = `{title, description, source: {kind: "file", url, name}, updated: {at, by: "tooling-checkup"}, staleAfterHours?}`.
   On create, or when `dashboard/index.html` changed, add `files/index.html` `{text}`.
5. Read `data/users/me` doc `check`, as the type says.

## Privacy

Rows hold tooling metrics only. The exporter maps the home folder to `~`,
redacts token-like strings, and replaces any text that matches the local
private-pattern file (`~/.config/oss-readiness/oss-readiness.env`) with
`[redacted]`. Metric keys outside `[a-z0-9_]` and non-numeric values are
dropped from `latest`. `agent_time` names only the tooling projects
(agentbrew, dotfiles, minsky, taskgrind, tasks.md, tooling); every other
project is grouped as `other`, so private repo names never reach the page. Anyone who can open the dashboard can read the files.

## Design

`dashboard/index.html` is built with the Hallmark design skill (redesign, app
screen scope) and the `ui-ux-rankings` comfort budget. The host Dashboard type
owns the `--color-*` and `--font-*` tokens; the page maps them to `--tc-*`
tokens at `:root` and sets no literal colour. Check it with
`node ~/.claude/skills/hallmark/scripts/sloplint.mjs skills/tooling-checkup/dashboard/index.html --genre modern-minimal --scope app`.
The render tier needs `puppeteer-core`; without it, check the page in a stub
host (fixture `dash` object, d3, light and dark tokens) with Playwright.

Comfort gate: `NODE_PATH=<dir with playwright, axe-core, d3> node scripts/dashboard_comfort.cjs <index.html> <prefix>`
(run it as `heavy-run`). It renders the page on phone and desktop, light and
dark, with reduced motion, and exits 1 on a serious axe issue, text under 14
px, a touch target under 44 px, sideways overflow, a word split inside a table
cell, a table part without its ARIA role (`table`, `row`, `columnheader`, `cell`), more than 5 run rows before "Show N more", a chart without `role="img"`,
an `aria-label` with latest, min and max, a visible latest value, or a tooltip
on focus and tap, or a missing dataset that stops other panels drawing.
The gate sends a real `touchscreen.tap` on phones, checks that ArrowLeft
changes the tooltip, and requires every chart line to reach 3:1 contrast
against its panel in both themes. The page preserves the chart hue and
adjusts lightness only when needed; it checks both the panel token and the
nearest opaque ancestor background. The fixture gate measures the panel
contrast. Real-host backgrounds still need separate validation.
Overflow is measured with `scrollWidth > clientWidth` on the document and each
panel, and by every element's right edge, so `overflow-x: clip` (which Hallmark
requires on `html` and `body`) cannot hide it. The fixture holds a word wider
than a phone cell. The `load` fixture matches the exporter: one row per hour
over 168 consecutive hours, with UTC keys such as `2026-11-01T05:00Z`.
The page keeps those instants for chart binding and formats labels locally.
Both spring-forward and fall-back fixtures contain exactly 168 elapsed
hours. They are not local calendar weeks, which can contain 167 or 169
hours across a clock change.

`tests/tooling-checkup-dashboard.bats` runs the gate, plants an overflow and a
break-anywhere rule, broken ArrowLeft, ignored touch input, and a low-contrast
line to prove it fails on each. It skips when Playwright,
axe-core or d3 are missing, with a visible SKIPPED line. It looks in `DASHBOARD_NODE_PATH`, `NODE_PATH`, then the cache folder `~/.cache/dotfiles/dashboard-gate/node_modules`. Install once with `npm i --prefix ~/.cache/dotfiles/dashboard-gate playwright@1.64.1 axe-core@4.14.0 d3@7.9.0`.

## Proof boundaries

The comfort harness renders the actual dashboard fragment in a synthetic
Dashboard host with fabricated data. Its HTML and screenshots are unit
proof. They do not establish compatibility with the deployed Dashboard host
or prove that a real dashboard was updated.

After the fixture checks pass, inspect the existing dashboard through a
task-owned browser tab, read-only. Real metrics and screenshots stay local.
A UI change needs a labeled before/after pair from a deployed test dashboard
for each changed part. Capture the hourly chart binding and chart line
contrast in light and dark, on phone and desktop, with reduced motion.
Use a dedicated test dashboard and fabricated datasets for any deployment;
keep the owner's dashboard and attached data unchanged.

If browser verification, sign-in, or missing Dashboard tools prevents that
check, retain the UI work in a draft with a blocked validation task. Record
the exact missing capability. Do not substitute fixture-host screenshots for
real-host proof or claim that the deployed UI was fixed.
