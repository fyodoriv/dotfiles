# Tasks

<!-- policy: do NOT bypass commit hooks (--no-verify) and do NOT push to a
remote without explicit operator approval in the current session. -->

<!-- policy: every new task names the competitive scorecard metric it
advances (a **Competitive-goal** line). The metrics are in
docs/competition/scorecard.md; run scripts/benchmark-run.sh --json to refresh
them. -->

## P0

## P1

- [ ] Headless browser test runs bypass the heavy-run lock
  - **ID**: headless-browser-runs-bypass-heavy-run
  - **Blocked**: needs-time — 2026-10-28: shipped the hook extension (e2e/ui scripts, exec playwright, make e2e/test-all) and the doctor check `resilience.headless_chrome_under_heavy_run`; Acceptance part 1 is met. Part 2 needs data: read the unexplained-overload count in the tooling-checkup machine-metrics phase on the next two checkups after this lands, then close (under 40 rows, peak load1 under 100) or pivot (over 150 rows).
  - **Tags**: performance, reliability, agents
  - **Details**: The 2026-10-27 `/tooling-checkup` found 197 unexplained overload rows (load1 over 20) in the last 24 h of `machine_metrics`, peak load1 257.6 at 2026-10-27T09:16. The top processes in those rows were `chrome-headless-shell` (112 rows), `python` (105), and `node` (84). The 2026-10-25 checkup had the same 197 count, so the problem persists. `heavy-run` only queues commands that agents wrap by hand; Playwright and agent-browser runs started directly (e2e suites, UI audits, MCP browser sessions) do not take the lock. Find which callers start headless Chrome without the lock, then make the lock hard to skip: for example, a Playwright/agent-browser wrapper on PATH that takes the `heavy-run` lock, or a doctor/hook warning when a browser test runs outside it.
  - **Files**: `bin/heavy-run`, `modules/resilience/doctor.sh`, `docs/` (heavy-run doc), `tests/`
  - **Output**: code
  - **Acceptance**: a headless browser test run started without `heavy-run` either queues on the lock or is reported by the doctor; the next two checkups show the unexplained overload count under the Success threshold.
  - **Hypothesis**: routing headless browser test runs through the `heavy-run` lock cuts unexplained overload rows (load1 over 20) in 24 h of `machine_metrics` from 197 to under 40, because parallel `chrome-headless-shell` fan-out is the top process in those rows.
  - **Measurement**: the unexplained-overload count in the tooling-checkup machine-metrics phase (24 h window of `machine_metrics`, rows with load1 over 20 and no `heavy-run` holder), on the next two checkups after the change lands.
  - **Success**: under 40 rows per 24 h and peak load1 under 100 on both checkups.
  - **Pivot**: over 150 rows on both checkups -> the lock is not the lever; profile the `python` and `node` rows instead and drop the wrapper approach.
  - **Anchor**: tooling-checkup runs 2026-10-25 and 2026-10-27 (machine_metrics phase); Gunther 2007, *Guerrilla Capacity Planning* (load beyond core count); Forsgren, Humble, Kim 2018 (stability).
  - **Competitive-goal**: none — machine stability for agent work (docs/metrics.md), not a scorecard metric.

## P2

- [ ] Doctor warns when Apple Silicon lacks Amphetamine Power Protect
  - **ID**: keepawake-power-protect-check
  - **Tags**: reliability, agents
  - **Details**: On an M1 Pro laptop the pmset log showed `Clamshell Sleep ... Using Batt` three times in two days (at 63% and 100%) while the keep-awake manager's protection applied and Amphetamine's Closed-Display session was active. On AC the same lid close entered DarkWake (stayed awake). Amphetamine's own pref `Ask To Install Power Protect` was still 1, and no Amphetamine helper was installed. Power Protect is Amphetamine's add-on for Closed-Display sessions on Apple Silicon laptops when power is connected or removed. The docs and setup hint now name it; the doctor does not check it yet.
  - **Files**: `modules/resilience/doctor.sh`, `docs/module-reference.md`, `tests/`
  - **Output**: code
  - **Acceptance**: on arm64 with Amphetamine installed, an advisory check fails when Power Protect is missing and passes after install; the check reads a real install marker (find its path on a Mac after install), not the `Ask To Install Power Protect` pref alone.
  - **Hypothesis**: after Power Protect is installed, a 2-minute lid close on battery logs no `Clamshell Sleep` entry, so Remote Control stays connected.
  - **Measurement**: `pmset -g log | grep "Clamshell Sleep"` during an unplugged lid-close test, before and after install.
  - **Success**: no battery `Clamshell Sleep` line during the test window after install.
  - **Pivot**: still sleeps with Power Protect installed -> lid-closed work on battery needs `pmset disablesleep`; document it as AC-only instead.
  - **Anchor**: field pmset log 2026-10-27/28; Amphetamine App Store release notes 5.3 and 5.3.1 (Power Protect).
  - **Competitive-goal**: none; agent uptime on a laptop (docs/metrics.md), not a scorecard metric.

