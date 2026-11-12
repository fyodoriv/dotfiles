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
