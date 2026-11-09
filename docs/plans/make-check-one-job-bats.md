# Plan: make one-job Bats runs work with GNU parallel

- **Task**: make-check-one-job-bats
- **Status**: one-job fix implemented 2026-11-09; full green gate blocked by pre-existing artifact drift

## Goal and design

Bats 1.14 requires more than one job for its file-parallel flags. With GNU
parallel installed, the Makefile supplied those flags even for `JOBS=1`.
Select a plain serial invocation for exactly one job. Keep the existing
`--jobs N --no-parallelize-within-files` behavior for every larger value and
the no-GNU-parallel fallback.

The same `JOBS` choice controls Bats and `cached-run --jobs`, so one-job runs
omit both parallel-only arguments. Affected-test selection, the separate
heavy-run test, and doctor-last ordering do not change.

## Measurement

The scheduler fake rejects `--jobs 1` with
`--no-parallelize-within-files`. The named red control reported `expected all
one-job recipes to run serially` before the fix. After the conditional change,
the one-job control passed all three targets with exact selected-file coverage
and no parallel flags. The multi-job control passed all three targets and
retained `--jobs 2 --no-parallelize-within-files`.

The complete focused scheduler suite passed. A fresh
`JOBS=1 heavy-run --exclusive nice -n 15 make check` with no Bats flag
overrides remains required. It is blocked by the unchanged-base `kimi-goal`
eval-to-command drift recorded in the full-suite plan. Any rejected recipe,
changed selection, lost parallel option, or doctor-order change rejects the
approach.

Anchor: [Bats parallel execution](https://bats-core.readthedocs.io/en/stable/usage.html#parallel-execution);
Munafò et al. (2017), pre-registration.