- [ ] Record each real install run so the README can prove one-command setup
  - **ID**: proof-install-field-outcome
  - **Tags**: metrics, proof
  - **Details**: The README Proof row "One command sets up a Mac" says `not measured yet`. `bin/dotfiles-install run` writes no stats event, so no real install is counted. Add a content-free `log_run install` event with ok/error, minutes to a clean doctor, and the failing-check count, then a `scripts/proof.sh` row that reads it.
  - **Files**: `bin/dotfiles-install`, `lib/stats.sh`, `scripts/proof.sh`, `tests/proof.bats`
  - **Output**: code
  - **Acceptance**: after one real install, `scripts/proof.sh` fills the row with `real use` and the README test passes.
  - **Competitive-goal**: `manual_bootstrap_steps` (docs/competition/scorecard.md).
  - **Blocked**: needs-time — 2026-10-27: shipped the recording part. `bin/dotfiles-install run` writes one `install` stats line (ok, `duration_ms`, the heal doctor's `fail` count) and `scripts/proof.sh` fills the row from `install_clean_minutes`. No real install has run since. Unblock: after the next real install on any Mac, run `scripts/proof.sh` there and check the row says `real use`; then close.

- [ ] Record shell start time on real machines for the README Proof section
  - **ID**: proof-shell-start-field
  - **Tags**: metrics, proof, performance
  - **Details**: The Proof row "The shell starts fast" says `not measured yet`; only a local run is shown (230 ms on 2026-10-26, above the 200 ms budget and the "~30ms" Highlights line). Sample the start time of real interactive shells (for example, once a day from the existing zsh startup timer) into the stats log, then add a `real use` row.
  - **Files**: `home/zshrc`, `lib/stats.sh`, `scripts/proof.sh`
  - **Output**: code
  - **Acceptance**: the row shows a median of real shell starts with its machine count; the Highlights line matches the measured number.
  - **Competitive-goal**: none; shell start is the "Interactive shell startup" row of docs/metrics.md, not a scorecard metric.
  - **Blocked**: needs-time — 2026-10-27: shipped the recording part. `home/zshrc` logs one `shell-start` stats line a day (first prompt, `duration_ms`), and `scripts/proof.sh` fills the row from `shell_start_field_ms`. Unblock: on or after 2026-11-03 (7 daily samples after `dotfiles apply`), run `scripts/proof.sh`, then set the Highlights line to the measured median and close.

- [ ] Skip unchanged chezmoi scripts inside a full apply
  - **ID**: apply-skip-unchanged-scripts
  - **Tags**: performance
  - **Details**: One managed-Mac checkup measured `dotfiles apply` at 537 s (#338). `--if-changed` skips a whole apply when nothing changed, and the apply now prints per-step timing (pull, chezmoi apply, doctor). Next, find which `run_after_*` scripts and doctor checks take the time, and key the slow ones on a content hash, like the JetBrains stamp.
  - **Files**: `bin/dotfiles`, `.chezmoiscripts/`, `bin/dotfiles-doctor`
  - **Output**: code
  - **Acceptance**: a second full apply with no source change spends under 60 s in `chezmoi apply`, per the timing line.
  - **Competitive-goal**: `reproducibility_pct` (docs/competition/scorecard.md).
  - **Blocked**: needs-real-machine-data — 2026-10-27: the 537 s apply was measured on a managed Mac, and the apply timing line shows only pull, chezmoi apply, and doctor. Finding the slow `run_after_*` scripts needs a timed full apply there (for example `chezmoi apply -v` with each script start and end time noted, or `DOTFILES_DEBUG` per-script timing). A guess at which scripts to hash-key, without that data, could skip real work. Unblock: one timed full apply on that Mac, with the per-script seconds pasted into this task.

- [ ] Checkup skips the full `dotfiles apply` when nothing changed
  - **ID**: checkup-skip-apply-when-unchanged
  - **Tags**: perf, agents
  - **Details**: The 2026-10-20 `/tooling-checkup` ran `dotfiles apply` for 191 s (last run: 214 s) right after `dotfiles-sync` printed "No changes". The apply converges drift too, so a skip must still detect drift cheaply (for example `chezmoi status` plus the doctor modules the checkup already runs).
  - **Files**: `skills/update-tooling/SKILL.md`, `skills/tooling-checkup/SKILL.md`
  - **Output**: code
  - **Acceptance**: a checkup on an unchanged machine finishes the apply step in under 30 s, and a hand edit is still reported.
  - **Hypothesis**: skipping the full apply when the source head and live drift are unchanged cuts the checkup apply step from ~200 s to under 30 s.
  - **Measurement**: the `dotfiles_apply_secs` metric in `python3 ~/.claude/skills/tooling-checkup/scripts/checkup_state.py diff`, on the next two checkups.
  - **Success**: under 30 s on a no-change run.
  - **Pivot**: over 90 s, or a missed drift item -> keep the full apply and speed up its slowest step instead.
  - **Anchor**: tooling-checkup agent time review 2026-10-20; Forsgren, Humble, Kim 2018 (lead time); perf-review skill known fixes.
  - **Competitive-goal**: `noop_reapply_ms` (docs/competition/scorecard.md).
  - **Blocked**: needs-time — 2026-10-22: shipped `dotfiles apply --if-changed` and switched update-tooling and tooling-checkup to it (PR #253). Baseline `dotfiles_apply_secs`: 191 s and 214 s on the last two checkups. The skip check took 0.74 to 1.09 s on this Mac at load1 114. Measure on the next two checkups, on or after 2026-10-29, with `python3 ~/.claude/skills/tooling-checkup/scripts/checkup_state.py diff` (`dotfiles_apply_secs`), then close or pivot.

- [ ] Make `make check` fast in the inner loop
  - **ID**: speed-up-make-check
  - **Blocked**: needs-time — 2026-10-22: shipped per-test caching in `make test` (`bin/bats-affected --pairs` + `bin/cached-run --per-file --deps`, keyed on HEAD), an input-keyed cache for the install e2e, lazy lint lists (one `file` call), and inner-loop steering in AGENTS.md and the `make check` output (PR #261). Baseline 2026-10-22: dotfiles `make check` line 5m04s/day (27x in 9 sessions, p95 5m12s); tooling line 17m57s/day (42x in 3 sessions). A four-run edit loop took 1034 s before and 440 s after (repeat runs 459 s -> 65 s and 164 s -> 6 s). Measure on or after 2026-10-29 with `python3 ~/.claude/skills/tooling-checkup/scripts/agent_time_review.py --days 7` (the dotfiles `make check` line), then close or pivot.
  - **Tags**: perf, agents
  - **Details**: The 2026-10-20 checkup time review: `make check` costs 2m38s/day (17x in 7 sessions, p95 5m12s). Agents run the full gate while iterating instead of `bin/bats-affected`.
  - **Files**: `Makefile`, `AGENTS.md`, `bin/cached-run`
  - **Output**: code
  - **Acceptance**: the `make check` line in the 7-day agent time review is under 1 min/day.
  - **Hypothesis**: steering the inner loop to `bin/bats-affected` and caching unchanged steps cuts `make check` from 2m38s/day to under 1 min/day.
  - **Measurement**: `python3 ~/.claude/skills/tooling-checkup/scripts/agent_time_review.py --days 7` (the dotfiles `make check` line), 7 days after the change lands.
  - **Success**: under 1 min/day.
  - **Pivot**: still over 2 min/day after 7 days -> profile per step from `~/.local/state/dotfiles/gate-timings.jsonl` and drop this approach.
  - **Anchor**: tooling-checkup agent time review 2026-10-20; Forsgren, Humble, Kim 2018 (lead time); perf-review skill known fixes.
  - **Competitive-goal**: none — agent gate speed (docs/metrics.md gate row), not a scorecard metric.

- [ ] Account for every executable before Rust migration
  - **ID**: rust-source-inventory
  - **Tags**: migration, rust
  - **Mode**: AFK implementation — record any unavailable owner-only live proof as a linked blocked HITL child before claiming the slice; see the plan.
  - **Details**: Deliver the component manifest and a thin pinned Rust adapter to agentbrew's inventory validator. Account for every owned executable, embedded interpreter, generated mapping, test and caller without duplicating the shared engine. Plan and boundary/rollback contract: [Rust migration](docs/plans/rust-migration.md).
  - **Output**: code
  - **Blocked**: needs-agentbrew-inventory — the reusable validator in agentbrew task `rust-source-inventory` must be delivered before this adapter can pass. Source collection can proceed independently.
  - **Acceptance**: Unclassified owned executable components 0; unexplained exceptions 0; every component has one owner and a measured slice or a precise permitted exception. The runnable validator rejects every planted embedded, extensionless and generated-code omission before any production replacement.
  - **Hypothesis**: A source-and-caller inventory makes unclassified owned executable components reach 0, including extensionless and embedded code, without changing runtime behavior.
  - **Measurement**: `heavy-run cargo run --locked --release --manifest-path rust/Cargo.toml --bin migration-check -- inventory --check` — proposed exact command delivered by this preparation task through the pinned shared validator; not currently available and not deferred to the dependent measurement-harness task.
  - **Success**: Unclassified owned executable components 0; unexplained exceptions 0; every component has one owner and a measured slice or a precise permitted exception.
  - **Pivot**: Any missed component or blanket exception changes the inventory method to execution/caller analysis before a replacement starts.
  - **Anchor**: Basili, Caldiera, Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration); Forsgren, Humble, Kim 2018 (performance and stability).
  - **Competitive-goal**: none — native runtime independence; existing scorecard behavior is a guard and speed claims require separate evidence.

- [ ] Measure each Rust step against a sealed baseline
  - **ID**: rust-measurement-harness
  - **Tags**: migration, rust
  - **Mode**: AFK implementation — record any unavailable owner-only live proof as a linked blocked HITL child before claiming the slice; see the plan.
  - **Details**: Thin pinned adapter to agentbrew's engine; fixture registry, sealed baselines, planted-fault controls. Plan and boundary/rollback contract: [Rust migration](docs/plans/rust-migration.md).
  - **Output**: code
  - **Blocked by**: rust-source-inventory
  - **Blocked**: needs-agentbrew-harness — the shared measuring engine in agentbrew task `rust-measurement-harness` must be delivered before this adapter. See the cross-repo dependency in the linked plan.
  - **Acceptance**: Planted-fault detection 100%; invalid/missing/contaminated baselines rejected 100%; valid sealed unchanged baselines for every registered slice; production behavior unchanged.
  - **Hypothesis**: The shared engine and thin adapter detect 100% of planted compatibility/safety/measurement faults before replacing production code.
  - **Measurement**: Preparation delivers and proves `heavy-run --exclusive cargo run --locked --release --manifest-path rust/Cargo.toml --bin migration-check -- harness-selftest` and `heavy-run --exclusive cargo run --locked --release --manifest-path rust/Cargo.toml --bin migration-check -- baseline --slice all --seal`; these commands do not exist yet. Production replacement starts only after this preparation is merged.
  - **Success**: Planted-fault detection 100%; invalid/missing/contaminated baselines rejected 100%; valid sealed unchanged baselines for every registered slice; production behavior unchanged.
  - **Pivot**: Any missed planted fault, accepted invalid baseline or private payload retention changes the measuring approach before porting production.
  - **Anchor**: Basili, Caldiera, Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration); Forsgren, Humble, Kim 2018 (performance and stability).
  - **Competitive-goal**: none — native runtime independence; existing scorecard behavior is a guard and speed claims require separate evidence.

- [ ] Install and roll back native tools without extra setup
  - **ID**: rust-native-delivery
  - **Tags**: migration, rust
  - **Mode**: AFK implementation — record any unavailable owner-only live proof as a linked blocked HITL child before claiming the slice; see the plan.
  - **Details**: Locked build/artifact integrity, atomic dispatch/install, supported Mac targets and rollback; bin/dotfiles-install, lifecycle scripts. Plan and boundary/rollback contract: [Rust migration](docs/plans/rust-migration.md).
  - **Output**: code
  - **Blocked by**: rust-measurement-harness
  - **Acceptance**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B. Preserve this boundary's exact approved protocols, file effects, failure controls and owner scope; retain per-step evidence and independent review.
  - **Hypothesis**: Remove the legacy implementation for this boundary while preserving observable behavior and resource cost. Expected result: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Measurement**: Future harness gate, delivered before replacement: `heavy-run --exclusive cargo run --locked --release --manifest-path rust/Cargo.toml --bin migration-check -- compare --slice rust-native-delivery --samples 60`. Seal actual B and commit the numerical prediction before code. Existing affected tests and `heavy-run make check` remain guards.
  - **Success**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Pivot**: Any behavior/safety failure stops rollout; resource upper bound >1.10 changes architecture or slice boundary before retry. Missing or inconclusive evidence leaves the task open and the old implementation active.
  - **Anchor**: Basili, Caldiera, Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration); Forsgren, Humble, Kim 2018 (performance and stability).
  - **Competitive-goal**: none — native runtime independence; existing scorecard behavior is a guard and speed claims require separate evidence.

- [ ] Run bounded processes and locks through Rust
  - **ID**: rust-process-primitives
  - **Tags**: migration, rust
  - **Mode**: AFK implementation — record any unavailable owner-only live proof as a linked blocked HITL child before claiming the slice; see the plan.
  - **Details**: Locks, bounded child groups, timeouts and caching; lib/lock.sh, lib/run-with-timeout.sh, bin/cached-run. Plan and boundary/rollback contract: [Rust migration](docs/plans/rust-migration.md).
  - **Output**: code
  - **Blocked by**: rust-native-delivery
  - **Acceptance**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B. Preserve this boundary's exact approved protocols, file effects, failure controls and owner scope; retain per-step evidence and independent review.
  - **Hypothesis**: Remove the legacy implementation for this boundary while preserving observable behavior and resource cost. Expected result: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Measurement**: Future harness gate, delivered before replacement: `heavy-run --exclusive cargo run --locked --release --manifest-path rust/Cargo.toml --bin migration-check -- compare --slice rust-process-primitives --samples 60`. Seal actual B and commit the numerical prediction before code. Existing affected tests and `heavy-run make check` remain guards.
  - **Success**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Pivot**: Any behavior/safety failure stops rollout; resource upper bound >1.10 changes architecture or slice boundary before retry. Missing or inconclusive evidence leaves the task open and the old implementation active.
  - **Anchor**: Basili, Caldiera, Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration); Forsgren, Humble, Kim 2018 (performance and stability).
  - **Competitive-goal**: none — native runtime independence; existing scorecard behavior is a guard and speed claims require separate evidence.

