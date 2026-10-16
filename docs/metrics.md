# Metrics

These are the numbers that say whether dotfiles works for the people who use
it. Each row has a goal, a pivot, and the exact command that measures it.
`dotfiles metrics --table` runs every command in the table below and prints
the current value next to its goal and pivot.

Rules:

- A metric is an outcome that a user creates or feels: runs, rates, time,
  drift. A count of passing tests is a guard, not a metric.
- The goal is where we want to be. The pivot is the value at which we change
  the approach, not only retry. A dated pivot that is missed triggers the
  matching kill criterion in [VISION.md](../VISION.md#kill-criteria).
- Commands run from the repo root with `bash -o pipefail`. Missing data, a
  missing tool, or a source that would answer 0 for something that does not
  exist makes the command fail, and the table prints `(stub)`. It never
  prints a made-up 0.
- Baselines were measured on the owner's Mac on 2026-10-16.

## Metrics

| Metric | Goal | Pivot | Command | Story |
|---|---|---|---|---|
| North star: scorecard metrics where dotfiles beats the best competitor (of 5) | ≥ 2 by 2027-04-30 (baseline 0) | 0 on 2027-04-30 | `jq -e '.north_star.metrics_beaten' ~/.local/state/dotfiles/scorecard.json` (refresh: `scripts/benchmark-run.sh`) | all |
| Interactive shell startup, median of 5 (ms) | < 200 (baseline 80) | ≥ 300 | `for i in 1 2 3 4 5; do /usr/bin/time -p zsh -i -c exit 2>&1 >/dev/null \| awk '/^real/{print int($2*1000)}'; done \| sort -n \| sed -n 3p \| grep .` | US01, US02 |
| Commands a person types on a fresh Mac | 1 by 2027-01-31 (baseline 4) | ≥ 3 on 2027-01-31 | `jq -e '.dotfiles.metrics.manual_bootstrap_steps' ~/.local/state/dotfiles/scorecard.json` | US01 |
| `morning` runs in the last 7 days | ≥ 5 (baseline 6) | < 3 | `jq -s --arg s "$(date -u -v-7d +%FT%TZ)" '[.[] \| select(.task=="morning" and .timestamp>=$s)] \| length' ~/.dotfiles-stats.jsonl` | US02 |
| Managed files that drifted from the source (`chezmoi status` lines) | ≤ 5 by 2027-01-31 (baseline 19) | > 25 | `chezmoi status \| wc -l \| tr -d ' '` | US03 |
| `.overrides` entries that name no known check | 0 (baseline 0) | ≥ 3 | `{ bin/dotfiles-doctor --validate-overrides \|\| true; } \| awk '/^All overrides are valid/{print 0; f=1} /unknown override/{print $1; f=1} END{exit !f}'` | US04 |
| Doctor runs with no failure, last 30 runs (%) | ≥ 95 (baseline 93) | < 80 | `jq -se '[.[] \| select(.task=="doctor" and .fail!=null)] \| .[-30:] \| if length==0 then error("no runs") else (map(select(.fail==0)) \| length) * 100 / length \| floor end' ~/.dotfiles-stats.jsonl` | US05 |
| Private-reference matches on the public branch | 0 (baseline 0) | ≥ 1 (purge history the same day) | `. ~/.config/oss-readiness/oss-readiness.env && test -n "$OSS_READINESS_INTERNAL_PATTERN" && git rev-parse -q --verify origin/feat/chezmoi >/dev/null && { git grep -icE -e "$OSS_READINESS_INTERNAL_PATTERN" origin/feat/chezmoi -- . \|\| true; } \| awk -F: '{s+=$NF} END{print s+0}'` | US06 |
| PRs merged to dotfiles in the last 30 days | ≥ 30 (baseline 124) | < 8 | `gh pr list -R fyodoriv/dotfiles --state merged --search "merged:>=$(date -v-30d +%F)" --limit 500 --json number --jq length` | US07 |
| Minutes saved by automation in the last 30 days | ≥ 90 (baseline 94) | < 30 | `jq -se --arg s "$(date -u -v-30d +%FT%TZ)" '[.[] \| select(.timestamp>=$s) \| .seconds_saved] \| add / 60 \| floor' ~/.dotfiles-stats.jsonl` | US08 |
| Local-AI health checks that found an engine, last 2000 log lines (%) | ≥ 80 by 2027-01-31 (baseline 25) | < 50 on 2027-01-31 | `tail -2000 ~/.local/share/dotfiles/logs/local-ai-warmup.log \| awk '/health check start/{n++} /no inference engine reachable/{w++} END{if(n==0) exit 1; print int((n-w)*100/n)}'` | US09 |
| Public forks of dotfiles | ≥ 3 by 2027-06-30 (baseline 0) | 0 on 2027-06-30 | `gh api repos/fyodoriv/dotfiles --jq .forks_count` | US10 |
| `make check` total time, median of the last 10 passing runs (s) | ≤ 120 (baseline: first runs from 2026-10-16) | > 300 | `jq -se '[.[] \| select(.step=="total" and .status==0) \| .seconds] \| .[-10:] \| if length==0 then error("no runs") else sort \| .[length/2 \| floor] end' ~/.local/state/dotfiles/gate-timings.jsonl` | contributors |

## Guards

Guards must not get worse, but they are not goals:

- `make check` passes (shellcheck, TASKS.md lint, affected bats, install e2e when needed).
- `bash ~/.claude/skills/new-project/scripts/check-setup.sh . --profile tool` stays at 100%.

## Where the data comes from

| Source | Written by | Read by |
|---|---|---|
| `~/.dotfiles-stats.jsonl` | `lib/stats.sh` `log_run` (one JSON line per automation run) | `dotfiles stats`, `dotfiles doctor --trends`, this table |
| `~/.local/state/dotfiles/scorecard.json` | `scripts/benchmark-run.sh` (full runs only) | this table, [competition/scorecard.md](competition/scorecard.md) |
| `~/.local/state/dotfiles/gate-timings.jsonl` | `scripts/gate-timed.sh` (each `make check` step) | this table, the monthly speed review in `/tooling-checkup` |
| `~/.local/state/dotfiles/load-samples.tsv` | `bin/dotfiles-load-sampler` | `dotfiles metrics` |
| `~/.local/state/dotfiles/errors.jsonl` | `lib/errors-log.sh` (see [observability.md](observability.md#errors)) | `jq`, the monthly audit |
| `~/.local/share/dotfiles/logs/*.log` | each LaunchAgent | this table (local-AI row) |
