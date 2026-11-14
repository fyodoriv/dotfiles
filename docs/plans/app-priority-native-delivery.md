# App-priority native delivery prediction

Register before implementation. Keep the installed shell command and its
stats behavior while introducing a reversible native dispatch. Build only
from the locked, vendored source. Never run both implementations after the
native command has started: a partial native failure could duplicate actions.

- **Hypothesis:** An atomic, integrity-checked native install and a narrow
  dispatch preserve the shell command's contract and timing record while
  allowing an explicit rollback to the original command.
- **Measurement:** Hosted macOS exercises a fresh offline install, a repeat
  install, failed and interrupted installs, corrupt artifacts, rollback, help,
  configuration, stats, and owned-child action parity. Compare 30 alternating
  complete command pairs including dispatch and stats against the shell base.
- **Success:** All behavior and rollback cases pass, no unowned process is
  changed, no partial artifact is dispatched, every ordered fixture action
  matches, the candidate median is at most 400 ms, and the candidate/base
  median ratio is at most 0.40. Cold and warm builds meet 120 s and 15 s.
- **Pivot:** Any contract, integrity, rollback, or timing failure leaves the
  original shell command active. Fixture results do not prove in-use benefit.
- **Anchor:** The native delivery and gate G requirements in
  [the migration plan](rust-migration.md), the existing `lib/stats.sh` logging
  contract, and the owned-child result in [the same-day plan](app-priority-same-day.md).

The legacy code remains a temporary rollback bridge. It is not a completed
port until the native command passes gate G without the former implementation.

## Memory qualification

Register before measurement. On hosted macOS use the same owned children and
simulated actions as the complete-command fixture. Measure peak resident memory
with `/usr/bin/time -l`: two 15-run shell windows, then 15 native-dispatch runs.
Every run must preserve the expected ordered actions and exit successfully.
The two shell medians must have a ratio from 0.95 to 1.05. The candidate median
divided by the lower shell median must be at most 1.10. A missing sample, failed
action, unstable baseline or higher ratio leaves memory unqualified and the
shell active. This is a fixture measurement, not a claim about in-use memory.

Anchor: gate G and the peak-RSS definition in [the migration plan](rust-migration.md).