- [ ] Run the shared resource queue safely through Rust
  - **ID**: rust-shared-queue
  - **Tags**: migration, rust
  - **Mode**: AFK implementation — record any unavailable owner-only live proof as a linked blocked HITL child before claiming the slice; see the plan.
  - **Details**: CPU/memory admission, inner-worker budgets, exclusive timings; bin/heavy-run, app-priority, headless detection. Plan and boundary/rollback contract: [Rust migration](docs/plans/rust-migration.md). Start only after the current queue safety work lands and its admission/lifetime/privacy/exclusivity contract has independent proof.
  - **Output**: code
  - **Blocked by**: rust-process-primitives
  - **Acceptance**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B. Preserve this boundary's exact approved protocols, file effects, failure controls and owner scope; retain per-step evidence and independent review. Queue over-admissions, memory-pressure admissions, forged nested bypasses, starvation and exclusive overlaps must be 0 in controlled traces; measure useful CPU/memory throughput and interactive latency, not only sleeping jobs. Isolate admission state to fixture workers and scrub inherited nesting markers while retaining the outer machine reservation and resource budget.
  - **Hypothesis**: Remove the legacy implementation for this boundary while preserving observable behavior and resource cost. Expected result: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Measurement**: Future harness gate, delivered before replacement: `heavy-run --exclusive cargo run --locked --release --manifest-path rust/Cargo.toml --bin migration-check -- compare --slice rust-shared-queue --samples 60`. Seal actual B and commit the numerical prediction before code. Existing affected tests and `heavy-run make check` remain guards.
  - **Success**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Pivot**: Any behavior/safety failure stops rollout; resource upper bound >1.10 changes architecture or slice boundary before retry. Missing or inconclusive evidence leaves the task open and the old implementation active.
  - **Anchor**: Basili, Caldiera, Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration); Forsgren, Humble, Kim 2018 (performance and stability).
  - **Competitive-goal**: none — native runtime independence; existing scorecard behavior is a guard and speed claims require separate evidence.

- [ ] Discover repositories and select work through Rust
  - **ID**: rust-repository-discovery
  - **Tags**: migration, rust
  - **Mode**: AFK implementation — record any unavailable owner-only live proof as a linked blocked HITL child before claiming the slice; see the plan.
  - **Details**: Inventory/fingerprints, workspace status, affected selection and tasks; learn-repos tools, bats-affected, check-all, add-task. Plan and boundary/rollback contract: [Rust migration](docs/plans/rust-migration.md).
  - **Output**: code
  - **Blocked by**: rust-native-delivery
  - **Acceptance**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B. Preserve this boundary's exact approved protocols, file effects, failure controls and owner scope; retain per-step evidence and independent review.
  - **Hypothesis**: Remove the legacy implementation for this boundary while preserving observable behavior and resource cost. Expected result: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Measurement**: Future harness gate, delivered before replacement: `heavy-run --exclusive cargo run --locked --release --manifest-path rust/Cargo.toml --bin migration-check -- compare --slice rust-repository-discovery --samples 60`. Seal actual B and commit the numerical prediction before code. Existing affected tests and `heavy-run make check` remain guards.
  - **Success**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Pivot**: Any behavior/safety failure stops rollout; resource upper bound >1.10 changes architecture or slice boundary before retry. Missing or inconclusive evidence leaves the task open and the old implementation active.
  - **Anchor**: Basili, Caldiera, Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration); Forsgren, Humble, Kim 2018 (performance and stability).
  - **Competitive-goal**: none — native runtime independence; existing scorecard behavior is a guard and speed claims require separate evidence.

- [ ] Keep action discovery and configuration working through Rust
  - **ID**: rust-cli-core
  - **Tags**: migration, rust
  - **Mode**: AFK implementation — record any unavailable owner-only live proof as a linked blocked HITL child before claiming the slice; see the plan.
  - **Details**: CLI/action registry, config/profile/enterprise precedence, output; bin/dotfiles*, lib/output.sh. Plan and boundary/rollback contract: [Rust migration](docs/plans/rust-migration.md).
  - **Output**: code
  - **Blocked by**: rust-native-delivery
  - **Acceptance**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B. Preserve this boundary's exact approved protocols, file effects, failure controls and owner scope; retain per-step evidence and independent review.
  - **Hypothesis**: Remove the legacy implementation for this boundary while preserving observable behavior and resource cost. Expected result: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Measurement**: Future harness gate, delivered before replacement: `heavy-run --exclusive cargo run --locked --release --manifest-path rust/Cargo.toml --bin migration-check -- compare --slice rust-cli-core --samples 60`. Seal actual B and commit the numerical prediction before code. Existing affected tests and `heavy-run make check` remain guards.
  - **Success**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Pivot**: Any behavior/safety failure stops rollout; resource upper bound >1.10 changes architecture or slice boundary before retry. Missing or inconclusive evidence leaves the task open and the old implementation active.
  - **Anchor**: Basili, Caldiera, Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration); Forsgren, Humble, Kim 2018 (performance and stability).
  - **Competitive-goal**: none — native runtime independence; existing scorecard behavior is a guard and speed claims require separate evidence.

- [ ] Preserve doctor discovery and repair results through Rust
  - **ID**: rust-doctor-core
  - **Tags**: migration, rust
  - **Mode**: AFK implementation — record any unavailable owner-only live proof as a linked blocked HITL child before claiming the slice; see the plan.
  - **Details**: Discovery, budgets, overrides, result/fix/recheck semantics; bin/dotfiles-doctor. Plan and boundary/rollback contract: [Rust migration](docs/plans/rust-migration.md).
  - **Output**: code
  - **Blocked by**: rust-cli-core, rust-process-primitives
  - **Acceptance**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B. Preserve this boundary's exact approved protocols, file effects, failure controls and owner scope; retain per-step evidence and independent review.
  - **Hypothesis**: Remove the legacy implementation for this boundary while preserving observable behavior and resource cost. Expected result: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Measurement**: Future harness gate, delivered before replacement: `heavy-run --exclusive cargo run --locked --release --manifest-path rust/Cargo.toml --bin migration-check -- compare --slice rust-doctor-core --samples 60`. Seal actual B and commit the numerical prediction before code. Existing affected tests and `heavy-run make check` remain guards.
  - **Success**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Pivot**: Any behavior/safety failure stops rollout; resource upper bound >1.10 changes architecture or slice boundary before retry. Missing or inconclusive evidence leaves the task open and the old implementation active.
  - **Anchor**: Basili, Caldiera, Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration); Forsgren, Humble, Kim 2018 (performance and stability).
  - **Competitive-goal**: none — native runtime independence; existing scorecard behavior is a guard and speed claims require separate evidence.

- [ ] Check shell and editor health through Rust
  - **ID**: rust-doctor-shell-editors
  - **Tags**: migration, rust
  - **Mode**: AFK implementation — record any unavailable owner-only live proof as a linked blocked HITL child before claiming the slice; see the plan.
  - **Details**: shell, terminal, prompt, local-bin, editor, vscode, jetbrains module behavior. Plan and boundary/rollback contract: [Rust migration](docs/plans/rust-migration.md).
  - **Output**: code
  - **Blocked by**: rust-doctor-core
  - **Acceptance**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B. Preserve this boundary's exact approved protocols, file effects, failure controls and owner scope; retain per-step evidence and independent review.
  - **Hypothesis**: Remove the legacy implementation for this boundary while preserving observable behavior and resource cost. Expected result: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Measurement**: Future harness gate, delivered before replacement: `heavy-run --exclusive cargo run --locked --release --manifest-path rust/Cargo.toml --bin migration-check -- compare --slice rust-doctor-shell-editors --samples 60`. Seal actual B and commit the numerical prediction before code. Existing affected tests and `heavy-run make check` remain guards.
  - **Success**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Pivot**: Any behavior/safety failure stops rollout; resource upper bound >1.10 changes architecture or slice boundary before retry. Missing or inconclusive evidence leaves the task open and the old implementation active.
  - **Anchor**: Basili, Caldiera, Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration); Forsgren, Humble, Kim 2018 (performance and stability).
  - **Competitive-goal**: none — native runtime independence; existing scorecard behavior is a guard and speed claims require separate evidence.

- [ ] Check security, Git and SSH health through Rust
  - **ID**: rust-doctor-security
  - **Tags**: migration, rust
  - **Mode**: AFK implementation — record any unavailable owner-only live proof as a linked blocked HITL child before claiming the slice; see the plan.
  - **Details**: security, git, ssh module denial/repair behavior. Plan and boundary/rollback contract: [Rust migration](docs/plans/rust-migration.md).
  - **Output**: code
  - **Blocked by**: rust-doctor-core
  - **Acceptance**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B. Preserve this boundary's exact approved protocols, file effects, failure controls and owner scope; retain per-step evidence and independent review.
  - **Hypothesis**: Remove the legacy implementation for this boundary while preserving observable behavior and resource cost. Expected result: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Measurement**: Future harness gate, delivered before replacement: `heavy-run --exclusive cargo run --locked --release --manifest-path rust/Cargo.toml --bin migration-check -- compare --slice rust-doctor-security --samples 60`. Seal actual B and commit the numerical prediction before code. Existing affected tests and `heavy-run make check` remain guards.
  - **Success**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Pivot**: Any behavior/safety failure stops rollout; resource upper bound >1.10 changes architecture or slice boundary before retry. Missing or inconclusive evidence leaves the task open and the old implementation active.
  - **Anchor**: Basili, Caldiera, Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration); Forsgren, Humble, Kim 2018 (performance and stability).
  - **Competitive-goal**: none — native runtime independence; existing scorecard behavior is a guard and speed claims require separate evidence.

