# Plan: make `make lint` fast in the inner loop

- **Task**: speed-up-make-lint
- **Status**: implemented 2026-10-22; measured on or after 2026-10-29

## Goal

`make lint` stays a full check of every script in `SCRIPTS`, but it only
runs shellcheck on scripts whose inputs changed. Agents call it many times
while they iterate; most of those calls change zero or a few scripts.

## Design

- `bin/cached-run --per-file [--jobs N] [--key TEXT] <command...> -- <file...>`
  runs `<command...> <file>` for each file and records each pass in a ledger
  under `~/.cache/cached-run/per-file/`. The repo path is not in the key, so
  every worktree and clone shares the passes.
- A file's key is its path and git blob hash, plus the path and blob of every
  file it sources (directly or through another sourced file). `.shellcheckrc`
  sets `external-sources=true`, so a lib change can change a dependent
  script's verdict (for example SC2154). Sources are `source`/`.` with a
  constant path and `# shellcheck source=` directives, looked up from the repo
  root (as ShellCheck does) and from the script's folder. A `source-path=`
  directive makes the file uncacheable. `tests/cached-run.bats` guards that
  `.shellcheckrc` adds no other source-path.
- The Makefile key adds the shellcheck version, the `.shellcheckrc` blob, and
  `SHELLCHECK_OPTS`. Misses run `$(JOBS)` at a time (shellcheck is
  single-threaded; serial was 17-39 s).
- `make lint-full` keeps the old single uncached call. Same verdict.
- In the agent sandbox the ledger is read-only: hits still count, misses run
  every time, and the run never fails because of the cache.

## Measurement

Baseline 2026-10-22: the `make lint` lines of
`python3 ~/.claude/skills/tooling-checkup/scripts/agent_time_review.py --days 7`
sum to 6m02s/day. Success: under 1 min/day. Pivot: over 3 min/day after 7
days, then profile the gate rows with `bin/dotfiles-metrics --table`.
