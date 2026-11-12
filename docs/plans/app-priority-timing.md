# App-priority timing: prediction

Registered before implementation on 2026-11-11. The existing plan records
whole-second durations, so those values cannot measure a subsecond change.

- **Hypothesis:** millisecond clock samples make the scheduled run measurable
  without changing its priority decisions or exposing process details.
- **Measurement:** `bats tests/app-priority.bats` with a controlled clock,
  plus `heavy-run make check`.
- **Success:** the controlled 125 ms run records exactly 125 ms; all existing
  priority tests pass; no extra process data enters the log.
- **Pivot:** if any priority decision changes, the clock fails, or the sample
  is invalid, keep the old behavior and repair the measurement before using
  it as a baseline. Do not mix old whole-second samples into new windows.
- **Anchor:** [Rust migration measurement contract](rust-migration.md#measurement-contract).

## Deployment evidence

PR #586 merged at `57a4b14`. Its timing code was present in the live
checkout by 2026-11-12 02:12:39 UTC. A tagged sample was recorded at
02:13:04 UTC; the record does not identify its triggering process. The two
seven-day before windows must both start
after that deployment time. They cannot be complete before 2026-11-26
02:12:39 UTC, and still need the plan's sample-count and stability checks.