- [ ] Check workspace and sync health through Rust
  - **ID**: rust-doctor-workflow
  - **Tags**: migration, rust
  - **Mode**: AFK implementation — record any unavailable owner-only live proof as a linked blocked HITL child before claiming the slice; see the plan.
  - **Details**: chezmoi, sync, workflow, workspace, plugins, enterprise modules. Plan and boundary/rollback contract: [Rust migration](docs/plans/rust-migration.md).
  - **Output**: code
  - **Blocked by**: rust-doctor-core, rust-repository-discovery
  - **Acceptance**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B. Preserve this boundary's exact approved protocols, file effects, failure controls and owner scope; retain per-step evidence and independent review.
  - **Hypothesis**: Remove the legacy implementation for this boundary while preserving observable behavior and resource cost. Expected result: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Measurement**: Future harness gate, delivered before replacement: `heavy-run --exclusive cargo run --locked --release --manifest-path rust/Cargo.toml --bin migration-check -- compare --slice rust-doctor-workflow --samples 60`. Seal actual B and commit the numerical prediction before code. Existing affected tests and `heavy-run make check` remain guards.
  - **Success**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Pivot**: Any behavior/safety failure stops rollout; resource upper bound >1.10 changes architecture or slice boundary before retry. Missing or inconclusive evidence leaves the task open and the old implementation active.
  - **Anchor**: Basili, Caldiera, Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration); Forsgren, Humble, Kim 2018 (performance and stability).
  - **Competitive-goal**: none — native runtime independence; existing scorecard behavior is a guard and speed claims require separate evidence.

- [ ] Check browser and resilience health through Rust
  - **ID**: rust-doctor-browsers
  - **Tags**: migration, rust
  - **Mode**: AFK implementation — record any unavailable owner-only live proof as a linked blocked HITL child before claiming the slice; see the plan.
  - **Details**: agent-browser, chrome, resilience checks and safe repair. Plan and boundary/rollback contract: [Rust migration](docs/plans/rust-migration.md).
  - **Output**: code
  - **Blocked by**: rust-doctor-core, rust-shared-queue
  - **Acceptance**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B. Preserve this boundary's exact approved protocols, file effects, failure controls and owner scope; retain per-step evidence and independent review.
  - **Hypothesis**: Remove the legacy implementation for this boundary while preserving observable behavior and resource cost. Expected result: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Measurement**: Future harness gate, delivered before replacement: `heavy-run --exclusive cargo run --locked --release --manifest-path rust/Cargo.toml --bin migration-check -- compare --slice rust-doctor-browsers --samples 60`. Seal actual B and commit the numerical prediction before code. Existing affected tests and `heavy-run make check` remain guards.
  - **Success**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Pivot**: Any behavior/safety failure stops rollout; resource upper bound >1.10 changes architecture or slice boundary before retry. Missing or inconclusive evidence leaves the task open and the old implementation active.
  - **Anchor**: Basili, Caldiera, Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration); Forsgren, Humble, Kim 2018 (performance and stability).
  - **Competitive-goal**: none — native runtime independence; existing scorecard behavior is a guard and speed claims require separate evidence.

- [ ] Check agent and memory readiness through Rust
  - **ID**: rust-doctor-agents
  - **Tags**: migration, rust
  - **Mode**: AFK implementation — record any unavailable owner-only live proof as a linked blocked HITL child before claiming the slice; see the plan.
  - **Details**: agentbrew, claude, codex, memory, minsky adapters; owner APIs and readiness. Plan and boundary/rollback contract: [Rust migration](docs/plans/rust-migration.md).
  - **Output**: code
  - **Blocked by**: rust-doctor-core
  - **Acceptance**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B. Preserve this boundary's exact approved protocols, file effects, failure controls and owner scope; retain per-step evidence and independent review.
  - **Hypothesis**: Remove the legacy implementation for this boundary while preserving observable behavior and resource cost. Expected result: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Measurement**: Future harness gate, delivered before replacement: `heavy-run --exclusive cargo run --locked --release --manifest-path rust/Cargo.toml --bin migration-check -- compare --slice rust-doctor-agents --samples 60`. Seal actual B and commit the numerical prediction before code. Existing affected tests and `heavy-run make check` remain guards.
  - **Success**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Pivot**: Any behavior/safety failure stops rollout; resource upper bound >1.10 changes architecture or slice boundary before retry. Missing or inconclusive evidence leaves the task open and the old implementation active.
  - **Anchor**: Basili, Caldiera, Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration); Forsgren, Humble, Kim 2018 (performance and stability).
  - **Competitive-goal**: none — native runtime independence; existing scorecard behavior is a guard and speed claims require separate evidence.

- [ ] Check macOS and machine profiles through Rust
  - **ID**: rust-doctor-macos
  - **Tags**: migration, rust
  - **Mode**: AFK implementation — record any unavailable owner-only live proof as a linked blocked HITL child before claiming the slice; see the plan.
  - **Details**: macos, personal-machine, home-theater profile checks. Plan and boundary/rollback contract: [Rust migration](docs/plans/rust-migration.md).
  - **Output**: code
  - **Blocked by**: rust-doctor-core
  - **Acceptance**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B. Preserve this boundary's exact approved protocols, file effects, failure controls and owner scope; retain per-step evidence and independent review.
  - **Hypothesis**: Remove the legacy implementation for this boundary while preserving observable behavior and resource cost. Expected result: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Measurement**: Future harness gate, delivered before replacement: `heavy-run --exclusive cargo run --locked --release --manifest-path rust/Cargo.toml --bin migration-check -- compare --slice rust-doctor-macos --samples 60`. Seal actual B and commit the numerical prediction before code. Existing affected tests and `heavy-run make check` remain guards.
  - **Success**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Pivot**: Any behavior/safety failure stops rollout; resource upper bound >1.10 changes architecture or slice boundary before retry. Missing or inconclusive evidence leaves the task open and the old implementation active.
  - **Anchor**: Basili, Caldiera, Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration); Forsgren, Humble, Kim 2018 (performance and stability).
  - **Competitive-goal**: none — native runtime independence; existing scorecard behavior is a guard and speed claims require separate evidence.

- [ ] Check local AI and toolchain health through Rust
  - **ID**: rust-doctor-local-ai
  - **Tags**: migration, rust
  - **Mode**: AFK implementation — record any unavailable owner-only live proof as a linked blocked HITL child before claiming the slice; see the plan.
  - **Details**: local-ai, local-llm, tools, upgrade discovery and opt-out behavior. Plan and boundary/rollback contract: [Rust migration](docs/plans/rust-migration.md).
  - **Output**: code
  - **Blocked by**: rust-doctor-core
  - **Acceptance**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B. Preserve this boundary's exact approved protocols, file effects, failure controls and owner scope; retain per-step evidence and independent review.
  - **Hypothesis**: Remove the legacy implementation for this boundary while preserving observable behavior and resource cost. Expected result: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Measurement**: Future harness gate, delivered before replacement: `heavy-run --exclusive cargo run --locked --release --manifest-path rust/Cargo.toml --bin migration-check -- compare --slice rust-doctor-local-ai --samples 60`. Seal actual B and commit the numerical prediction before code. Existing affected tests and `heavy-run make check` remain guards.
  - **Success**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Pivot**: Any behavior/safety failure stops rollout; resource upper bound >1.10 changes architecture or slice boundary before retry. Missing or inconclusive evidence leaves the task open and the old implementation active.
  - **Anchor**: Basili, Caldiera, Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration); Forsgren, Humble, Kim 2018 (performance and stability).
  - **Competitive-goal**: none — native runtime independence; existing scorecard behavior is a guard and speed claims require separate evidence.

- [ ] Check remaining supported apps through Rust
  - **ID**: rust-doctor-apps
  - **Tags**: migration, rust
  - **Mode**: AFK implementation — record any unavailable owner-only live proof as a linked blocked HITL child before claiming the slice; see the plan.
  - **Details**: extras, obsidian and any later inventory-discovered supported modules. Plan and boundary/rollback contract: [Rust migration](docs/plans/rust-migration.md).
  - **Output**: code
  - **Blocked by**: rust-doctor-core
  - **Acceptance**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B. Preserve this boundary's exact approved protocols, file effects, failure controls and owner scope; retain per-step evidence and independent review.
  - **Hypothesis**: Remove the legacy implementation for this boundary while preserving observable behavior and resource cost. Expected result: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Measurement**: Future harness gate, delivered before replacement: `heavy-run --exclusive cargo run --locked --release --manifest-path rust/Cargo.toml --bin migration-check -- compare --slice rust-doctor-apps --samples 60`. Seal actual B and commit the numerical prediction before code. Existing affected tests and `heavy-run make check` remain guards.
  - **Success**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Pivot**: Any behavior/safety failure stops rollout; resource upper bound >1.10 changes architecture or slice boundary before retry. Missing or inconclusive evidence leaves the task open and the old implementation active.
  - **Anchor**: Basili, Caldiera, Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration); Forsgren, Humble, Kim 2018 (performance and stability).
  - **Competitive-goal**: none — native runtime independence; existing scorecard behavior is a guard and speed claims require separate evidence.

