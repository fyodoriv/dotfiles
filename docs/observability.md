# Observability

How to see what dotfiles did on this Mac, what failed, and how healthy it is.
Everything stays on the Mac, with one opt-in exit: `dotfiles telemetry` (see
[Telemetry](#telemetry)). `dotfiles metrics --share` writes an aggregate-only
snapshot only when you ask for one.

## Logs

| Log | Written by | What one entry holds | Read it with |
|---|---|---|---|
| `~/.dotfiles-stats.jsonl` | `lib/stats.sh` `log_run`, and the doctor | One JSON line per automation run: `task`, `timestamp`, `seconds_saved`, `units`, `ok` (true or false), `duration_ms`; doctor runs add `pass`, `fail`, `fixed`, `warn`, `skip` counts. `bin/dotfiles-install run` adds one `install` line per real run, with the heal doctor's `fail` count. An interactive zsh adds one `shell-start` line a day (`duration_ms` from `~/.zshrc` start to the first prompt). No paths or messages. | `dotfiles stats`, `dotfiles doctor --trends`, [metrics.md](metrics.md) |
| `~/.local/state/dotfiles/errors.jsonl` | `lib/errors-log.sh` `log_error` | One JSON line per failure (see [Errors](#errors)) | `jq` (below) |
| `~/.local/state/dotfiles/load-samples.tsv` | `bin/dotfiles-load-sampler` (every 30 s) | Load, CPU, memory, swap, process count, top 3 process names, and who owns each (PID, parent, redacted 80-char command) | `dotfiles-load-sampler --report 24`, `dotfiles metrics`, the `load` dataset of the tooling health dashboard |
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

## Performance gate

`make perf-gate` (also a step of `make check`) stops a PR that makes a tracked
command slower. `scripts/perf-gate.sh` times each command in
`config/perf-budget.tsv` in two trees in the same run: your working tree and a
checkout of the merge-base with the default branch. It needs no stored
baseline, so it works the same on every machine.

- **Fails when** the fastest run in your tree is more than 10% and more than
  3 ms slower than the fastest run at the base, or above the command's ceiling
  in the budget file.
- **How it times**: 2 warmups, then 15 runs per tree, base and head in turn,
  with an empty environment and a scratch HOME. It compares the minimums. A
  command that looks slower is timed again, up to two more rounds.
- **Skips** when the diff touches no runtime path: `perf gate: skipped (no
  runtime change)`. The path list is the `PERF_GATE_PATH` lines of the budget
  file at the base and in your tree together, so a PR cannot shrink its own
  scope. `scripts/perf-gate.sh --force` times anyway.
- **Setup errors exit 2, never pass**: no base commit (run `git fetch origin`,
  or set `PERF_GATE_BASE=<ref>`; `PERF_GATE_NO_BASE=1` checks the ceilings
  only), a command that fails in your tree or in the base checkout, a git
  failure, a budget file with no path line or no command, an allow line that
  names no command, a bad `PERF_GATE_RUNS`, an unknown argument, no perl, a
  cache folder that is not an absolute path or cannot be written, a folder
  at the base checkout path that the gate did not build. The gate
  prints the base ref and the date of its last commit, so a stale ref shows.
- **A change to the gate itself**: a PR that changes `scripts/perf-gate.sh`,
  `scripts/perf-gate.pl`, or `tests/perf-gate.bats` changes its own judge.
  The gate prints a warning and exits 2 unless the budget file has a new line
  `PERF_GATE_ALLOW=perf-gate:<reason>`. Review such a PR by hand.
- **Allow lines**: an allow line counts when the base budget file does not
  have the same line (same name and same reason); a line that the base has
  unchanged is stale. On a stale line the gate stops before any timing, exits
  1, and prints `remove this line from config/perf-budget.tsv: <line>`. A PR
  that needs the allow again writes the line with its own reason.
- **Queue**: timing runs through `heavy-run --exclusive` and prints a line
  while it waits for the slot. Inside a heavy-run slot (`heavy-run make
  check`) it runs directly.
- **On a failure**: make the command faster. If the cost is intended, raise
  the ceiling and give the reason in the PR. A step above 10% in one PR also
  needs a `PERF_GATE_ALLOW=<name>:<reason>` line in the budget file; the next
  PR removes it or gives its own reason.
- **New hot-path command**: add its row to the budget file in the same PR.
  A new name whose file the base commit does not have gets the ceiling check
  only. A name that the base budget file has is never new: the base runs its
  own row, so a PR cannot avoid the comparison by pointing the row at another
  file or a wrapper. A row removed from the budget file fails the gate unless
  an allow line names it.
- **Machine output**: `scripts/perf-gate.sh --json` prints `base_min`,
  `head_min`, `ratio`, and `verdict` per command.
- **Base checkouts**: detached worktrees under
  `~/.cache/dotfiles/perf-gate.noindex/<commit>`; the newest two are kept.
  Before each use the gate checks that a checkout is at its commit and has no
  changed, new, or ignored file; if not, it builds the checkout again. It
  builds and removes checkouts under a lock, and removes only its own: a
  folder with the marker `<commit>.ready` next to it. It unlinks a symlink
  without following it.
- **Field numbers**: the gate measures one machine before a merge. Numbers
  from real installs will be on the performance dashboard (link: to be added
  with the telemetry timing events).

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
