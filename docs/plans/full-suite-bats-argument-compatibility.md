# Plan: restore full-suite Bats argument compatibility

- **Task**: full-suite-bats-argument-compatibility
- **Status**: parser fix implemented 2026-11-09; full green run blocked by pre-existing artifact drift

## Goal and design

Bats 1.14 rejects a standalone `--` before test paths. The full-suite macro
passed that separator directly to Bats, so no selected test ran. Remove only
those direct-Bats separators. Keep the separators that `bin/cached-run` uses to
divide its command from its per-file inputs; Bats never receives those.

The selected files, parallel flags, failure propagation, and isolated doctor
phase stay unchanged. Repo-controlled test paths do not begin with `-`, so the
supported direct form `bats [options] tests/file.bats` is safe.

## Measurement

The strict scheduler fake now rejects the same standalone separator as the
installed parser. Before the fix, the named parser control failed on
`test-all` with `Error: Bad command line option '--'`. The one-job and
multi-job controls failed on the same direct full-suite path. After removing
only the direct-Bats separators, all three controls passed.

An initial attempt also removed `cached-run`'s separator. Its real command
parser rejected that invocation and the focused test stayed red. Restoring
that distinct separator made the parser and cache controls pass without
changing coverage.

The real full-suite run executed 1,756 tests with no parser error. It found
the unchanged-base failure `command eval files are valid and point at existing
commands`: `commands/evals/kimi-goal.evals.json` names missing
`commands/kimi-goal.md`. The run later stalled under shared load and its
orphaned peer process was stopped. The task remains open pending an unrelated
artifact-drift fix and a fresh complete green run. Any parser error or coverage
change rejects the parser approach.

Anchor: installed Bats 1.14 help output; Basili, Caldiera and Rombach (1994),
Goal Question Metric.