- [ ] Apply and maintain packages and settings through Rust
  - **ID**: rust-apply-install
  - **Tags**: migration, rust
  - **Mode**: AFK implementation — record any unavailable owner-only live proof as a linked blocked HITL child before claiming the slice; see the plan.
  - **Details**: Defaults/apply, package/cask installers, signing/shims, upgrades/uninstall; .chezmoiscripts, macos*.sh, apply-state/apply-defaults. Plan and boundary/rollback contract: [Rust migration](docs/plans/rust-migration.md).
  - **Output**: code
  - **Blocked by**: rust-cli-core, rust-process-primitives
  - **Acceptance**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B. Preserve this boundary's exact approved protocols, file effects, failure controls and owner scope; retain per-step evidence and independent review.
  - **Hypothesis**: Remove the legacy implementation for this boundary while preserving observable behavior and resource cost. Expected result: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Measurement**: Future harness gate, delivered before replacement: `heavy-run --exclusive cargo run --locked --release --manifest-path rust/Cargo.toml --bin migration-check -- compare --slice rust-apply-install --samples 60`. Seal actual B and commit the numerical prediction before code. Existing affected tests and `heavy-run make check` remain guards.
  - **Success**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Pivot**: Any behavior/safety failure stops rollout; resource upper bound >1.10 changes architecture or slice boundary before retry. Missing or inconclusive evidence leaves the task open and the old implementation active.
  - **Anchor**: Basili, Caldiera, Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration); Forsgren, Humble, Kim 2018 (performance and stability).
  - **Competitive-goal**: none — native runtime independence; existing scorecard behavior is a guard and speed claims require separate evidence.

- [ ] Validate and manage signed plugins through Rust
  - **ID**: rust-plugin-trust
  - **Tags**: migration, rust
  - **Mode**: AFK implementation — record any unavailable owner-only live proof as a linked blocked HITL child before claiming the slice; see the plan.
  - **Details**: Signed plugin pins, sandbox/capabilities and transactional lifecycle; bin/dotfiles-plugin, lib/plugin*. Plan and boundary/rollback contract: [Rust migration](docs/plans/rust-migration.md).
  - **Output**: code
  - **Blocked by**: rust-cli-core, rust-process-primitives
  - **Acceptance**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B. Preserve this boundary's exact approved protocols, file effects, failure controls and owner scope; retain per-step evidence and independent review.
  - **Hypothesis**: Remove the legacy implementation for this boundary while preserving observable behavior and resource cost. Expected result: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Measurement**: Future harness gate, delivered before replacement: `heavy-run --exclusive cargo run --locked --release --manifest-path rust/Cargo.toml --bin migration-check -- compare --slice rust-plugin-trust --samples 60`. Seal actual B and commit the numerical prediction before code. Existing affected tests and `heavy-run make check` remain guards.
  - **Success**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Pivot**: Any behavior/safety failure stops rollout; resource upper bound >1.10 changes architecture or slice boundary before retry. Missing or inconclusive evidence leaves the task open and the old implementation active.
  - **Anchor**: Basili, Caldiera, Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration); Forsgren, Humble, Kim 2018 (performance and stability).
  - **Competitive-goal**: none — native runtime independence; existing scorecard behavior is a guard and speed claims require separate evidence.

- [ ] Run sync, services and power orchestration through Rust
  - **ID**: rust-services-power
  - **Tags**: migration, rust
  - **Mode**: AFK implementation — record any unavailable owner-only live proof as a linked blocked HITL child before claiming the slice; see the plan.
  - **Details**: Sync/reload/drift, wake/keepawake/Amphetamine, watchdog and notices; launchagents, tooling-sync. Plan and boundary/rollback contract: [Rust migration](docs/plans/rust-migration.md).
  - **Output**: code
  - **Blocked by**: rust-cli-core, rust-process-primitives
  - **Acceptance**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B. Preserve this boundary's exact approved protocols, file effects, failure controls and owner scope; retain per-step evidence and independent review.
  - **Hypothesis**: Remove the legacy implementation for this boundary while preserving observable behavior and resource cost. Expected result: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Measurement**: Future harness gate, delivered before replacement: `heavy-run --exclusive cargo run --locked --release --manifest-path rust/Cargo.toml --bin migration-check -- compare --slice rust-services-power --samples 60`. Seal actual B and commit the numerical prediction before code. Existing affected tests and `heavy-run make check` remain guards.
  - **Success**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Pivot**: Any behavior/safety failure stops rollout; resource upper bound >1.10 changes architecture or slice boundary before retry. Missing or inconclusive evidence leaves the task open and the old implementation active.
  - **Anchor**: Basili, Caldiera, Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration); Forsgren, Humble, Kim 2018 (performance and stability).
  - **Competitive-goal**: none — native runtime independence; existing scorecard behavior is a guard and speed claims require separate evidence.

- [ ] Preserve public-write and damage guards through Rust
  - **ID**: rust-git-security-guards
  - **Tags**: migration, rust
  - **Mode**: AFK implementation — record any unavailable owner-only live proof as a linked blocked HITL child before claiming the slice; see the plan.
  - **Details**: Git/GitHub and agent hooks, leak/secret/private-ref scans, attribution, git-safe. Plan and boundary/rollback contract: [Rust migration](docs/plans/rust-migration.md).
  - **Output**: code
  - **Blocked by**: rust-cli-core, rust-process-primitives
  - **Acceptance**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B. Preserve this boundary's exact approved protocols, file effects, failure controls and owner scope; retain per-step evidence and independent review.
  - **Hypothesis**: Remove the legacy implementation for this boundary while preserving observable behavior and resource cost. Expected result: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Measurement**: Future harness gate, delivered before replacement: `heavy-run --exclusive cargo run --locked --release --manifest-path rust/Cargo.toml --bin migration-check -- compare --slice rust-git-security-guards --samples 60`. Seal actual B and commit the numerical prediction before code. Existing affected tests and `heavy-run make check` remain guards.
  - **Success**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Pivot**: Any behavior/safety failure stops rollout; resource upper bound >1.10 changes architecture or slice boundary before retry. Missing or inconclusive evidence leaves the task open and the old implementation active.
  - **Anchor**: Basili, Caldiera, Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration); Forsgren, Humble, Kim 2018 (performance and stability).
  - **Competitive-goal**: none — native runtime independence; existing scorecard behavior is a guard and speed claims require separate evidence.

