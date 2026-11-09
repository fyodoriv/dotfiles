# Plan: make `make check` fast in the inner loop

- **Task**: speed-up-make-check
- **Status**: caching implemented 2026-10-22; real-agent attribution added 2026-11-09; speed outcome pending

## Goal

Agents run `make check` many times while they iterate (14 runs per session
in some sessions). A repeat run should redo only the steps whose inputs
changed, and agents should use the narrow loop while they iterate.

## Design

- **Steer**: AGENTS.md says to run `make check` once before a commit and
  names the inner loop (`make lint`, `bats tests/<name>.bats`). `make check`
  ends with the same one-line hint.
- **Lint**: already per file (speed-up-make-lint, PR #257).
- **Tests**: `bin/bats-affected --pairs` prints `test<TAB>changed file` for
  each reason a test runs. `make test` gives the pairs to
  `bin/cached-run --per-file --deps`, keyed on HEAD. A test file is skipped
  when it already passed on this HEAD with the same content of the changed
  files that select it (and the files those source). This is the
  bats-affected model, so it is as strict as `make test` was: a file that
  does not select a test cannot change its result. After a fix, only the
  tests that the fixed file selects run again.
- **Install e2e**: the e2e still runs only when an installer path changed
  against the base. It now also skips when every file that
  `tests/e2e/needs-e2e.sh` counts is unchanged since its last pass (the same
  model as the skip rule). The passes are shared by all worktrees.
  `make e2e` stays the uncached full run.
- **Make overhead**: `BIN_SCRIPTS` and `SCRIPTS` use `=` and one `file`
  call, so the six sub-makes of `make check` no longer run about 150 `file`
  processes each (`make help` went from 1.25 s to 0.16 s).

## Measurement

Baseline 2026-10-22: the dotfiles `make check` line of
`python3 ~/.claude/skills/tooling-checkup/scripts/agent_time_review.py --days 7`
is 5m04s/day (27x in 9 sessions, p95 5m12s); 2m38s/day when filed. Success:
under 1 min/day. Pivot: over 2 min/day after 7 days, then profile per step
from `~/.local/state/dotfiles/gate-timings.jsonl` and drop this approach.

## Real-agent attribution and current result

The synthetic join did not prove real receipt delivery. On 2026-11-09 the
seven-day review reported 27 Dotfiles `make check` calls totaling 57m45s, or
8m15s/day. An exclusive unchanged-base call passed every internal step in 3
seconds but took 788.87 seconds of wall time, including the `heavy-run` wait.
This identifies queue wait as part of that call's cost; it does not attribute
the older 27 calls.

Each gate now generates an opaque invocation ID. `scripts/gate-timed.sh` adds
it to every JSONL step row and prints one final bounded receipt with the exit
status. Invalid or overlong labels fail closed without running the command.
A real failed gate returned invocation
`9FB1F4F9-65D8-4410-AEEA-27B20C1839F6` with status 2; its `lint`,
`lint-tasks`, and `total` rows all carried the same ID. The final successful
repository gate is the success control. Output truncation cannot erase the
receipt without also removing the command's final result, and missing or
ambiguous receipts remain unattributed.

This instrumentation is not a speed improvement and does not meet the task's
under-1-min/day acceptance. Keep the task open. Measure the seven-day outcome
on or after 2026-11-16 and use attributed calls to choose a separately
registered optimization. Do not claim that internal step timings include
`heavy-run` queue wait.
