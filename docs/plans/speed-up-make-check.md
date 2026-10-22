# Plan: make `make check` fast in the inner loop

- **Task**: speed-up-make-check
- **Status**: implemented 2026-10-22; measured on or after 2026-10-29

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