- [ ] Automate browsers and native events through Rust
  - **ID**: rust-browser-native
  - **Tags**: migration, rust
  - **Mode**: AFK implementation — record any unavailable owner-only live proof as a linked blocked HITL child before claiming the slice; see the plan.
  - **Details**: CDP/tab leases, temp browser, Slack, profiles, native quit/Dock events; bin/agent-tab, lib/*.swift. Plan and boundary/rollback contract: [Rust migration](docs/plans/rust-migration.md).
  - **Output**: code
  - **Blocked by**: rust-process-primitives, rust-shared-queue
  - **Acceptance**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B. Preserve this boundary's exact approved protocols, file effects, failure controls and owner scope; retain per-step evidence and independent review.
  - **Hypothesis**: Remove the legacy implementation for this boundary while preserving observable behavior and resource cost. Expected result: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Measurement**: Future harness gate, delivered before replacement: `heavy-run --exclusive cargo run --locked --release --manifest-path rust/Cargo.toml --bin migration-check -- compare --slice rust-browser-native --samples 60`. Seal actual B and commit the numerical prediction before code. Existing affected tests and `heavy-run make check` remain guards.
  - **Success**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Pivot**: Any behavior/safety failure stops rollout; resource upper bound >1.10 changes architecture or slice boundary before retry. Missing or inconclusive evidence leaves the task open and the old implementation active.
  - **Anchor**: Basili, Caldiera, Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration); Forsgren, Humble, Kim 2018 (performance and stability).
  - **Competitive-goal**: none — native runtime independence; existing scorecard behavior is a guard and speed claims require separate evidence.

- [ ] Run local AI agent and loop orchestration through Rust
  - **ID**: rust-local-ai-runtime
  - **Tags**: migration, rust
  - **Mode**: AFK implementation — record any unavailable owner-only live proof as a linked blocked HITL child before claiming the slice; see the plan.
  - **Details**: Agent/loop retry/verify/rollback/warmup logic; lib/local-ai-*.py, bin/local-ai-*. Plan and boundary/rollback contract: [Rust migration](docs/plans/rust-migration.md).
  - **Output**: code
  - **Blocked by**: rust-cli-core, rust-process-primitives
  - **Acceptance**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B. Preserve this boundary's exact approved protocols, file effects, failure controls and owner scope; retain per-step evidence and independent review.
  - **Hypothesis**: Remove the legacy implementation for this boundary while preserving observable behavior and resource cost. Expected result: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Measurement**: Future harness gate, delivered before replacement: `heavy-run --exclusive cargo run --locked --release --manifest-path rust/Cargo.toml --bin migration-check -- compare --slice rust-local-ai-runtime --samples 60`. Seal actual B and commit the numerical prediction before code. Existing affected tests and `heavy-run make check` remain guards.
  - **Success**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Pivot**: Any behavior/safety failure stops rollout; resource upper bound >1.10 changes architecture or slice boundary before retry. Missing or inconclusive evidence leaves the task open and the old implementation active.
  - **Anchor**: Basili, Caldiera, Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration); Forsgren, Humble, Kim 2018 (performance and stability).
  - **Competitive-goal**: none — native runtime independence; existing scorecard behavior is a guard and speed claims require separate evidence.

- [ ] Preserve metrics and checkup results through Rust
  - **ID**: rust-metrics-checkup
  - **Tags**: migration, rust
  - **Mode**: AFK implementation — record any unavailable owner-only live proof as a linked blocked HITL child before claiming the slice; see the plan.
  - **Details**: Checkup Python processors/exporter, stats/proof/scorecard/telemetry; UI unchanged. Plan and boundary/rollback contract: [Rust migration](docs/plans/rust-migration.md).
  - **Output**: code
  - **Blocked by**: rust-cli-core, rust-process-primitives
  - **Acceptance**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B. Preserve this boundary's exact approved protocols, file effects, failure controls and owner scope; retain per-step evidence and independent review.
  - **Hypothesis**: Remove the legacy implementation for this boundary while preserving observable behavior and resource cost. Expected result: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Measurement**: Future harness gate, delivered before replacement: `heavy-run --exclusive cargo run --locked --release --manifest-path rust/Cargo.toml --bin migration-check -- compare --slice rust-metrics-checkup --samples 60`. Seal actual B and commit the numerical prediction before code. Existing affected tests and `heavy-run make check` remain guards.
  - **Success**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Pivot**: Any behavior/safety failure stops rollout; resource upper bound >1.10 changes architecture or slice boundary before retry. Missing or inconclusive evidence leaves the task open and the old implementation active.
  - **Anchor**: Basili, Caldiera, Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration); Forsgren, Humble, Kim 2018 (performance and stability).
  - **Competitive-goal**: none — native runtime independence; existing scorecard behavior is a guard and speed claims require separate evidence.

- [ ] Capture PTYs and measure latency through Rust
  - **ID**: rust-pty-tools
  - **Tags**: migration, rust
  - **Mode**: AFK implementation — record any unavailable owner-only live proof as a linked blocked HITL child before claiming the slice; see the plan.
  - **Details**: First fixture/observer measurement, then PTY capture/echo logic in separate measured steps. Plan and boundary/rollback contract: [Rust migration](docs/plans/rust-migration.md).
  - **Output**: code
  - **Blocked by**: rust-process-primitives
  - **Acceptance**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B. Preserve this boundary's exact approved protocols, file effects, failure controls and owner scope; retain per-step evidence and independent review.
  - **Hypothesis**: Remove the legacy implementation for this boundary while preserving observable behavior and resource cost. Expected result: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Measurement**: Future harness gate, delivered before replacement: `heavy-run --exclusive cargo run --locked --release --manifest-path rust/Cargo.toml --bin migration-check -- compare --slice rust-pty-tools --samples 60`. Seal actual B and commit the numerical prediction before code. Existing affected tests and `heavy-run make check` remain guards.
  - **Success**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Pivot**: Any behavior/safety failure stops rollout; resource upper bound >1.10 changes architecture or slice boundary before retry. Missing or inconclusive evidence leaves the task open and the old implementation active.
  - **Anchor**: Basili, Caldiera, Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration); Forsgren, Humble, Kim 2018 (performance and stability).
  - **Competitive-goal**: none — native runtime independence; existing scorecard behavior is a guard and speed claims require separate evidence.

- [ ] Run remaining developer utilities through Rust
  - **ID**: rust-developer-utilities
  - **Tags**: migration, rust
  - **Mode**: AFK implementation — record any unavailable owner-only live proof as a linked blocked HITL child before claiming the slice; see the plan.
  - **Details**: Scaffolds, notes/timers, status, snapshots, cleanup, PR/review and remaining assigned commands. Plan and boundary/rollback contract: [Rust migration](docs/plans/rust-migration.md).
  - **Output**: code
  - **Blocked by**: rust-cli-core, rust-repository-discovery
  - **Acceptance**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B. Preserve this boundary's exact approved protocols, file effects, failure controls and owner scope; retain per-step evidence and independent review.
  - **Hypothesis**: Remove the legacy implementation for this boundary while preserving observable behavior and resource cost. Expected result: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Measurement**: Future harness gate, delivered before replacement: `heavy-run --exclusive cargo run --locked --release --manifest-path rust/Cargo.toml --bin migration-check -- compare --slice rust-developer-utilities --samples 60`. Seal actual B and commit the numerical prediction before code. Existing affected tests and `heavy-run make check` remain guards.
  - **Success**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Pivot**: Any behavior/safety failure stops rollout; resource upper bound >1.10 changes architecture or slice boundary before retry. Missing or inconclusive evidence leaves the task open and the old implementation active.
  - **Anchor**: Basili, Caldiera, Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration); Forsgren, Humble, Kim 2018 (performance and stability).
  - **Competitive-goal**: none — native runtime independence; existing scorecard behavior is a guard and speed claims require separate evidence.

- [ ] Prove and port the Python-host TLS adapter through Rust
  - **ID**: rust-python-host-extension
  - **Tags**: migration, rust
  - **Mode**: AFK implementation — record any unavailable owner-only live proof as a linked blocked HITL child before claiming the slice; see the plan.
  - **Details**: In-process TLS adapter feasibility, ABI/signing and opt-in policy; lib/python/dotfiles_tls_relax.py. Plan and boundary/rollback contract: [Rust migration](docs/plans/rust-migration.md).
  - **Output**: code
  - **Blocked by**: rust-native-delivery, rust-process-primitives
  - **Acceptance**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B. Preserve this boundary's exact approved protocols, file effects, failure controls and owner scope; retain per-step evidence and independent review. Prove host ABI/signing feasibility first; the external Python host may remain, but owned implementation is Rust. Preserve the existing opt-in and TLS validation boundary; unresolved non-Rust executable glue prevents completion.
  - **Hypothesis**: Remove the legacy implementation for this boundary while preserving observable behavior and resource cost. Expected result: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Measurement**: Future harness gate, delivered before replacement: `heavy-run --exclusive cargo run --locked --release --manifest-path rust/Cargo.toml --bin migration-check -- compare --slice rust-python-host-extension --samples 60`. Seal actual B and commit the numerical prediction before code. Existing affected tests and `heavy-run make check` remain guards.
  - **Success**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Pivot**: Any behavior/safety failure stops rollout; resource upper bound >1.10 changes architecture or slice boundary before retry. Missing or inconclusive evidence leaves the task open and the old implementation active.
  - **Anchor**: Basili, Caldiera, Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration); Forsgren, Humble, Kim 2018 (performance and stability).
  - **Competitive-goal**: none — native runtime independence; existing scorecard behavior is a guard and speed claims require separate evidence.

- [ ] Move owned non-UI tests and gate tools to Rust
  - **ID**: rust-test-build-tooling
  - **Tags**: migration, rust
  - **Mode**: AFK implementation — record any unavailable owner-only live proof as a linked blocked HITL child before claiming the slice; see the plan.
  - **Details**: Non-UI tests, fake services, coverage/build/gates, .github tooling; preserve independent negative controls. Plan and boundary/rollback contract: [Rust migration](docs/plans/rust-migration.md). Run alongside domain ports; retire an old oracle only after the new independent tests detect the same planted faults.
  - **Output**: code
  - **Blocked by**: rust-measurement-harness
  - **Acceptance**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B. Preserve this boundary's exact approved protocols, file effects, failure controls and owner scope; retain per-step evidence and independent review. Detect 100% of retained planted faults; remove no negative/failure case to achieve conversion.
  - **Hypothesis**: Remove the legacy implementation for this boundary while preserving observable behavior and resource cost. Expected result: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Measurement**: Future harness gate, delivered before replacement: `heavy-run --exclusive cargo run --locked --release --manifest-path rust/Cargo.toml --bin migration-check -- compare --slice rust-test-build-tooling --samples 60`. Seal actual B and commit the numerical prediction before code. Existing affected tests and `heavy-run make check` remain guards.
  - **Success**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Pivot**: Any behavior/safety failure stops rollout; resource upper bound >1.10 changes architecture or slice boundary before retry. Missing or inconclusive evidence leaves the task open and the old implementation active.
  - **Anchor**: Basili, Caldiera, Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration); Forsgren, Humble, Kim 2018 (performance and stability).
  - **Competitive-goal**: none — native runtime independence; existing scorecard behavior is a guard and speed claims require separate evidence.

- [ ] Prove complete conversion and retire superseded runtimes
  - **ID**: rust-final-audit
  - **Tags**: migration, rust
  - **Mode**: AFK implementation — record any unavailable owner-only live proof as a linked blocked HITL child before claiming the slice; see the plan.
  - **Details**: Residual/source/generated/install audit, runtime retirement and whole-tool evidence. Plan and boundary/rollback contract: [Rust migration](docs/plans/rust-migration.md).
  - **Output**: code
  - **Blocked by**: rust-source-inventory, rust-measurement-harness, rust-native-delivery, rust-process-primitives, rust-shared-queue, rust-repository-discovery, rust-cli-core, rust-doctor-core, rust-doctor-shell-editors, rust-doctor-security, rust-doctor-workflow, rust-doctor-browsers, rust-doctor-agents, rust-doctor-macos, rust-doctor-local-ai, rust-doctor-apps, rust-apply-install, rust-plugin-trust, rust-services-power, rust-git-security-guards, rust-browser-native, rust-local-ai-runtime, rust-metrics-checkup, rust-pty-tools, rust-developer-utilities, rust-python-host-extension, rust-test-build-tooling
  - **Acceptance**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B. Preserve this boundary's exact approved protocols, file effects, failure controls and owner scope; retain per-step evidence and independent review. Unexplained owned non-Rust non-UI/nonessential-shell components 0; temporary implementation adapters 0; narrow exception ledger complete. Frozen/unresolved residue prevents a full conversion claim.
  - **Hypothesis**: Remove the legacy implementation for this boundary while preserving observable behavior and resource cost. Expected result: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Measurement**: Future gate: `heavy-run --exclusive cargo run --locked --release --manifest-path rust/Cargo.toml --bin migration-check -- final-audit`; also `heavy-run make check` and the supported install/update/uninstall/rollback matrix. Compare each slice against its own sealed baseline; never substitute an aggregate benchmark.
  - **Success**: G: approved behavior parity 100%; unauthorized writes, disclosures, false permits and orphaned owned processes 0; native-only success for converted owned logic 100%; upper 95% paired-CI execution-p95 and peak-RSS ratios <=1.10 versus sealed B.
  - **Pivot**: Any behavior/safety failure stops rollout; resource upper bound >1.10 changes architecture or slice boundary before retry. Missing or inconclusive evidence leaves the task open and the old implementation active.
  - **Anchor**: Basili, Caldiera, Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration); Forsgren, Humble, Kim 2018 (performance and stability).
  - **Competitive-goal**: none — native runtime independence; existing scorecard behavior is a guard and speed claims require separate evidence.


## P3

- [ ] Harden the tooling-checkup dashboard chart checks (round-2 review of dotfiles #379)
  - **ID**: dashboard-chart-gate-hardening
  - **Tags**: ui, tooling-checkup
  - **Details**: Four leftovers from the round-2 review of the Hallmark dashboard redesign. (1) The load chart can show a duplicate or a missing local hour on a daylight-saving change, because the exporter keys rows by local time: key them by UTC and format in the page. (2) The gate's tap test uses a mouse click, not `touchscreen.tap`. (3) The gate presses ArrowLeft but never checks that the tooltip moved. (4) Chart line colours (non-text contrast, WCAG 1.4.11) are not gated.
  - **Files**: `skills/tooling-checkup/scripts/dashboard_export.py`, `skills/tooling-checkup/dashboard/index.html`, `skills/tooling-checkup/scripts/dashboard_comfort.cjs`, `tests/tooling-checkup-dashboard.bats`
  - **Output**: code
  - **Acceptance**: a fixture with a spring-forward and a fall-back week draws 168 distinct hours; the gate taps with `touchscreen.tap`, asserts the tooltip text changes after ArrowLeft, and fails on a chart line under 3:1 against the panel in light and dark.

- [ ] Tighten the perl alarm guard test
  - **ID**: perl-alarm-guard-gaps
  - **Tags**: tests, reliability
  - **Details**: Two gaps in `tests/perl-alarm.bats`, found in review of the SIGALRM fix. (1) The guard greps one line at a time, so a multi-line `perl -e '...'` that calls `alarm` without resetting the handler is not caught. (2) The guard skips all of `tests/morning.bats`, but only its perl stub lines need to be skipped.
  - **Files**: `tests/perl-alarm.bats`
  - **Output**: code
  - **Acceptance**: a fixture with a multi-line `perl -e` that arms `alarm` and has no reset makes the guard fail; the guard still passes on the repo; the skip covers only the stub lines of `tests/morning.bats`, so a bad `alarm` line elsewhere in that file fails the guard.
  - **Competitive-goal**: none — test hardening, not a scorecard metric.

- [ ] Make `make lint` fast in the inner loop
  - **ID**: speed-up-make-lint
  - **Blocked**: needs-time — 2026-10-22: shipped `make lint` per-file cache (`bin/cached-run --per-file`: skips a script that passed with the same content, sourced files, shellcheck version, and `.shellcheckrc`; shared by all worktrees; misses run in parallel) plus `make lint-full` (PR #257). Baseline 2026-10-22: `make lint` lines sum 6m02s/day (tooling 2m08s, dotfiles 2m04s, agentbrew 1m50s); one run 17-39 s uncached, now 11.6 s cold and 1.2-1.3 s warm at load 40-50. Measure on or after 2026-10-29 with `python3 ~/.claude/skills/tooling-checkup/scripts/agent_time_review.py --days 7` (sum of the `make lint` lines), then close or pivot.
  - **Tags**: perf, agents
  - **Details**: The 2026-10-21 checkup time review (7 days): `make lint` (shellcheck on every script in `SCRIPTS`) costs 3m51s/day across sessions started in dotfiles and agentbrew (14x in 4 sessions, p95 8m20s to 11m30s). agentbrew has no Makefile, so both lines are this target. Agents run the full shellcheck while they iterate.
  - **Files**: `Makefile`, `bin/cached-run`, `AGENTS.md`
  - **Output**: code
  - **Acceptance**: the `make lint` lines in the 7-day agent time review add up to less than the Success threshold.
  - **Hypothesis**: shellcheck on changed scripts only (or `bin/cached-run` per file) cuts `make lint` from 3m51s/day to under 1 min/day.
  - **Measurement**: `python3 ~/.claude/skills/tooling-checkup/scripts/agent_time_review.py --days 7` (sum of the `make lint` lines), 7 days after the change lands.
  - **Success**: under 1 min/day.
  - **Pivot**: still over 3 min/day after 7 days -> profile with `bin/dotfiles-metrics --table` gate rows and drop this approach.
  - **Anchor**: tooling-checkup agent time review 2026-10-21; Forsgren, Humble, Kim 2018 (lead time); perf-review skill known fixes.
  - **Competitive-goal**: none — agent gate speed (docs/metrics.md gate row), not a scorecard metric.

- [ ] Evaluate Gemma 4 26B (and E4B) as a replacement for qwen3-coder:30b in the local-AI stack
  - **ID**: bench-gemma4-vs-qwen3-coder-local-ai
  - **Blocked**: needs a quiet-machine window and about 47 GB of downloads (checked 2026-10-16). Ollama 0.40.5 is running, but neither candidate (`gemma4:26b` 18 GB, `gemma4:e4b` 9.6 GB) nor the baseline `qwen3-coder:30b` (about 18 GB) is on disk; `ollama list` shows only qwen3:14b, qwen3:0.6b, qwen3.6:27b, and two custom tags. Parallel agent sessions keep load1 at 20-80, which would distort tok/s numbers. Unblock: run the pulls and the bench on an idle machine (load1 under 5), and first confirm the baseline is still `qwen3-coder:30b` and not `qwen3.6:27b`.
  - **Tags**: local-ai, bench, model-evaluation, ollama, mlx
  - **Details**: Gemma 4 shipped April 2026 (Apache 2.0, 256K context,
    multimodal, MoE A4B variant). The
    `docs/local-ai-roadmap.md` already flags two upstream Ollama
    advantages that Gemma 4 has and qwen3-coder doesn't: native MLX
    paths in Ollama 0.21 (only Gemma 4 today) and multi-token-prediction
    speculative decoding (PR #15980, May 2026 — ~33% tok/s win on the
    variants that ship MTP). The candidate is `gemma4:26b` (18 GB on
    disk, 4B active out of 26B MoE — analog to qwen3-coder:30b's 3.3B
    active out of 30B). Secondary candidate `gemma4:e4b` (9.6 GB) could
    replace `qwen3:8b` in the title/quick-loop slot.

    Follow the same MAPE-K hypothesis-test discipline used for
    qwen3-coder originally (`docs/audits/local-ai-task-runs-2026-05-11.md`):

    1. `ollama pull gemma4:26b gemma4:e4b`.
    2. `bin/local-ai-bench --model gemma4:26b` and same for the qwen3-coder
       baseline. Compare cold/warm/tok-s/prompt-eval-ms on identical prompts.
    3. End-to-end agentic test: `DOTFILES_OLLAMA_PRIMARY=gemma4:26b
       bin/local-ai-agent "<real TASKS.md task>"`. Record turn count,
       wall time, tool-call format errors, CLI-flag hallucinations
       (per `docs/audits/local-ai-failure-modes.md`).
    4. Append a new "Task N — bench-gemma4-vs-qwen3-coder" entry to
       `docs/audits/local-ai-task-runs-2026-05-11.md` (or a new dated
       audit file if the existing one is too long) with: pre-registered
       hypothesis, pivot threshold, predicted vs observed numbers,
       match yes/no/partial, lesson.
    5. **Decision rule**: swap if Gemma 4 wins on tok/s AND matches/beats
       qwen3-coder on agentic quality (turn count + output correctness).
       Otherwise keep qwen3-coder and file a follow-up task to re-evaluate
       when Ollama lands MTP speculative decoding for non-Gemma models.

    Known migration cost if the bench says swap:
    `bin/local-ai-warmup` (model registry + size buckets), `home/zshrc.ai-tools`
    (MLX server stanza), `launchagents/com.dotfiles.ollama.plist.tmpl`
    (context length + KV-cache notes), `lib/local-ai-agent.py` (system
    prompt tuned to qwen3 tool format), and the opencode bootstrap path
    in `agentbrew/src/mcp/opencode-bootstrap.ts`. The audit-driven entry
    must list every file that needs edits before the swap commit lands.

    Specifically NOT in scope here: pulling `gemma4:31b-coding-mtp-bf16`
    (64 GB on disk — would not coexist with opencode + OS on a 64 GB M3
    Max). If quantized variants of that tag appear later, file a separate
    bench task.
  - **Files**: `docs/audits/local-ai-task-runs-2026-05-11.md` (new audit
    entry), no code edits unless the decision rule fires.
  - **Acceptance**: New "Task N" audit entry in MAPE-K format with
    pre-registered hypothesis + observed numbers + decision (swap or
    keep). If decision = swap, link a follow-up implementation task
    listing the files above and the rollback plan (revert via
    `DOTFILES_OLLAMA_PRIMARY=qwen3-coder:30b` env var without code
    revert).
  - **Competitive-goal**: none — local-AI story US09 (docs/metrics.md local-AI row), not a scorecard metric.
  - **Hypothesis**: `gemma4:26b` reaches at least 1.2× the warm tok/s of `qwen3-coder:30b` with equal or fewer agent turns on the same task.
  - **Measurement**: `bin/local-ai-bench --model gemma4:26b` vs `bin/local-ai-bench --model qwen3-coder:30b` on an idle machine (load1 under 5), plus one `bin/local-ai-agent` run each.
  - **Success**: tok/s ratio ≥ 1.2 and turns ≤ baseline: swap.
  - **Pivot**: tok/s ratio < 1.05 or more turns: keep qwen3-coder and re-check when Ollama ships MTP for other models.
  - **Anchor**: `docs/audits/local-ai-task-runs-2026-05-11.md` MAPE-K method; Ollama PR #15980 (MTP).
  - **Surfaced-by**: 2026-05-15 session — Gemma 4 release (April 2026)
    plus existing roadmap entries flagging MLX + spec-decoding advantages
    that haven't been benched yet on this stack.

- [ ] Investigate Ollama upstream qwen3-coder XML-parser fix (PRs #14906 / #14915)
  - **ID**: track-ollama-qwen3coder-parser-fix
  - **Tags**: local-ai, upstream, ollama
  - **Blocked**: needs-external-action — upstream fix has NOT shipped: PR ollama/ollama#14906 closed UNMERGED, successor #14915 still open, issue #14834 still open (checked 2026-06-12 and again 2026-10-16 via api.github.com; local Ollama is 0.40.5). Unblock when #14915 (or equivalent) merges into a tagged Ollama release; then simplify the retry ladder per Acceptance.
  - **Research**: 2026-06-12 — upstream status check
    `curl -sf https://api.github.com/repos/ollama/ollama/pulls/14906` → state=closed, merged=false.
    `.../pulls/14915` → state=open. `.../issues/14834` → state=open.
    Watch-list entries + an anonymous-API fallback snippet added to docs/local-ai-roadmap.md
    (this host has no github.com gh auth; the API check needs no token).
    Re-check command: `curl -sf https://api.github.com/repos/ollama/ollama/pulls/14915 | jq '{state, merged, merged_at}'`.
  - **Last-enriched**: 2026-10-16
  - **Details**: The 3-stage retry ladder in lib/local-ai-agent.py
    is a workaround for ollama/ollama#14834 — the qwen3-coder XML
    tool-call parser crashes with HTTP 500 on certain model
    outputs. Upstream PRs #14906 and #14915 propose to treat
    unparseable tool calls as content instead of aborting. Once
    one of those lands in a tagged Ollama release, simplify our
    retry ladder (we can drop the temperature wiggle once
    deterministic temp=0 retries no longer crash). Also update
    `docs/audits/local-ai-failure-modes.md` to mention which
    Ollama version fixes it.
  - **Files**: lib/local-ai-agent.py,
    docs/audits/local-ai-failure-modes.md
  - **Acceptance**: When the fix ships in Ollama, our retry
    ladder is simplified (1 retry, no temperature wiggle) and a
    new failure-mode entry records the Ollama version threshold.
  - **Hypothesis**: Removing the temperature retry ladder after Ollama fixes qwen3-coder parsing will simplify local-ai runs without increasing crashes.
  - **Success**: On a fixed Ollama release, local-ai-agent succeeds with one retry and no temperature wiggle on the known failure prompt.
  - **Pivot**: If upstream fix does not cover our crash shape, keep the ladder and update the failure-mode doc with version evidence.
  - **Measurement**: `lib/local-ai-agent.py` retry tests pass and a recorded Ollama version threshold is added to docs.
  - **Anchor**: ollama/ollama#14834 and PRs #14906/#14915; docs/user-stories/09-run-local-models-fast.md.

- [ ] Cross-repo local-AI loop (currently dotfiles-only)
  - **ID**: local-ai-loop-cross-repo
  - **Blocked**: needs the loop's default model `qwen3-coder:30b` (about 18 GB), which is not on disk (checked 2026-10-16), to prove a real run in a second repo. The config extraction itself can be tested with a stub agent, as `tests/local-ai-loop-branching.bats` does. Unblock: local AI back in use with the default model pulled.
  - **Tags**: local-ai, cross-repo, refactor
  - **Details**: `bin/local-ai-loop` hardcodes assumptions that
    only hold in `dotfiles/`: `make check` exists, `bats tests/`
    works, `git-hooks/` is the hook dir, the failure-modes file
    lives at `docs/audits/local-ai-failure-modes.md`. Extract the
    repo-specific bits into a `.local-ai-loop.json` config file
    per repo (verify_cmd, test_cmd, hook_dir, failure_modes_path,
    safe_prefixes). Move the standalone driver to
    `~/apps/tooling/agentbrew/skill-plugins/workflow/local-ai-loop/` so other
    repos can opt-in via `agentbrew sync`. Validate on
    `agentbrew` and `tasks.md`.
  - **Files**: bin/local-ai-loop, lib/local-ai-loop.py,
    .local-ai-loop.json (new), ~/apps/tooling/agentbrew/skill-plugins/workflow/
  - **Acceptance**: `local-ai-loop` runs successfully from at
    least 2 different repos (dotfiles + one other), each with its
    own `.local-ai-loop.json`. Original dotfiles flow still works.
  - **Hypothesis**: Extracting repo-specific local-ai-loop config lets the runner work beyond dotfiles without hardcoded make/bats assumptions.
  - **Success**: The loop completes a task in dotfiles and one other repo using per-repo `.local-ai-loop.json` configs.
  - **Pivot**: If cross-repo differences are too large, keep dotfiles as the only supported repo and document required adapter hooks.
  - **Measurement**: `local-ai-loop` fixture tests cover two config files and both runs reach verification.
  - **Anchor**: docs/local-ai-roadmap.md; docs/user-stories/09-run-local-models-fast.md.

- [ ] Stretch the loop to genuine feature work (patch_file in anger)
  - **ID**: local-ai-loop-feature-work-dogfood
  - **Blocked**: needs a real model run; the loop's default `qwen3-coder:30b` (about 18 GB) is not on disk (checked 2026-10-16). Unblock: local AI back in use with the default model pulled.
  - **Tags**: local-ai, dogfood, patch_file
  - **Details**: Earlier loop runs only produced new static test files. The harder case is editing an existing file with `patch_file`. Pick one open dotfiles task that edits a large existing file (for example `module-resilience-bats-missing-lib` or `launchagent-path-fix-stub-plist-message`), run the loop on it, and record where `patch_file` breaks.
  - **Files**: the chosen task's files, docs/audits/local-ai-failure-modes.md
  - **Acceptance**: At least one task that modifies an existing
    file > 100 lines via `patch_file` completes end-to-end. New
    failure modes captured in
    `docs/audits/local-ai-failure-modes.md`.
  - **Hypothesis**: Forcing local-ai-loop to patch an existing >100-line file will reveal real edit-path failures hidden by static test tasks.
  - **Success**: At least one existing-file modification task completes end-to-end with correct tests and failure-mode notes updated.
  - **Pivot**: If patch_file remains unreliable, add a smaller patching harness before using the loop on feature work.
  - **Measurement**: The chosen task edits a large existing file, passes `make check`, and its failures are recorded in docs/audits/local-ai-failure-modes.md.
  - **Anchor**: docs/audits/local-ai-failure-modes.md; docs/user-stories/09-run-local-models-fast.md.

- [ ] Run the local-AI loop for 8 hours from a task queue and log the success rate
  - **ID**: local-ai-loop-overnight-grind
  - **Blocked**: an 8-hour measured run, over the 60-minute agent limit, and the default model `qwen3-coder:30b` (about 18 GB) is not on disk (checked 2026-10-16). Per-task branches shipped (#115); the run is the only remaining step.
  - **Tags**: local-ai, automation, overnight
  - **Details**: The queue reader (`read_queue_dir`, `lib/local-ai-loop.py`), the run CSV, and the reviewer gate already shipped. What remains is the measured long run. Per-task branches (`overnight-grind-branch-per-task`) shipped on 2026-10-16. The loop never pushes, so each task ends as a local branch or a rollback note, not a PR. The loop last ran on 2026-05-11 and no inference engine is reachable today, so this waits until local AI is back in use.
  - **Files**: bin/local-ai-loop, lib/local-ai-loop.py, docs/local-ai-roadmap.md
  - **Acceptance**: `./bin/local-ai-loop --queue tasks-queue/` runs for 8 hours and writes one CSV row per task with status, wall time, and regression outcome.
  - **Hypothesis**: Running queued local-AI tasks for hours exposes success-rate and rollback failure modes that one-task tests hide.
  - **Success**: An 8-hour run completes at least 80% of seeded tasks or records a rollback note for each failure.
  - **Pivot**: If the success rate is below 80%, pause feature work and fix the top recurring failure in the run CSV.
  - **Measurement**: `docs/audits/local-ai-runs.csv` rows for the run.
  - **Anchor**: docs/local-ai-roadmap.md; docs/user-stories/09-run-local-models-fast.md.

- [ ] Replace or relocate the Codex readiness wrapper when upstream covers it
  - **ID**: replace-relocate-codex-readiness
  - **Tags**: codex, reuse
  - **Details**: `dotfiles-install-codex` wraps npm installation and a user-bin link; `modules/codex` checks machine readiness. Compare the existing `codex doctor --json` checks with the local-bin link, GUI host, and stale configured CLI path checks. Delegate matching checks upstream; retain only the machine-specific gaps. Recheck when upstream changes its doctor or installer.
  - **Files**: `bin/dotfiles-install-codex`, `modules/codex/doctor.sh`
  - **Output**: decision
  - **Acceptance**: a current upstream probe records which checks can be delegated; delete wrappers only when the regression tests pass against the replacement.
  - **Competitive-goal**: none — upstream delegation for machine readiness, not a scorecard metric.
