# Measured Rust migration plan

## Overall goal and vision

Convert dotfiles-owned executable logic to Rust in small, measured steps. Keep
UI code and necessary shell scripts in their current languages, as requested on
2026-11-01. Preserve self-healing, one-command setup, privacy and agentbrew's
ownership of generated agent configuration (VISION.md G1–G4; US01/03/05/06/08).

This plan adds tasks. It does not implement Rust or claim a speedup. Per-slice
runtime, CPU, RSS and build baselines are **unmeasured**. Continue current queue
and correctness fixes independently; consume their delivered behavior as the
migration baseline. Use one behavior boundary per implementation PR.

## Decision and alternatives

Land instrumentation, then replace one owned implementation behind its existing
command or protocol. Reuse maintained Rust libraries and external tools. Keep
upstream chezmoi, Homebrew, Git, browser engines, Ollama and the memory service.
Their owned adapters remain in scope.

A single rewrite prevents attribution and risks losing failure cases. Permanent
dual implementations double maintenance. Use temporary measured dispatch bridges
with explicit deletion conditions and tested rollback instead.

Agentbrew owns the reusable measurement engine and versioned receipt protocol.
Dotfiles adds a thin Rust adapter pinned to an exact tested source revision.
Do not duplicate that engine or depend on a sibling checkout's relative path.

## Evidence and current state

