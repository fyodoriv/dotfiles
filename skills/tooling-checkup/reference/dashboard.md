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
dropped from `latest`. Anyone who can open the dashboard can read the files.
