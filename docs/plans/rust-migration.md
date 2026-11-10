# Measured Rust migration plan

**Status (2026-11-10): porting stays paused until the owner starts it.**
This plan was rewritten on 2026-11-10 after the
[validation review](#validation-review-2026-11-09). No code is ported yet.
The re-plan Pivot did not apply: all seven MUST findings are resolved and
gate G stays. The measured hot paths (agent hooks and `app-priority`) now
come first.

## Overall goal and vision

Make the things users wait for faster, and prove it with numbers. Move
dotfiles-owned executable logic to Rust only where a slice names a
user-benefit metric. Keep UI code and necessary shell scripts in their
current languages, as requested on 2026-11-01. Preserve self-healing,
one-command setup, privacy and agentbrew's ownership of generated agent
configuration (VISION.md G1–G4; US01/03/05/06/08).

A slice with no measured user benefit is a
[recorded exception](#recorded-exceptions). It reopens when field numbers
and a profile show a gain. Runtime independence alone is not a reason to
port. Current queue and correctness fixes continue on their own.

## Decision and alternatives

Replace one owned implementation per PR behind its existing command or
protocol. Start with the code that runs most often. Weigh a cheaper fix
first in every slice. Port to Rust only when the cheaper fix misses the
pre-registered number.

A single rewrite prevents attribution and risks losing failure cases.
Porting every slice in dependency order put the hot paths late. Both are
rejected. Permanent dual implementations double maintenance; a temporary
bridge needs a deletion condition and a tested rollback.

Two existing tools measure each slice:

- **Performance gate:** `make perf-gate` times the rows of
  `config/perf-budget.tsv` against the merge-base in the same run
  ([details](../observability.md#performance-gate)).
- **Local logs and field telemetry:** each `dotfiles` command and each
  automation run writes one content-free line with `duration_ms`. Telemetry
  sends it with `runtime` (`shell` now, `rust` after a port)
  ([details](../observability.md#telemetry)). The dashboard shows p50 and
  p95 per command and runtime.

## Evidence and current state

Reviewed at revision `788d43d` on 2026-11-10.

| Claim | Current source of truth / delivery | Status |
|---|---|---|
| The task backend is TASKS.md; make check is the local gate | Agentfile.yaml, AGENTS.md, Makefile | fact |
| Production code has no Rust; no `rust/Cargo.toml` and no `migration-check` binary exist | Tracked source | fact |
| Rust exists only as test fixture crates | `tests/fixtures/` (`checkup-read-consumer`, `compiler-queue-observer`, `connector-credentials`, `queue-privacy-cutover`) | fact |
| Two agent hooks run on each agent Bash call and start Perl, `shfmt` or `jq` | agent-hooks/require-heavy-run.sh, agent-hooks/block-dangerous-git.sh | fact |
| The performance gate tracks both hooks and three commands | config/perf-budget.tsv | fact |
| `app-priority` runs every 60 seconds and logs each run | launchagents/com.dotfiles.app-priority.plist.tmpl; `log_run app-priority` | fact |
| Commands and runs log `duration_ms`; telemetry adds `runtime` | lib/stats.sh; bin/dotfiles-telemetry | fact |
| Shell embeds Perl/Python/Node; some programs lack an extension | bin/heavy-run, bin/agent-tab, bin/learn-repos-inventory, lib/ | fact |
| Source collection covers several families | [source inventory](rust-source-inventory.md) | fact |
| Where doctor, apply and sync time goes | Step 3 below | unmeasured |

**Existing Rust code is grandfathered.** The fixture crates shipped before
gate G existed. They are test fixtures, not ports. They stay with their
tests and do not count as migrated slices. A later change that makes Rust
replace a production path must pass G.

Read live source again when claiming a task. Newly merged behavior and newly
discovered code enter the inventory; this dated snapshot is not a scope limit.

## Scope and exceptions

In scope: owned code on a measured hot path. Today that is the two agent
hooks and `app-priority`.

Out of scope until reopened: every slice in
[Recorded exceptions](#recorded-exceptions).

Never in scope:

- UI presentation and rendering assets. Exporters and CDP policy are backend
  work, not UI.
- Shell that must stay shell: sourced environment, shell functions and
  completions, first bootstrap before a binary exists, or a tiny
  external-protocol entrypoint. Move its business logic out when its slice
  is ported.
- Declarative YAML/JSON/plists, prompts, docs, data fixtures and lockfiles.
- Upstream chezmoi, Homebrew, Git, browser engines, Ollama and the memory
  service.
- Frozen agent support. It stays as it is. The manifest marks it `frozen`.
  It needs no port and no task.

## Boundary contracts and state lifetimes

Before replacement, record argv/stdin, stdout/stderr, exit codes, schemas, file
bytes/modes/symlinks, write ownership, confirmations, deadlines, cancellation,
process groups and external calls. Existing observable behavior is the oracle;
a separately approved bug fix is not silently folded into a language port.

Scheduler leases have machine-user/workload scope; settings have per-host/profile
scope; fixture homes, caches and process groups have per-run scope. Each owner
documents creation, refresh, crash cleanup and deletion. Agentbrew remains the
writer of generated agent config and semantic-memory lifecycle. Preserve privacy
opt-ins and deduplication. Do not import, clone or sync conversation histories.

Raw outputs stay private. Commit only content-free workload IDs, hashes,
numeric results, validity fields and decisions. Never keep credentials, raw
transcripts, private paths, memory payloads or customer data in fixtures or
public receipts.

### Cross-repo rule

This is the one rule for both repositories. The agentbrew plan holds the
same text.

- Hot-path slices and source collection in dotfiles do not wait for
  agentbrew. They use the dotfiles performance gate and local logs.
- A dotfiles step that runs `migration-check` waits until the agentbrew task
  `rust-source-inventory` merges. No other dotfiles step waits.
- Dotfiles pins the shared crate as a git dependency with an exact `rev`.
  It commits `Cargo.lock` and a `cargo vendor` copy, with a
  `.cargo/config.toml` source replacement. `cargo build --locked --offline`
  then works with no network and no sibling checkout.
- The vendored copy is a pinned snapshot of agentbrew's crate. Dotfiles
  never edits it and never writes a second engine.

## Measurement contract

### Commands that run today

```sh
scripts/perf-gate.sh --force --json
jq -s '[.[] | select(.task == "app-priority") | .duration_ms] | add / length' ~/.dotfiles-stats.jsonl
jq -s '[.[] | select(.command == "doctor") | .duration_ms] | sort | .[length / 2 | floor]' ~/.local/state/dotfiles/commands.jsonl
bin/bats-affected origin/feat/chezmoi | xargs bats
```

The first prints `base_min`, `head_min`, `ratio` and `verdict` per tracked
row. The second prints the mean `app-priority` run time in ms. The third
prints the local p50 of one command; the dashboard shows the same number per
`runtime` for all installs. The fourth runs the affected Bats tests, which
are the behavior oracle.

### Commands that run after the agentbrew inventory step merges

`rust/Cargo.toml` and `migration-check` do not exist yet. These commands are
**runnable after the agentbrew task `rust-source-inventory` merges** and the
dotfiles adapter pins it. Until then no task may cite one as its measurement.

```sh
heavy-run cargo build --locked --offline --release --manifest-path rust/Cargo.toml --bin migration-check
heavy-run rust/target/release/migration-check inventory --check
heavy-run --exclusive rust/target/release/migration-check compare --slice <task ID> --pairs 30
```

Build with plain `heavy-run` first. Time only the built binary under
`heavy-run --exclusive`. Compile time never counts as workload time. The
`compare` command exists only when a reopened slice needs the differential
runner (see [Deferred preparation steps](#deferred-preparation-steps)).

### Rules

- Register workloads, fixtures and thresholds before production changes.
- Measure unchanged source first. Keep every sample and every failure.
  Missing or contaminated data is inconclusive. It is never zero or passing.
- Commit the baseline number and the numeric prediction before the
  replacement code.
- Queue wait, workload execution, external tools, build, install, cold
  startup and warm work are distinct measurements.
- Never cancel other sessions or bypass admission to get a number. Never
  test by changing the live admission directory.
- Publish negative results too. An independent reviewer checks each
  keep/pivot decision.

### Statistic and noise floor

The plan no longer uses a confidence bound on a p95 ratio. Sixty pairs give
about three tail samples, and measured noise on this Mac was 19-50%.

- **Time, for a row in the budget file:** the performance gate decides. It
  compares the fastest of 15 runs per tree and times a slower-looking row
  again, up to two more rounds. Each hot-path task first proves 20 A/A runs
  (base and head at the same commit) with 0 failures.
- **Time, for a logged run:** compare the 7-day mean or p50 of `duration_ms`
  before and after, from the `jq` commands above. Need at least 1,000 runs
  on each side.
- **Time and memory, for other workloads:** R_T is the median of the paired
  ratios candidate time / baseline time. R_M is the same for peak RSS. Use at
  least 30 order-balanced pairs. Take a percentile bootstrap of the median
  with 10,000 resamples and a committed seed. Use its upper 95% bound.
- **Noise floor first:** run the same comparison with the baseline on both
  sides (an A/A run). Its upper bound must be at most 1.05. If it is higher,
  the result is inconclusive. Fix the run conditions; never the thresholds.
- **Memory without the runner:** take peak RSS from `/usr/bin/time -l` over
  15 pairs and compare the medians.
- **p95** is a field number. Read it from the dashboard, where the sample
  count is large. It is not a merge gate.

### Gate G

**Common gate G** for every port slice:

- Approved contract parity is 100%.
- Unauthorized writes, credential disclosures, false permits and orphaned
  owned processes are 0.
- The converted logic passes 100% with its former implementation absent.
- R_T and R_M are each at most **1.10** by the statistic above.
- The slice meets its own user-benefit number.
- The build budget holds: a cold `cargo build --locked --release` of the
  slice's crate takes at most 120 s and a warm build at most 15 s under
  `heavy-run`. `make check` builds Rust only when `rust/` changed.

**Named exemptions.** Three preparation steps still call the old runtime by
design: `rust-source-inventory`, the measurement runner and native delivery.
The clause "with its former implementation absent" does not apply to them.
Every other clause does.

**Pivot:** any safety or contract failure stops rollout. A resource bound
above 1.10 changes the architecture or slice boundary before a retry. A
missed user-benefit number ends the slice; it does not lower the number.
Inconclusive results keep the old implementation active and the task open.
Never adjust thresholds after results.

## Numbered work breakdown

The linked TASKS.md blocks are the execution queue. Work in isolated
fixtures and already-authorized interfaces is AFK. One implementation PR
changes one behavior boundary. Tests move with their slice: a port keeps
the old Bats tests until the new ones catch the same planted faults. There
is no separate "move tests to Rust" step.

| Step / task ID | Why and change | User-benefit metric, number and command | Depends on |
|---|---|---|---|
| 1. `rust-agent-hooks` | Two hooks run on each agent Bash call and start Perl, `shfmt` or `jq`. Remove those starts. Weigh a shell fast path first. | `hook-require-heavy-run` and `hook-block-dangerous-git` `ratio` at most 0.50 each, from `scripts/perf-gate.sh --force --json`. | none |
| 2. `rust-app-priority` | `app-priority` ran 17,488 times at 1.3 s mean. Weigh one `ps` pass first. | 7-day mean `duration_ms` at most 400, from the `app-priority` `jq` command above. | none; parallel with 1 |
| 3. `rust-cold-path-profile` | Doctor, apply, sync and the queue were never profiled. Measure where their time goes before any port. | Recorded exception: measurement only. Output is the share of wall time in owned code per command, next to its local p50. | none; parallel with 1-2 |
| 4. `rust-source-inventory` | Keep scope honest with a manifest and a thin pinned adapter to agentbrew's small validator. No full harness. | Recorded exception: preparation. Done when `migration-check inventory --check` rejects every planted omission. | Source collection: none. The check: agentbrew `rust-source-inventory`. |
| 5. `rust-final-audit` | Prove that every owned executable is ported, a recorded exception or frozen. | Recorded exception: audit. Done when unrecorded components are 0 and every ported slice still meets its number. | 1, 2, 3, 4 |

Each hot-path task commits its absolute baseline number before any
replacement code. The ratio or mean above is the decision rule.

Existing runnable guards: `heavy-run make check`; installation paths also
use `heavy-run make e2e`. Do not describe a future command as having passed.

### Deferred preparation steps

These steps have no task now. Open one when a recorded exception reopens
and needs it.

- **Measurement runner:** a thin pinned adapter to agentbrew's
  `migration-check compare`, for workloads that have no budget row and no
  logged run. It applies the statistic above.
- **Native delivery:** locked build, artifact integrity, atomic dispatch and
  rollback for a Rust binary on supported Mac targets. The first port that
  ships a binary opens this step.

### Recorded exceptions

A recorded exception has no user-benefit metric today. It stays in its
current language. It reopens only when both conditions hold: the field
dashboard or `rust-cold-path-profile` shows a user-visible cost, and a
profile puts at least half of that cost in owned code. A reopened slice
gets a task with its own number first. The task blocks that this re-plan
removed remain in git history at `788d43d`. The
[source ledger](rust-source-inventory-evidence.json) keeps the old slice
names as classification labels; this table gives each label its state.

| Slice (old task suffix) | Reason | Cheaper option to weigh first |
|---|---|---|
| process-primitives | No measured cost of its own. | None needed. |
| shared-queue | The wrapped command dominates queue time. Current queue fixes ship first. `app-priority` moved to step 2. | The `heavy-run-status` budget row guards it. |
| repository-discovery | Rare, agent-driven tools. | None needed. |
| cli-core | `dotfiles --version` takes about 64 ms. Startup is not the hot path. | The `dotfiles-version` and `dotfiles-config` budget rows guard it. |
| doctor-core and the doctor module groups (shell-editors, security, workflow, browsers, agents, macos, local-ai, apps) | Doctor probes are cold paths that wait on child tools. Not profiled. | Parallel or cached probes; profile first (step 3). |
| apply-install | Dominated by chezmoi, Homebrew and installers. | Profile first (step 3). |
| plugin-trust | Rare actions; trust rules gain nothing from a port. | None needed. |
| services-power | Launchd jobs wait on system tools. `app-priority` moved to step 2. | Profile first (step 3). |
| git-security-guards | The two agent hooks moved to step 1. Git hooks run once per commit or push. | A budget row per git hook before any port. |
| browser-native | Time is in the browser and in macOS events. | None needed. |
| local-ai-runtime | Time is in the model. | None needed. |
| metrics-checkup | Runs every few days. | None needed. |
| pty-tools | No measured cost. | None needed. |
| developer-utilities | Rare commands. | None needed. |
| python-host-extension | A Rust in-process TLS adapter is unproven, and it has no speed goal. Never weaken TLS validation to port it. | None. |
| test-build-tooling | Tests move with their slice. The Bats `test` step is 74% of gate time. | `bats --jobs`; tasks `speed-up-make-check` and `make-check-one-job-bats`. |
| Frozen agent support | Policy: keep it, never change it. | None. |

## Rollout, security and regression coverage

Each port PR carries the baseline commit, the prediction, the result and a
rollback proof. Isolate worktrees, fixture homes and outputs. Heavy work
uses the shared admission queue and bounded inner workers; timings use
`--exclusive`.

Keep the original negative cases. Switch dispatch atomically. Roll back only
the owned binary, dispatch and state; keep user edits and unknown keys.
Delete a temporary bridge only with recorded proof.

Retain required Bash 3.2 and UI checks. Separate fake CDP/service results from
authorized throwaway-app proof. Physical lid/power, signed endpoint and real
credential paths need their own evidence; unavailable proof remains a blocker.
Never use owner tabs, real drafts, elevated changes or public posts as fixtures.

After a switch, the local log or the dashboard must show the gain for
`runtime` `rust` within 14 days, or the slice rolls back.

**Final audit rule.** The audit passes when every owned executable
component in the manifest has one of three states: `ported` with receipts,
`exception` with a row in the table above, or `frozen`. Unrecorded
components must be 0. The audit claims "all measured hot paths ported". It
never claims "all code is Rust". A language percentage or a lower line
count is coverage, not a user benefit.

## Decisions (2026-11-10)

The owner chose to fix the plan and to ship it without another question
round. The choices below were **adopted by default on the reviewer's
recommendation**. The owner did not decide them one by one. **The owner can
reverse any of them.**

| Choice | Adopted default |
|---|---|
| Order | The per-call hook slice comes first, with a pre-registered cut per agent Bash call. It needs no native delivery task and no full harness. |
| Cold paths | Doctor probes, sync orchestration and the other slices in the table above are recorded exceptions. |
| Test tasks | The separate "move tests to Rust" task is gone. Tests move with their slice. |
| Inventory | The inventory step is a manifest and a thin adapter to a small validator. |
| Cheaper options | Each slice weighs a cheaper fix first: one `ps` pass for `app-priority`, parallel or cached doctor probes, `bats --jobs` for the gate. |
| Existing Rust code | Fixture crates are grandfathered. Rust passes G only when it replaces a production path. The review asked for a statement; this is the default. |
| Final audit and frozen support | Frozen support and recorded exceptions are named audit states. The review said this needs an owner decision; this default makes the audit passable until the owner rules. |

## Validation review (2026-11-09)

An independent reviewer checked the earlier plan against measured timings on
2026-11-09. Verdict: **re-plan before any port**. No task in either
repository was done. The owner paused porting the same day and asked for
field metrics and a speed gate first. Both now exist
([Telemetry](../observability.md#telemetry),
[performance gate](../observability.md#performance-gate)).

Measured on one loaded Mac; treat the numbers as a ranking, not a benchmark:

- Direct CLI use is rare for agents (6 runs in 9 days). `agentbrew --version`
  takes about 145 ms against a 34 ms Node floor; `dotfiles --version` takes
  about 64 ms. Startup is not the hot path.
- Hook helpers are the hot path. About 28,000 agent Bash calls in 9 days each
  fired about 8 hooks of 125-483 ms; `bash -c true` takes about 7 ms.
- In dotfiles, `app-priority` ran 17,488 times (1.3 s mean), and the Bats
  `test` step is 74% of gate time.
- Sync, git maintenance, upgrade, catalog, MCP lifecycle and doctor probes
  are likely dominated by git, network and child tools. They were not
  profiled; a port there needs a profile first.
- Rust compiles are already the largest agent Bash cost in other
  repositories. Gate G now carries a build budget.

### Findings to fix

None open. The seven MUST findings are resolved below.

### Resolved findings (2026-11-10)

| Finding | What changed | Where |
|---|---|---|
| Stale evidence | The evidence table reviews revision `788d43d`. Rust exists only as fixture crates. They are grandfathered; Rust passes G only when it replaces a production path. | [Evidence and current state](#evidence-and-current-state) |
| Commands cannot run | Commands are split into "run today" and "run after the agentbrew inventory step merges". Build uses plain `heavy-run`; only the built binary is timed under `--exclusive`. | [Measurement contract](#measurement-contract) |
| Gate G contradicts the preparation steps | G exempts the inventory, the measurement runner and native delivery by name from the "former implementation absent" clause. | [Gate G](#gate-g) |
| The statistic is not usable | The p95 confidence bound is gone. The performance gate decides tracked rows after 20 clean A/A runs. Logged runs compare 7-day numbers. Other workloads use a bootstrap of the median paired ratio after an A/A noise floor of at most 1.05. | [Statistic and noise floor](#statistic-and-noise-floor) |
| The final audit cannot pass | The audit accepts three named states: `ported`, `exception` and `frozen`. It needs 0 unrecorded components. Adopted by default; the owner can reverse it. | [Rollout](#rollout-security-and-regression-coverage), [Decisions](#decisions-2026-11-10) |
| One cross-repo rule | One rule, the same text in both plans: who waits for what, and git `rev` pin plus `cargo vendor` for offline `--locked` builds. | [Cross-repo rule](#cross-repo-rule) |
| No user benefit metric | Every step names a metric, a number and a command, or is a recorded exception with its reason. | [Numbered work breakdown](#numbered-work-breakdown), [Recorded exceptions](#recorded-exceptions) |

## References

Metric anchors: Basili, Caldiera, Rombach (1994), Goal-Question-Metric; Munafò et
al. (2017), pre-registration; Kohavi, Tang, Xu (2020), A/A checks and guard
metrics; Efron and Tibshirani (1993), bootstrap intervals; Forsgren, Humble,
Kim (2018), performance/stability outcomes.

Implementation references: [Cargo build](https://doc.rust-lang.org/cargo/commands/cargo-build.html),
[cargo vendor](https://doc.rust-lang.org/cargo/commands/cargo-vendor.html), and
[PyO3 building/distribution](https://pyo3.rs/main/building-and-distribution).
PyO3 is a reuse candidate for the Python host extension if that exception
reopens. It needs an ABI and signing proof first.
