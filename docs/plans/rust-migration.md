# Measured Rust migration plan

**Status (2026-11-11): the owner started execution; measurement is in progress.**
This plan was rewritten on 2026-11-10 after the
[validation review](#validation-review-2026-11-09). No code is ported yet.
The re-plan Pivot did not apply: gate G stays. A first independent review of
this rewrite found five of the seven MUST findings only partly resolved. This
revision applies its fixes. A second independent review on 2026-11-10 graded all
seven findings resolved in both plans. The
owner confirmed all seven defaults on 2026-11-12; see
[Decisions](#decisions-2026-11-10). The agentbrew plan still needs the same
ruling recorded after this migration. The measured hot paths
(agent hooks and `app-priority`) now come first.

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
  ([details](../observability.md#telemetry)). The owner's dashboard
  ("Tooling performance: agentbrew + dotfiles", private since 2026-11-10)
  shows p50 and p95 of `duration_ms` by command, version and runtime. It
  is in the owner's PostHog project and needs a login. It cannot be
  verified from the repository. A public link is to be added. The local
  logs are the fallback.

## Evidence and current state

Reviewed at revision `788d43d` on 2026-11-10.

| Claim | Current source of truth / delivery | Status |
|---|---|---|
| The task backend is TASKS.md; make check is the local gate | Agentfile.yaml, AGENTS.md, Makefile | fact |
| Production code has no Rust; no `rust/Cargo.toml` and no `migration-check` binary exist | Tracked source | fact |
| The Makefile has no cargo step | Makefile | fact |
| Rust exists only as test fixture crates | `tests/fixtures/` (`checkup-read-consumer`, `compiler-queue-observer`, `connector-credentials`, `queue-privacy-cutover`) | fact |
| Two agent hooks run on each agent Bash call and start Perl, `shfmt` or `jq` | agent-hooks/require-heavy-run.sh, agent-hooks/block-dangerous-git.sh | fact |
| The performance gate tracks both hooks and three commands; it checks minimums and paired median differences | config/perf-budget.tsv, scripts/perf-gate.pl; #573 | fact |
| `app-priority` runs every 60 seconds; valid new timing records use monotonic milliseconds | launchagents/com.dotfiles.app-priority.plist.tmpl; [timing deployment](app-priority-timing.md) | fact |
| `app-priority` mean run time: 1,560 ms over 9,674 runs in the last 7 days; 990 ms over 8,654 runs in the 7 days before; 926 ms over all logged runs | The earlier whole-second window command, run on 2026-11-10 | measured, not a millisecond baseline |
| Commands and runs log `duration_ms`; telemetry adds `runtime` | lib/stats.sh; bin/dotfiles-telemetry | fact |
| Shell embeds Perl/Python/Node; some programs lack an extension | bin/heavy-run, bin/agent-tab, bin/learn-repos-inventory, lib/ | fact |
| Source collection covers several families | [source inventory](rust-source-inventory.md) | fact |
| Where doctor, apply and sync time goes | Step 3 below | unmeasured |

**Existing Rust code is grandfathered.** The fixture crates shipped before
gate G existed. They are test fixtures, not ports. They stay with their
tests and do not count as migrated slices. The manifest gives them the
state `grandfathered`. A later change that makes Rust replace a production
path must pass G.

Read live source again when claiming a task. Newly merged behavior and newly
discovered code enter the inventory; this dated snapshot is not a scope limit.

## Scope and exceptions

In scope: owned code on a measured hot path. Today that is the two agent
hooks and `app-priority`.

Out of scope until reopened: every slice in
[Recorded exceptions](#recorded-exceptions).

Never in scope (manifest state `out-of-scope`):

- UI presentation and rendering assets. Exporters and CDP policy are backend
  work, not UI.
- Shell that must stay shell: sourced environment, shell functions and
  completions, first bootstrap before a binary exists, or a tiny
  external-protocol entrypoint. Move its business logic out when its slice
  is ported.
- Declarative YAML/JSON/plists, prompts, docs, data fixtures and lockfiles.
- Upstream chezmoi, Homebrew, Git, browser engines, Ollama and the memory
  service.

Frozen agent support stays as it is. The manifest marks it `frozen`. It
needs no port and no task.

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

This is the one rule for both repositories. The other plan holds the same
bullets, byte for byte.

- Hot-path slices and source collection in dotfiles do not wait for
  agentbrew. They use the dotfiles performance gate and local logs.
- A dotfiles step that runs `migration-check inventory` waits until the
  agentbrew task `rust-source-inventory` merges.
- A dotfiles step that runs `migration-check compare` also waits until
  agentbrew's deferred measurement runner merges. No other dotfiles step
  waits.
- Dotfiles pins the shared crate as a git dependency with an exact `rev`.
  It commits `Cargo.lock` and a `cargo vendor` copy, with a
  `.cargo/config.toml` source replacement. `cargo build --locked --offline`
  then works with no network and no sibling checkout.
- The vendored copy is a pinned snapshot of agentbrew's crate. Dotfiles
  never edits it and never writes a second engine.

## Measurement contract

### Commands that run today

Each command below was started once on the owner's Mac on 2026-11-10. The
text after each one says what it printed. One of them, the performance
gate, did not finish; its text says so.

```sh
scripts/perf-gate.sh --force --json
```

**Result not verified here.** The run printed
`perf gate: base ref origin/feat/chezmoi (last commit 2026-11-10), merge-base 788d43d5591a`.
Then it waited for an exclusive slot in the shared `heavy-run` queue. It had
printed no JSON when this revision was committed. The
[gate docs](../observability.md#performance-gate) say `--json` prints
`base_min` and `ratio` per row; this plan did not confirm that by a
finished run. The task `rust-agent-hooks` runs the gate before any change.

```sh
jq -c -s --argjson to 0 '(now - ($to + 7) * 86400 | todate) as $a | (now - $to * 86400 | todate) as $b | [.[] | select(.task == "app-priority" and .timing_source == "monotonic-ms" and .timestamp >= $a and .timestamp < $b) | .duration_ms] | {runs: length, mean: (if length > 0 then add / length else null end), zeros: (map(select(. == 0)) | length)}' ~/.dotfiles-stats.jsonl
```

This is the **window command**. The filter selects only valid millisecond samples. Before that filter existed, the old whole-second version printed
`{"runs":9674,"mean":1560.47,"zeros":2562}` (mean shortened here) for the
last 7 days. With `--argjson to 7` it printed
`{"runs":8654,"mean":990.41,"zeros":3531}` for the 7 days before. `to` is
the number of days back where the 7-day window ends. In the old result,
`zeros` counted runs rounded down to 0. In the new command it counts valid
sub-millisecond samples rounded to 0. `mean` is `null` for an empty window.

```sh
jq -s '[.[] | select(.task == "app-priority") | .duration_ms] | add / length' ~/.dotfiles-stats.jsonl
```

It printed `926.47`: the mean over all logged runs, with no time window.
Use it only as a sanity check, never as the 7-day number.

```sh
jq -s '[.[] | select(.command == "doctor") | .duration_ms] | sort | .[length / 2 | floor]' ~/.local/state/dotfiles/commands.jsonl
```

It printed `null`. The commands log on this Mac has a few lines and no
`doctor` line yet. The command prints `null` until that command has logged
runs; then it prints the local p50 in ms.

```sh
bin/bats-affected origin/feat/chezmoi
```

It printed one path, `tests/verify-counts.bats`, for this docs-only branch.
A port branch pipes the list into Bats under the queue:
`bin/bats-affected origin/feat/chezmoi | xargs heavy-run bats`. Those tests
are the behavior oracle.

```sh
for i in $(seq 15); do printf '%s' '{"tool_input":{"command":"git status"},"cwd":"/tmp"}' | /usr/bin/time -l agent-hooks/require-heavy-run.sh 2>&1 >/dev/null | awk '/maximum resident set size/ {print $1}'; done | sort -n | sed -n 8p
```

It printed `4636672`: the median peak RSS in bytes of 15 runs of one hook
row. This is the **peak RSS command**. Change the hook path to the row's
command. The agent sandbox blocks `/usr/bin/time -l`; run it outside the
sandbox.

### Commands that run after the agentbrew inventory step merges

`rust/Cargo.toml` and `migration-check` do not exist yet. These commands are
**runnable after the agentbrew task `rust-source-inventory` merges** and the
dotfiles adapter pins it. Until then no task may cite one as a command that
runs now.

```sh
heavy-run cargo build --locked --offline --release --manifest-path rust/Cargo.toml --bin migration-check
heavy-run rust/target/release/migration-check inventory --check
```

### Command that runs after the deferred measurement runner merges

```sh
heavy-run --exclusive rust/target/release/migration-check compare --slice <task ID> --pairs 30
```

No task builds the runner today (see
[Deferred preparation steps](#deferred-preparation-steps)). It is agentbrew's
to build. No task may cite `compare` until a reopened slice opens that step
and it merges.

Build with plain `heavy-run` first. Time only the built binary under
`heavy-run --exclusive`. Compile time never counts as workload time.

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

- **Time, for a row in the budget file (R_T):** the performance gate
  decides. It compares the fastest of 15 runs per tree and times a
  slower-looking row again, up to two more rounds. R_T is the `ratio` it
  prints. Since #573 the gate also requires the paired median difference to
  exceed the same slowdown limit before it fails a row. R_T remains the
  registered minimum ratio for the slice's benefit decision.
- **The row must keep its command path.** A row whose file the base commit
  does not have gets the ceiling check only. A port PR must not change the
  row's command path. The row keeps calling the same entry file, and that
  file calls the new code.
- **Time, for a logged run (R_T):** the mean `duration_ms` of a 7-day
  window from the window command above, with at least 1,000 runs in each
  window. Both before windows must start after the final timing change is
  deployed, and the after window must start after the candidate is deployed.
  R_T is the after window divided by the lower of the two before windows.
- **Time, for a workload with no row and no log (R_T):** the median of the
  paired ratios candidate time / baseline time, from at least 30
  order-balanced pairs. Take a percentile bootstrap of the median with
  10,000 resamples and a committed seed. Use its upper 95% bound. This
  needs the deferred measurement runner.
- **Memory (R_M), one definition for every slice:** run the peak RSS
  command above once on the baseline tree and once on the candidate tree.
  Each run gives the median of 15 runs. R_M is the candidate median divided
  by the baseline median.
- **Noise floor first.** Each kind of number has its own floor:
  - Gate row: 20 A/A runs (base and head at the same commit) must pass 20
    times.
  - Logged run: two before windows (`to` 0 and `to` 7) must differ by at
    most 20% of the larger. On 2026-11-10 they differ by 37% (990 against
    1,560 ms), so the logged mean is **inconclusive today**.
  - R_M: two baseline medians must give a ratio from 0.95 to 1.05.
  - Workload with no row: the A/A upper bound must be at most 1.05.

  If a floor fails, the result is inconclusive. Fix the measure or the run
  conditions; never the thresholds.
- **p95** is a field number. Read it from the owner's dashboard, where the
  sample count is large. It is not a merge gate.

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
  `heavy-run`. `make check` must build Rust only when `rust/` changed. The
  Makefile has no cargo step today. The first port task that adds Rust code
  (`rust-agent-hooks` or `rust-app-priority`) adds that step with this
  condition.

**Named exemptions.** G as a whole applies to port slices only: steps 1
and 2. Steps 3, 4 and 5 and the two deferred preparation steps (the
measurement runner and native delivery) port nothing. Only the first two
clauses apply to them: contract parity and the safety counts. The
"former implementation absent" clause, R_T, R_M and the user-benefit number
do not apply to them. The build budget applies to any of them that builds
Rust.

**Pivot:** any safety or contract failure stops rollout. A resource bound
above 1.10 changes the architecture or slice boundary before a retry. A
missed user-benefit number ends the slice; it does not lower the number. An
ended slice becomes a row in [Recorded exceptions](#recorded-exceptions)
with its measured number, in the same PR that ends it. Inconclusive results
keep the old implementation active and the task open. Never adjust
thresholds after results.

## Numbered work breakdown

The linked TASKS.md blocks are the execution queue. Work in isolated
fixtures and already-authorized interfaces is AFK. One implementation PR
changes one behavior boundary. Tests move with their slice: a port keeps
the old Bats tests until the new ones catch the same planted faults. There
is no separate "move tests to Rust" step.

| Step / task ID | Why and change | User-benefit metric, number and command | Depends on |
|---|---|---|---|
| 1. `rust-agent-hooks` | Two hooks run on each agent Bash call and start Perl, `shfmt` or `jq`. Remove those starts. Weigh a shell fast path first. | `hook-require-heavy-run` and `hook-block-dangerous-git` `ratio` at most 0.50 each, from `scripts/perf-gate.sh --force --json`, after 20 clean A/A runs. The rows keep their command paths. | none |
| 2. `rust-app-priority` | `app-priority` runs every 60 seconds at about 1 to 1.6 s mean. First make the number usable: log real milliseconds. Then weigh one `ps` pass. | 7-day mean `duration_ms` at most 400 ms and at most 40% of the lower before window, from the window command, after the before windows agree within 20%. | none; parallel with 1 |
| 3. `rust-cold-path-profile` | Doctor, apply, sync, upgrade and the queue lack qualified child-span coverage. The registered pivot retains them as exceptions. | Not separable with the currently evidenced method; local p50 and owned share are unknown. Reopen only with a qualified measurement. | none; pivot recorded |
| 4. `rust-source-inventory` | Keep scope honest with a manifest and a thin pinned adapter to agentbrew's small validator. No full harness. | Recorded exception: preparation. Done when `migration-check inventory --check` rejects every planted omission. | Source collection: none. The check: agentbrew `rust-source-inventory`. |
| 5. `rust-final-audit` | Prove that every owned executable has one of the five audit states. | Recorded exception: audit. Done when unrecorded components are 0 and every ported slice still meets its number. | 1, 2, 3, 4, and the confirmed owner ruling |

Each hot-path task commits its absolute baseline number before any
replacement code. The ratio or mean above is the decision rule.
The first instrumentation prediction is in
[app-priority timing](app-priority-timing.md).
The [hook baseline](rust-hook-baseline-2026-11-11.md) records both sets of
20 A/A runs and the absolute linked-checkout observations.
The [cold-path fixture audit](rust-cold-profile-fixture-audit.md) records
safety boundaries, unknowns and the registered pivot criteria. No profile ran.

### Cold-path pivot (2026-11-12)

The registered pivot applies because the current method cannot establish
complete child-span coverage for at least two families. Independent review
found the same gap in all five. The provider probe required more privileges;
PATH wrappers and parent timing alone miss some child and background work, and
adding child durations can count overlapping time twice. No owned-time share
was estimated. The command-log check found no matching local samples on
2026-11-11, so local p50 is unknown for every row below.

| Family | Local p50 | Owned wall-time share | Decision |
|---|---|---|---|
| Doctor | Unknown | Not separable | Retain exception |
| Apply | Unknown | Not separable | Retain exception |
| Sync | Unknown | Not separable | Retain exception |
| Upgrade | Unknown | Not separable | Retain exception |
| Queue | Unknown | Not separable | Retain exception |

This is a limit of the current evidence, not proof that measurement is
impossible. Reopen a family only after a separately registered scratch-only
method proves isolation, complete child and background coverage, overlap
handling and calibration. The [fixture audit](rust-cold-profile-fixture-audit.md)
records the family-specific gaps.

On 2026-11-12 the owner confirmed all seven defaults. The agentbrew task
`rust-owner-rules-on-replan-defaults` still tracks recording the ruling in
the other plan; the technical dependencies of step 5 remain.

Existing runnable guards: `heavy-run make check`; installation paths also
use `heavy-run make e2e`. Do not describe a future command as having passed.

### Deferred preparation steps

These steps have no task now. Open one when a recorded exception reopens
and needs it.

- **Measurement runner:** a thin pinned adapter to agentbrew's
  `migration-check compare`, for workloads that have no budget row and no
  logged run. It applies the statistic above. It waits for agentbrew's
  runner, as the cross-repo rule says.
- **Native delivery:** locked build, artifact integrity, atomic dispatch and
  rollback for a Rust binary on supported Mac targets. The first port that
  ships a binary opens this step.

### Recorded exceptions

A recorded exception has no user-benefit metric today. It stays in its
current language. It reopens only when both conditions hold: the owner's
dashboard, a local log or `rust-cold-path-profile` shows a user-visible
cost, and a profile puts at least half of that cost in owned code. A
reopened slice gets a task with its own number first. The task blocks that
this re-plan removed remain in git history at `788d43d`. The
[source ledger](rust-source-inventory-evidence.json) keeps the old slice
names as classification labels; this table gives each label its state.

| Slice (old task suffix) | Reason | Cheaper option to weigh first |
|---|---|---|
| process-primitives | No measured cost of its own. | None needed. |
| shared-queue | The owned share is not separable with the current method. Current queue fixes ship first. `app-priority` moved to step 2. | The `heavy-run-status` budget row guards it. |
| repository-discovery | Rare, agent-driven tools. | None needed. |
| cli-core | `dotfiles --version` takes about 64 ms. Startup is not the hot path. | The `dotfiles-version` and `dotfiles-config` budget rows guard it. |
| doctor-core and the doctor module groups (shell-editors, security, workflow, browsers, agents, macos, local-ai, apps) | Doctor probes are cold paths that wait on child tools. Not profiled. | Parallel or cached probes; profile first (step 3). |
| apply-install | The owned share is not separable with the current method. | Qualify a profile before reopening (step 3). |
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

**14-day field check.** Within 14 days after a switch, the slice must show
its gain outside the PR. For a logged run, use the window command: the
after window against the before windows, by the logged-run statistic. For a
hook row, the hooks write no log line; run the gate again with
`PERF_GATE_BASE` set to the commit before the switch (a documented gate
setting). The owner's dashboard shows the same comparison by version for
all installs; it is private and has no public link yet. No gain rolls the
slice back.

**Final audit rule.** The audit passes when every owned executable
component in the manifest has one of five states:

- `ported`, with receipts.
- `exception`, with a row in the table above. This includes a slice that
  ended at its Pivot.
- `frozen`: frozen agent support.
- `grandfathered`: Rust code that shipped before gate G (the fixture
  crates).
- `out-of-scope`: UI presentation and shell that must stay shell, as listed
  in [Scope and exceptions](#scope-and-exceptions).

Unrecorded components must be 0. The audit reports each measured hot path
as ported or as a supported exception. It never claims "all code is Rust". A language percentage or a
lower line count is coverage, not a user benefit.

## Decisions (2026-11-10)

The choices below were adopted on the reviewer's recommendation on
2026-11-10. On 2026-11-12 the owner confirmed all seven as a group. The
owner can reverse any of them. The agentbrew task
`rust-owner-rules-on-replan-defaults` tracks recording the same ruling in
the other plan.

| Choice | Adopted default |
|---|---|
| Order | The per-call hook slice comes first, with a pre-registered cut per agent Bash call. It needs no native delivery task and no full harness. |
| Cold paths | Doctor probes, sync orchestration and the other slices in the table above are recorded exceptions. |
| Test tasks | The separate "move tests to Rust" task is gone. Tests move with their slice. |
| Inventory | The inventory step is a manifest and a thin adapter to a small validator. |
| Cheaper options | Each slice weighs a cheaper fix first: one `ps` pass for `app-priority`, parallel or cached doctor probes, `bats --jobs` for the gate. |
| Existing Rust code | Fixture crates are `grandfathered`. Rust passes G only when it replaces a production path. The review asked for a statement; this is the default. |
| Final audit states | The audit accepts `ported`, `exception`, `frozen`, `grandfathered` and `out-of-scope`. The review said the audit needs an owner decision; the owner confirmed these states on 2026-11-12. |

## Validation review (2026-11-09)

An independent reviewer checked this plan against measured timings on
2026-11-09. Verdict: **re-plan before any port**. Zero of the 48 tasks in the
two repositories are done. The owner paused porting the same day and asked
for field metrics and a speed gate first
([Telemetry](../observability.md#telemetry),
[performance gate](../observability.md#performance-gate)).

The text in this section is the reviewer's, as written. Each resolution
stands beside it.

Measured on one loaded Mac; treat the numbers as a ranking, not a benchmark:

- Direct CLI use is rare for agents (6 runs in 9 days). `agentbrew --version`
  takes about 145 ms against a 34 ms Node floor; `dotfiles --version` takes
  about 64 ms. Startup is not the hot path.
- Hook helpers are the hot path. About 28,000 agent Bash calls in 9 days each
  fired about 8 hooks of 125-483 ms; `bash -c true` takes about 7 ms.
- In dotfiles, `app-priority` ran 17,488 times (1.3 s mean), and the Bats
  `test` step is 74% of gate time.
  *Note (2026-11-10): the window command now gives 1,560 ms for the last 7
  days and 990 ms for the 7 days before. See
  [Evidence and current state](#evidence-and-current-state).*
- Sync, git maintenance, upgrade, catalog, MCP lifecycle and doctor probes
  are likely dominated by git, network and child tools. They were not
  profiled; a port there needs a profile first.
- Rust compiles are already the largest agent Bash cost in other
  repositories. This plan has no build-time budget.
  *Resolution (2026-11-10): [Gate G](#gate-g) now has a build budget.*

### Findings to fix

No MUST finding is open in this text. The table below keeps each finding as
the reviewer wrote it.

Status on 2026-11-10: a first review of the re-plan graded findings 1, 2
and 6 resolved and findings 3, 4, 5 and 7 partly resolved in this
repository. This revision applies the fixes it asked for. A second
independent review on 2026-11-10 graded all seven findings resolved in both
plans.

### Resolved findings (2026-11-10)

| Finding, as the reviewer wrote it | What changed | Where |
|---|---|---|
| **Stale evidence.** The evidence table reviews an old revision. The repository now has Rust code that never passed gate G. State whether it is grandfathered or must pass G. | The evidence table reviews revision `788d43d`. Rust exists only as fixture crates. They are `grandfathered`; Rust passes G only when it replaces a production path. | [Evidence and current state](#evidence-and-current-state) |
| **Commands cannot run.** Every measurement command needs `rust/Cargo.toml` and `migration-check`. Both exist only in an unmerged draft. Mark them "runnable after the inventory step merges". Build with plain `heavy-run` first; time only the built binary under `--exclusive`. | Commands are split into three blocks: run today (each was run once, with its output stated), run after the agentbrew inventory step merges, and run after the deferred runner merges. Build uses plain `heavy-run`. | [Measurement contract](#measurement-contract) |
| **Gate G contradicts the preparation steps.** Inventory, harness and native delivery still dispatch to the old runtime, so they cannot run "without the legacy runtime". Exempt them by name. | G applies in full to port slices only. The named non-port steps keep only the parity and safety clauses. | [Gate G](#gate-g) |
| **The statistic is not usable.** An upper 95% bound on a p95 ratio from 60 pairs rests on about three tail samples, and measured noise was 19-50%. Name the estimator (for example a bootstrap of the median ratio) and measure the noise floor first, or every result is "inconclusive". | The p95 bound is gone. Gate rows, logged runs and memory each have one definition, one command and a noise floor. The logged `app-priority` mean fails its floor today and says so. A bootstrap of the median ratio covers workloads with no row. | [Statistic and noise floor](#statistic-and-noise-floor) |
| **The final audit cannot pass.** Frozen agent support stays, exclusions are forbidden, and the audit needs zero unexplained legacy components. This needs an owner decision. | The audit accepts five named states and needs 0 unrecorded components. The owner confirmed the states on 2026-11-12. The agentbrew task `rust-owner-rules-on-replan-defaults` tracks the corresponding update to its plan. | [Rollout](#rollout-security-and-regression-coverage), [Decisions](#decisions-2026-11-10) |
| **One cross-repo rule.** Say once whether dotfiles work waits for the agentbrew validator, and how the shared crate is pinned (git revision plus vendoring) so `--locked` builds work offline. | One rule with the same bullets in both plans: who waits for the inventory, who waits for the runner, and git `rev` pin plus `cargo vendor`. | [Cross-repo rule](#cross-repo-rule) |
| **No user benefit metric.** Each slice needs one (for example p95 hook time per agent Bash call). A slice with none becomes a recorded exception. | Every step names a metric, a number and a command, or is a recorded exception with its reason. The `app-priority` number uses a 7-day window. | [Numbered work breakdown](#numbered-work-breakdown), [Recorded exceptions](#recorded-exceptions) |

Proposed changes (SHOULD, owner decides):

- Move one hook-dispatcher slice to the front, with a pre-registered p95 cut
  per agent Bash call. It does not need native delivery or the full harness.
- Keep cold paths (doctor probes, sync orchestration) as recorded exceptions.
- Drop the separate "move tests to Rust" tasks; tests move with their slice.
- Cut the inventory step to a manifest and a small validator.
- Weigh cheaper options per slice first: lazy command loading and the Node
  compile cache for CLI startup; one `ps` pass for `app-priority`; parallel
  or cached doctor probes; `bats --jobs` for the gate.

*Resolution (2026-11-10): each one is adopted by default in
[Decisions](#decisions-2026-11-10). The owner confirmed all seven on
2026-11-12. One
difference: the pre-registered cut is on the gate's fastest-run `ratio`, not
on p95, because p95 is not a usable merge statistic here.*

Every later port must show its gain on the field dashboard and pass the
performance gate. Events carry a `runtime` field (`ts`, `shell`, `rust`) for
that comparison.

*Resolution (2026-11-10): see the 14-day field check in
[Rollout](#rollout-security-and-regression-coverage). It names a local
command for each kind of slice.*

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
