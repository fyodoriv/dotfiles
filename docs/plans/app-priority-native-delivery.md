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
The owned-child test also removes the shell rules from a scratch copy and
fails if the native dispatch falls through to them.

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

### Native checksum helper trial

Register before implementation. The first hosted memory run had stable shell
baselines but a candidate ratio of 1.368, above the 1.10 limit. One possible
cost is the Perl-based checksum command on the dispatch path. On macOS, try
the system `sha256` executable; keep the existing checksum fallback elsewhere.

- **Hypothesis:** The system checksum helper reduces the candidate's peak RSS
  without changing integrity checks, actions or the timing record.
- **Measurement:** Repeat the same hosted 15 + 15 baseline and 15 candidate
  owned-child samples, plus the install and corrupt-artifact checks.
- **Success:** Both baseline medians have a ratio from 0.95 to 1.05; the
  candidate ratio is at most 1.10; every action and focused check passes.
- **Pivot:** A failed check or missed memory bound keeps the shell active.
- **Anchor:** [the first memory result](https://github.com/fyodoriv/dotfiles/actions/runs/43624038601)
  and gate G's memory requirement.

## Hosted build budget

The hosted build-budget check uses an empty Cargo home and a fresh target
directory. It measures a locked offline release build and repeats it warm
inside one exclusive queue slot. Gate G limits the cold build to 120 seconds
and the warm build to 15 seconds. Queue wait is excluded.

## Hosted result and installation

[Pull request 672](https://github.com/fyodoriv/dotfiles/pull/672) merged the
integrity-checked delivery path. The native binary is installed on the owner's
Mac; `dotfiles priority-native rollback` restores the shell path.

The [30-pair hosted fixture](https://github.com/fyodoriv/dotfiles/actions/runs/43626223966)
preserved ten ordered simulated actions in every pair, with the former shell
rules removed from the scratch candidate. The shell median was 526.10 ms and
the candidate median was 194.41 ms: ratio 0.370, within the 0.40 target. The
[hosted memory run](https://github.com/fyodoriv/dotfiles/actions/runs/43624227263)
had baseline and candidate ratios of 1.00. The [build-budget run](https://github.com/fyodoriv/dotfiles/actions/runs/43641648585)
measured 4.200 seconds cold and 0.039 seconds warm.

These controlled measurements do not prove an in-use speedup. The shortened
baseline was unstable, and live durations vary under load. The final migration
audit remains open and must verify all gate G requirements before closing the
task.