| Claim | Current source of truth / delivery | Status |
|---|---|---|
| The task backend is TASKS.md; make check is the local gate | Agentfile.yaml, AGENTS.md, Makefile | fact |
| The reviewed revision has no Rust workspace | Tracked source at 1063ca76; Cargo manifest absent | fact |
| Shell embeds Perl/Python/Node; some programs lack an extension | bin/heavy-run, bin/agent-tab, bin/learn-repos-inventory, lib/ | fact |
| Doctor discovers module entrypoints | bin/dotfiles-doctor, modules/*/doctor.sh | fact |
| Dashboard UI and export processing are separate | skills/tooling-checkup/dashboard/index.html; skills/tooling-checkup/scripts/dashboard_export.py | fact |
| Swift helpers contain native application-event logic | lib/quit-watcher.swift; lib/chrome-dock-guard.swift | fact |
| Existing timings lack complete per-slice CPU/RSS data | scripts/gate-timed.sh; scripts/benchmark-run.sh; scripts/heavy-run-bench.sh | fact |
| A shared Rust harness and incremental dispatch bridge | Preparation tasks below | proposed |
| Native target/host-ABI matrix and baseline values | Inventory, installation contract and sealed receipts | verify |

Read live source again when claiming a task. Newly merged behavior and newly
discovered code enter the inventory; this dated snapshot is not a scope limit.

## Scope and exceptions

- Migrate owned runtime, embedded code, extensionless tools, executable templates,
  generators, hooks, native event logic, workflow helpers, non-UI tests and tooling.
- Keep actual UI presentation/rendering assets. A directory named UI, dashboard
  or browser, or a .swift suffix, does not justify an exception. Exporters and
  CDP policy remain backend work. Classify UI-test glue by its responsibility.
- Keep shell only when its execution context is required: sourced environment,
  shell functions/completions, first bootstrap before a binary exists, or a tiny
  external-protocol entrypoint. Move its business logic to Rust. Existing .sh
  scripts and Bats test logic are not blanket exceptions.
- Keep declarative YAML/JSON/plists, prompts, docs, data fixtures and lockfiles.
  Inspect any template that generates executable code separately.
- Keep upstream implementation upstream. Owned generators/adapters and generated
  owned runtime still need inventory entries.
- Preserve frozen support without fixes/features. Record conflicting residue as
  unresolved; it cannot silently pass the final conversion audit.

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

The Python TLS adapter needs a feasibility proof for a Rust host extension.
A standalone executable is not equivalent to an in-process import. The external
Python host can remain; owned implementation must be Rust. Unsupported ABI or
signing, or unavoidable executable non-Rust glue, remains an explicit unresolved
scope decision. Never weaken TLS validation to complete the migration.

## Measurement contract

These commands are **proposed preparation deliverables**, not existing tools.
The inventory task first delivers the manifest and runnable inventory checker
through a pinned adapter to agentbrew's reusable validator. It rejects planted
embedded, extensionless and generated-code omissions. Source collection can run
independently, but automated acceptance waits for that upstream validator.
The dependent harness task delivers the remaining commands and proves them
before a production replacement:

```sh
heavy-run --exclusive cargo run --locked --release --manifest-path rust/Cargo.toml --bin migration-check -- inventory --check
heavy-run --exclusive cargo run --locked --release --manifest-path rust/Cargo.toml --bin migration-check -- harness-selftest
heavy-run --exclusive cargo run --locked --release --manifest-path rust/Cargo.toml --bin migration-check -- baseline --slice all --seal
heavy-run --exclusive cargo run --locked --release --manifest-path rust/Cargo.toml --bin migration-check -- compare --slice rust-cli-core --samples 60
heavy-run --exclusive cargo run --locked --release --manifest-path rust/Cargo.toml --bin migration-check -- final-audit
```

Each slice seals an unchanged source/fixture/toolchain/cache/platform baseline B.
Commit the actual numbers and numerical prediction **before implementation**.
If measurement is missing, land instrumentation first and keep the port blocked.
Queue wait, workload execution, external tools, build/install, cold startup and
warm work are distinct measurements. Do not attribute one to another.

Use paired, order-balanced trials in isolated homes. Seal sample counts and the
analysis recipe before trials. The default is 60 pairs per workload/cache
condition with an upper 95% paired confidence bound for p95 execution time and
peak RSS ratios. Pin the estimator, seed and resampling method in the harness;
validate it with planted controls. Near-zero/unstable baselines require an
absolute budget committed before replacement. Bounded retries are specified in
advance. Keep unfavorable runs. Missing or contaminated data is inconclusive.

Record contract results, file mutations/modes, CPU, execution wall time, RSS with
platform-correct units, process cleanup, native-only execution, artifact size
and install/build cost. Observe the owned process group, not just its direct
child. Resource-probe unknowns and contaminants are explicit validity fields.

**Common gate G:** approved contract parity is 100%; unauthorized writes,
credential disclosures, false permits and orphaned owned processes are 0;
converted owned logic passes 100% with its former implementation absent.
Define R_T as candidate execution-p95 divided by baseline execution-p95, and
R_M as candidate peak RSS divided by baseline peak RSS. Their upper 95% paired
confidence bounds must each be <=1.10. This targets runtime independence, not a speed claim. A speed
claim additionally needs a pre-registered p95 reduction of at least 10% with the
same safety/memory guards. Commit numeric build/install budgets too; a faster
hot path cannot hide slower installation or development.

Any safety/contract failure stops rollout. A resource bound above 1.10 changes
architecture or slice boundary before retry. Inconclusive results keep the old
implementation active and the task open. Never adjust thresholds after results.
Queue proof measures real CPU/memory workload throughput, worker-budget safety
and interactive latency; sleeping-job overlap alone does not prove capacity.

The queue under test uses a separate per-fixture admission directory shared only
by its fixture workers. Scrub inherited lease/nesting markers at that test
boundary, as tests/heavy-run.bats already does for HEAVY_RUN_DIR and HEAVY_RUN_HELD.
This prevents the outer exclusive reservation from causing a nested bypass or
deadlock in the queue being measured. Keep the outer machine reservation and
its worker/resource budget intact; synthetic state never authorizes extra real
machine capacity. Never test by changing the live admission directory.

Raw outputs stay private. Commit only content-free workload IDs, hashes, numeric
results, validity fields and decisions. Never retain credentials, raw transcripts,
private paths, memory payloads or customer data in fixtures or public receipts.
An independent reviewer checks the evidence and each keep/pivot decision.

## Numbered work breakdown

The linked TASKS.md blocks are the execution queue. Implementation in isolated
fixtures and already-authorized interfaces is AFK. Live acceptance can require
HITL evidence for physical power/lid tests, endpoint signing or owner-only
credentials. Before claiming that work, list the real required evidence and
record unavailable owner-only proof as an explicitly blocked HITL child linked
to the relevant slice and final audit. Reuse existing matching proof tasks;
do not fabricate a human blocker for a check an authorized agent can run.
Each block lists dependencies, acceptance, hypothesis, command, success and pivot. Sources
below define engineering guidance, not immutable filenames. Every component in
the inventory must map to a slice or a permitted narrow exception.

| Step / task suffix (all IDs start rust-) | Why / concrete change and owner boundary | Dependencies / parallel lane |
|---|---|---|
| 1. source-inventory | Account for every owned executable, embedded interpreter, generated mapping, test and caller; deliver manifest and pinned validator adapter | agentbrew:rust-source-inventory for automated acceptance; independent source-collection lane |
| 2. measurement-harness | Thin pinned adapter to agentbrew's engine; fixture registry, sealed baselines, planted-fault controls | source-inventory; agentbrew:rust-measurement-harness |
| 3. native-delivery | Locked build/artifact integrity, atomic dispatch/install, supported Mac targets and rollback; bin/dotfiles-install, lifecycle scripts | measurement-harness |
| 4. process-primitives | Locks, bounded child groups, timeouts and caching; lib/lock.sh, lib/run-with-timeout.sh, bin/cached-run | native-delivery |
| 5. shared-queue | CPU/memory admission, inner-worker budgets, exclusive timings; bin/heavy-run, app-priority, headless detection | process-primitives; delivered current queue safety contract |
| 6. repository-discovery | Inventory/fingerprints, workspace status, affected selection and tasks; learn-repos tools, bats-affected, check-all, add-task | native-delivery; parallel pure lane |
| 7. cli-core | CLI/action registry, config/profile/enterprise precedence, output; bin/dotfiles*, lib/output.sh | native-delivery; parallel CLI lane |
| 8. doctor-core | Discovery, budgets, overrides, result/fix/recheck semantics; bin/dotfiles-doctor | cli-core; process-primitives |
| 9. doctor-shell-editors | shell, terminal, prompt, local-bin, editor, vscode, jetbrains module behavior | doctor-core; module lane |
| 10. doctor-security | security, git, ssh module denial/repair behavior | doctor-core; module lane |
| 11. doctor-workflow | chezmoi, sync, workflow, workspace, plugins, enterprise modules | doctor-core; repository-discovery |
| 12. doctor-browsers | agent-browser, chrome, resilience checks and safe repair | doctor-core; shared-queue |
| 13. doctor-agents | agentbrew, claude, codex, memory, minsky adapters; owner APIs and readiness | doctor-core; module lane |
| 14. doctor-macos | macos, personal-machine, home-theater profile checks | doctor-core; module lane |
| 15. doctor-local-ai | local-ai, local-llm, tools, upgrade discovery and opt-out behavior | doctor-core; module lane |
| 16. doctor-apps | extras, obsidian and any later inventory-discovered supported modules | doctor-core; module lane |
| 17. apply-install | Defaults/apply, package/cask installers, signing/shims, upgrades/uninstall; .chezmoiscripts, macos*.sh, apply-state/apply-defaults | cli-core; process-primitives |
| 18. plugin-trust | Signed plugin pins, sandbox/capabilities and transactional lifecycle; bin/dotfiles-plugin, lib/plugin* | cli-core; process-primitives |
| 19. services-power | Sync/reload/drift, wake/keepawake/Amphetamine, watchdog and notices; launchagents, tooling-sync | cli-core; process-primitives |
| 20. git-security-guards | Git/GitHub and agent hooks, leak/secret/private-ref scans, attribution, git-safe | cli-core; process-primitives |
| 21. browser-native | CDP/tab leases, temp browser, Slack, profiles, native quit/Dock events; bin/agent-tab, lib/*.swift | process-primitives; shared-queue |
| 22. local-ai-runtime | Agent/loop retry/verify/rollback/warmup logic; lib/local-ai-*.py, bin/local-ai-* | cli-core; process-primitives |
| 23. metrics-checkup | Checkup Python processors/exporter, stats/proof/scorecard/telemetry; UI unchanged | cli-core; process-primitives |
| 24. pty-tools | First fixture/observer measurement, then PTY capture/echo logic in separate measured steps | process-primitives |
| 25. developer-utilities | Scaffolds, notes/timers, status, snapshots, cleanup, PR/review and remaining assigned commands | cli-core; repository-discovery |
| 26. python-host-extension | In-process TLS adapter feasibility, ABI/signing and opt-in policy; lib/python/dotfiles_tls_relax.py | native-delivery; process-primitives |
| 27. test-build-tooling | Non-UI tests, fake services, coverage/build/gates, .github tooling; preserve independent negative controls | measurement-harness; per-domain ports before old oracle retirement |
| 28. final-audit | Residual/source/generated/install audit, runtime retirement and whole-tool evidence | all preceding slices |

Verification for each port is the exact `compare --slice <task-ID> --samples 60`
command above with the row's ID, plus G and its queue-block acceptance criteria.
Inventory and harness tasks have their own commands. A row spanning several
behaviors is a task series: split into measured substeps before coding. No
single aggregate benchmark may justify unrelated substep changes.

Existing runnable guards: `heavy-run make check`; installation paths also use
`heavy-run make e2e`. Existing focused Bats tests remain independent oracles
until their Rust replacements prove the same planted failures. Do not describe
future harness commands as having passed now.

## Rollout, security and regression coverage

Land inventory and instrumentation before replacement. Land native delivery,
then process/pure leaves. Doctor module groups may run in parallel after the
doctor contract. Isolate worktrees, fixture homes and outputs. Heavy work uses
the shared admission queue and bounded inner workers; timings use --exclusive.
Never cancel other sessions or bypass admission to obtain benchmark results.

Each boundary gets a baseline/prediction commit, measured implementation PR,
matching docs and rollback proof. Keep original negative cases. Test migrations
must first detect the same planted faults against an independent oracle.
Switch dispatch atomically; rollback only owned binary/dispatch/state and keep
user edits and unknown keys. Delete temporary bridges only with recorded proof.

Retain required Bash 3.2 and UI checks. Separate fake CDP/service results from
authorized throwaway-app proof. Physical lid/power, signed endpoint and real
credential paths need their own evidence; unavailable proof remains a blocker.
Never use owner tabs, real drafts, elevated changes or public posts as fixtures.

The final audit covers generated and installed entrypoints, all declared Mac
targets and install/update/uninstall/rollback. A language percentage or lower
line count is coverage, not a user benefit. Preserve failed measurements too.

## Open decisions and references

Inventory/preparation settle crate versions, target and host-ABI matrices,
analysis method, absolute near-zero budgets and reviewable substep boundaries
from live source. Choose reuse candidates only after checking their contracts.
Extra executable-language exceptions need an explicit scope decision; an agent
cannot invent one to pass the final audit. Current queue fixes take priority
over porting that queue. This migration covers these named repos' owned code;
other repositories remain consumers of the shared runner.

Metric anchors: Basili, Caldiera, Rombach (1994), Goal-Question-Metric; Munafò et
al. (2017), pre-registration; Kohavi, Tang, Xu (2020), experiment design;
Forsgren, Humble, Kim (2018), performance/stability outcomes.

Primary implementation references: [Cargo build](https://doc.rust-lang.org/cargo/commands/cargo-build.html),
[Cargo test](https://doc.rust-lang.org/cargo/commands/cargo-test.html), and
[PyO3 building/distribution](https://pyo3.rs/main/building-and-distribution).
Rust Python extension and embedding are distinct choices; PyO3 is a reuse
candidate requiring an ABI/signing proof, not an already selected dependency.
