# Observability

How to see what dotfiles did on this Mac, what failed, and how healthy it is.
Everything stays on the Mac, with one opt-in exit: `dotfiles telemetry` (see
[Telemetry](#telemetry)). `dotfiles metrics --share` writes an aggregate-only
snapshot only when you ask for one.

## Logs

| Log | Written by | What one entry holds | Read it with |
|---|---|---|---|
| `~/.dotfiles-stats.jsonl` | `lib/stats.sh` `log_run`, and the doctor | One JSON line per automation run: `task`, `timestamp`, `seconds_saved`, `units`, `ok` (true or false), `duration_ms`; doctor runs add `pass`, `fail`, `fixed`, `warn`, `skip` counts. No paths or messages. | `dotfiles stats`, `dotfiles doctor --trends`, [metrics.md](metrics.md) |
| `~/.local/state/dotfiles/errors.jsonl` | `lib/errors-log.sh` `log_error` | One JSON line per failure (see [Errors](#errors)) | `jq` (below) |
| `~/.local/state/dotfiles/load-samples.tsv` | `bin/dotfiles-load-sampler` (every 30 s) | Load, CPU, memory, swap, process count, top 3 process names | `dotfiles-load-sampler --report 24`, `dotfiles metrics`, the `load` dataset of the tooling health dashboard |
| `~/.local/state/dotfiles/gate-timings.jsonl` | `scripts/gate-timed.sh` (each `make check` step) | `ts`, `step`, `seconds`, `status` | `dotfiles metrics --table`, the speed review in `/tooling-checkup`, the `gate` dataset of the tooling health dashboard |
| `~/.local/state/dotfiles/scorecard.json` | `scripts/benchmark-run.sh` (full runs) | The latest competitive scorecard | `dotfiles metrics --table` |
| `~/.local/share/dotfiles/logs/*.log` | each LaunchAgent | Free-text job output, trimmed by each job | `tail`, `rg` |

The JSON logs are content-free on purpose: counts, fixed codes, and check IDs,
never file contents, paths, or command output. Only the LaunchAgent text logs
hold free text, and they never leave the Mac. The load samples name processes,
so `dotfiles metrics --share` keeps only their numeric lines.

`log_run` allow-lists its fields too: a task is a short lowercase name and
`units` a number; anything else is written as `invalid` and `1`. The outcome
(`log_run <task> [units] [ok|error] [duration_ms]`) becomes `ok` true or false,
and a non-number duration falls back to the script run time (`$SECONDS`).

Tests never write the real errors or stats logs: both logs stay off inside
any bats test unless the test sets `DOTFILES_ERRORS_LOG=1` or
`DOTFILES_STATS_LOG=1`, and the Makefile and `tests/test_helper.bash` also
export both as `0`. `tests/errors-log.bats` fails if any of this goes away.

## Errors

`log_error <story> <source> <code> [check]` appends one line to
`~/.local/state/dotfiles/errors.jsonl`:

```json
{"ts":"2026-10-16T21:10:00Z","story":"US05","source":"doctor","code":"check_failed","check":"git.user_name"}
```

- Every field is allow-listed: `story` is `US01`–`US99`, `source` is
  `doctor`, `sync`, or `morning`, `code` is a short fixed code, and `check` is
  a check ID. Any other value is written as `invalid`, so no free text can
  leak into the log.
- `story` names the user story the failure breaks, so failures map to
  [user stories](user-stories/README.md) and [metrics](metrics.md).
- The log keeps the last 2000 lines. `DOTFILES_ERRORS_LOG=0` turns it off.

| Source | Code | Story | When |
|---|---|---|---|
| `doctor` | `check_failed` (with `check`) | US05 | a check still fails at the end of a run |
| `sync` | `apply_failed`, `fetch_failed`, `pull_failed`, `push_failed` | US05 | the 30-minute sync job could not finish a step |
| `morning` | `pull_failed` | US02 | `morning` could not pull a repo |

Read it:

```bash
jq -s 'group_by(.story) | map({story: .[0].story, failures: length})' ~/.local/state/dotfiles/errors.jsonl
jq -r 'select(.source == "doctor") | .check' ~/.local/state/dotfiles/errors.jsonl | sort | uniq -c | sort -rn | head
```

There is no external error reporter. dotfiles is a local tool, and its
privacy contract keeps machine data on the machine (accepted push back,
agentbrew new-project requirements map, 2026-10-16).

## Telemetry

`bin/dotfiles-telemetry` is the one adapter that can send the stats log to
PostHog EU (`https://eu.i.posthog.com/batch/`). It is opt-in by key:

- **Sends nothing** until the owner stores a project key:
  `security add-generic-password -s dotfiles -a posthog_key -w` (or sets
  `DOTFILES_POSTHOG_KEY`). The key is never printed, logged, or committed.
- **What leaves**: per stats line, `dotfiles.run`, its time, `task`, and the
  number fields (`seconds_saved`, `units`, `pass`, `fail`, `fixed`, `warn`,
  `skip`, `ok`, `duration_ms`), keyed by a random install id. Never paths,
  names, host, or messages. `$process_person_profile: false` and
  `$geoip_disable: true` on every event; no replay, flags, or surveys.
- **When**: at most once a day, batched, after `dotfiles` showed its one-line
  notice. A failed send never fails a command; the cursor moves only after a
  send works.
- **Off switches**: `dotfiles telemetry off`, or `DO_NOT_TRACK=1`.
- **Check it**: `dotfiles telemetry status`; `dotfiles telemetry send --dry-run`
  prints the exact body with the key hidden.
- **State**: `~/.local/state/dotfiles/telemetry.json` (install id, cursor,
  on/off, last send day; mode 600). Delete it to reset.

## Health check

`dotfiles doctor` is the health check. It runs every module's checks and
prints one line per check. Every failing line ends with its fix:

```text
  ✗ pull.rebase = true — fix: dotfiles doctor --fix --module git
  ✗ /Users/you/.gitconfig → dotfiles (not managed) — fix: chezmoi apply '/Users/you/.gitconfig'
  ✗ git user.name is set — fix: no auto-fix; follow docs/module-reference.md (git)
```

- `dotfiles doctor --fix` applies every automatic fix; `--module NAME` limits
  the run; `--json` gives each check's status and fix command for scripts.
- The `com.dotfiles.dotfiles-doctor` LaunchAgent runs it weekly with `--fix`.
- The install ends with it (README quick start), so a new Mac starts with a
  health report.
- `tests/errors-log.bats` fails when a `fail` line in `bin/dotfiles-doctor`
  has no fix.
