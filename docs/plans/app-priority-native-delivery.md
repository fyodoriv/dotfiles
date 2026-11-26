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

## First native install on both architectures

The manual `app-priority-fixture.yml` workflow uses `delivery_check=true`
to install in a scratch home on Apple Silicon and Intel macOS 15.
Both jobs verify the binary digest, architecture, macOS 13.0 deployment
target, and exit code without `--apply`. Each job tests rollback in the
same scratch home.

The runner supplies a Rust toolchain. The check covers native artifact
portability and the current installer. Fresh full-profile toolchain
provisioning and native rollback after shell removal need their own proof.

## Fresh toolchain on both architectures

- **Hypothesis:** The install fixture can build and load App Priority using a pinned Rust toolchain in empty runner directories on both Intel and Apple Silicon.
- **Measurement:** Run `gh workflow run app-priority-fixture.yml -R fyodoriv/dotfiles --ref test/app-priority-isolated-toolchain -f delivery_check=true -f isolated_toolchain=true`. Read both delivery jobs for the selected compiler, installed artifact, no-apply exit and rollback results.
- **Success:** 2 of 2 jobs verify the installer hash, select Rust 1.100.0 from runner scratch space, build the locked crate offline, load its verified macOS 13.0 artifact and roll back successfully. Zero live priority actions.
- **Pivot:** If 1 job cannot provision the pinned toolchain, use it for the build, or verify the result, keep shell fallback and identify the failed prerequisite before changing Mac setup.
- **Anchor:** [Rustup installation options](https://rust-lang.github.io/rustup/installation/other.html), [Rust macOS targets](https://doc.rust-lang.org/rustc/platform-support/apple-darwin.html), and App Priority gate G in [the migration plan](rust-migration.md).

The current matrix uses the runner's Rust install. The added mode starts with empty Cargo and Rustup directories. It runs on macOS 15 and checks deployment metadata for macOS 13. Actual Ventura execution and apply-time integration need separate evidence.

## First native install during apply

- **Hypothesis:** A fresh eligible full-profile apply selects a verified native App Priority binary before it loads the LaunchAgent. An ineligible or previously rolled-back setup does not attempt that first install.
- **Measurement:** Run `bats -f 'app-priority first apply' tests/chezmoiscripts.bats` in hosted CI. Record the order of the install and load calls in a scratch fixture. Run the isolated architecture fixture on the same source for the real compiler and artifact.
- **Success:** All 5 fixture cases pass. A fresh eligible setup installs before load. Core profile, missing app, and explicit rollback make 0 install calls. A failed first install keeps the existing shell route. The real build passes artifact checks on both hosted architectures and changes 0 live priorities.
- **Pivot:** If 1 fixture activates native code before artifact verification, attempts a fresh install on an excluded setup, or loses the existing route on failure, stop the rollout and fix the first-install boundary.
- **Anchor:** [App Priority gate G](rust-migration.md), the existing LaunchAgent profile and app checks, and the isolated toolchain fixture above.

This phase qualifies setup during apply. The native-to-native rollback and shell removal need their own measurements.

The first setup and refresh share a time limit. First setup uses a pinned
toolchain under App Priority's data directory and checks the copied binary
without applying any priority changes before it selects it. The build, refresh,
and rollback share a per-installation lock. A refresh keeps any hold set by
rollback. The apply script prints the manual retry command if first setup fails.
The downloaded installer keeps its `rustup-init` name inside a private
temporary directory. Rustup chooses installer mode from that name.

## Hosted result and installation

[Pull request 672](https://github.com/fyodoriv/dotfiles/pull/672) merged the
integrity-checked delivery path. The native binary is installed on the owner's
Mac; `dotfiles priority-native rollback` restores the shell path.

**Updates reach the Mac on apply (2026-11-16).** The single-scan fix
(#725) merged on 2026-11-16 but this Mac still ran the 2026-11-14 build:
nothing rebuilt the binary after a merge. Every `dotfiles apply` now runs
`.chezmoiscripts/run_after_app-priority-native.sh.tmpl`. It hashes every
crate file (and `rust/.cargo/config.toml`) and reruns
`dotfiles priority-native install` when the hash differs from
`source-hash`, which only a good build writes. So a failed build, or one
stopped after 10 minutes waiting for a heavy-run slot
(`DOTFILES_NATIVE_BUILD_MAX_WAIT`), is retried on the next apply, and the
previous build stays active meanwhile. It does nothing on a Mac without the
native link (never installed, or rolled back).

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

### Roll back to a verified native binary

- **Hypothesis:** Selecting the immediate prior verified binary restores
  a usable native runtime and keeps it selected through later apply runs
  until an explicit install succeeds.
- **Measurement:** Use hosted `tests/app-priority-native.bats` and the
  isolated Intel and Apple Silicon delivery jobs. Verify the selected
  current and prior artifact digests after each changed or interrupted
  selection. No fixture applies process priority changes.
- **Success:** Both architectures select the prior verified generation and
  keep it selected after apply. All seven controls pass: first install,
  successful upgrade, persistent rollback, failed build, bad prior
  artifact, identical build, and explicit re-enable. Zero live priority
  changes and zero unverified artifact selections.
- **Pivot:** If one case loses the current working artifact, clears the hold
  implicitly, or selects an unverified artifact, retain the shell path and
  repair the selection before either rollout or shell removal.
- **Anchor:** App Priority gate G in [the migration plan](rust-migration.md)
  and the existing atomic link selection and digest validation.

The default rollback still restores the shell in this phase. Test the
native rollback option through the existing CLI action and document it
where the agent and command-line users look for rollback. Verify
interruption separately before removing the shell implementation.

Record the predecessor under the new binary's digest before changing the
current link. A failed selection leaves the current link and its receipt
in place. Native rollback checks the predecessor digest and runs a
no-apply probe before selecting it. The rollback marker pauses refresh
until an explicit install completes.

The isolated architecture check builds the older App Priority source at
`fa9c743c` and the current source with one pinned compiler. It verifies
both binaries before checking rollback, the refresh hold, and re-enable.

### Rollback after an interrupted first install

- **Hypothesis:** If the first-install launcher exits while its build worker
  is running, a successful later rollback prevents that build from selecting
  a native binary afterward.
- **Measurement:** Run the hosted fixture in `tests/app-priority-native.bats`.
  Terminate only the fixture launcher after its worker starts. Start rollback
  before releasing the scratch build and inspect the selection and hold after
  both operations finish.
- **Success:** The fixture leaves 0 current links, 1 rollback hold, and 0 live
  priority changes. The existing first-install and concurrent-rollback cases
  still pass.
- **Pivot:** If 1 interrupted worker can select a binary after rollback
  reports success, keep the shell route and move the installation lock to
  the process that can select the binary.
- **Anchor:** [App Priority gate G](rust-migration.md) and the first-install
  concurrency case in `tests/app-priority-native.bats`.

The first-install worker owns the per-installation lock. The launcher's
time limit covers the worker's lock wait and build. If the launcher exits
while the worker is still running, rollback waits for that worker before
it removes the selection.
