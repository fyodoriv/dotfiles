# User Story: See How Much Time Automation Saves

> Concrete numbers — not vibes — for how much time dotfiles automation has saved.

## Viewing Stats

```bash
dotfiles stats               # full dashboard
dotfiles stats --oneliner    # single line (embedded in morning/status)
```

### Example Output

```
📊 Dotfiles Automation Stats

  Total time saved:  ~4h 23m
  Total runs:       847
  Active since:     2025-01-15
  Current streak:   12 day(s)

  Last 7 days:  98 runs, ~32m saved

  By task:
    sync                  412 runs   ~2h 45m saved
    cursor-priority       280 runs   ~1h 10m saved
    doctor                 52 runs   ~8m saved
    cleanup                48 runs   ~48m saved
    git-maintain           35 runs   ~11m saved
    morning                20 runs   ~5m saved
```

## Per-Task Estimates

| Task | Runs via | Per-unit estimate | What scales it |
|------|----------|-------------------|----------------|
| `sync` | LaunchAgent (every 30 min) | 3s / cycle | — |
| `doctor` | LaunchAgent (weekly) | 2s / config check | Module checks evaluated |
| `audit` | Manual (security audit) | 2s / run | — |
| `cleanup` | LaunchAgent (weekly) | 10s / cache | Cache locations cleaned |
| `git-maintain` | LaunchAgent (daily) | 5s / repo | Repos in `~/apps` |
| `cursor-priority` | LaunchAgent (every 60s) | 0s (background) | Flat |
| `morning` | Manual (daily) | 15s / repo | Repos pulled |

Estimates are conservative — minimum manual time you'd spend doing the same task by hand.

## How It Works

Scripts call `log_run <task> [units]` from `lib/stats.sh`, appending a JSONL line to `~/.dotfiles-stats.jsonl` (machine-specific, not tracked in git).

The `morning` and `status` commands show a time-saved one-liner automatically.

## Files Involved

| File | Purpose |
|------|---------|
| `bin/dotfiles-stats` | Stats dashboard script |
| `lib/stats.sh` | `log_run` and `get_time_saved_summary` functions |
| `~/.dotfiles-stats.jsonl` | Stats storage (not in git) |
