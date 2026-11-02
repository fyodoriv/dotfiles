# Guarded heavy-run metadata cutover

- **Task**: heavy-run-private-metadata
- **Repo**: dotfiles
- **Author**: inventory-snapshot, 2026-11-02
- **Status**: draft registration before instrumentation or writer changes
- **Validated-by**: root, conditional source-plan review on 2026-11-02;
  native capability review remains pending

## Overall goal and vision

Keep command arguments, working folders and project names out of new shared
queue metadata without breaking machine or project capacity. This advances
VISION G3 and story 06. Safe parallel admission remains a hard constraint.
Reader preparation is not privacy completion. Register and prove the missing
cutover instrument before implementing opaque writers.

## Decision and alternatives

Use a managed entrypoint barrier, complete bounded process-cohort evidence and
an atomic protocol-generation transition. A verified launcher enrolls before
loading a controller body. Keep the barrier closed through the final cohort
check and generation commit. A clear queue alone cannot authorize the change.

Reject one empty snapshot: an old Bash launcher or loaded Perl controller can
be paused before making a ticket. Reject a reader marker alone: file text does
not attest code holding sched.lock or a future writer. Never rewrite another
controller's records, change slots, fabricate workload leases or stop unowned
work. Old work drains normally.

The native bootstrap and bounded cohort observer are prerequisites, not tools
delivered by this plan. New guard/domain logic belongs in Rust. A tiny shell
bootstrap may only locate and exec its verified artifact. Add no Python
measurement engine or permanent shell exemption for Perl/Bats business logic.
Retain the raw protocol until the prerequisites pass.

## Evidence and current state

| Claim | Current source of truth | Delivery path | Status |
| --- | --- | --- | --- |
| Task requires seven privacy cases and guarded activation | TASKS.md, heavy-run-private-metadata | task backend | fact |
| Phase A normalizes readers but writes raw fields | bin/heavy-run: project_identity, snapshot, tick, ticket and owner writes | Bash to embedded Perl | fact |
| Leader retains loaded code while holding sched.lock | bin/heavy-run: lead and step | controller invocation | fact |
| Pending grants reserve capacity before owner publication | bin/heavy-run: tick and took | ticket and grant | fact |
| Source scripts are placed directly on PATH | home/zshrc, derived repo bin path | shell startup | fact |
| bin is excluded from direct chezmoi deployment | .chezmoiignore | source-directory scripts | fact |
| A native guard/bootstrap exists and is installed | proposed native artifact and delivery contract | managed launcher | verify |
| Managed closure covers pre-ticket old launchers | proposed bounded observer and installation certificate | native guard | proposed |
| No strict old cohort can decide after activation | actual old-source fixtures and race barriers | future instrument gate | verify |

Source baseline: baadea48c7558dfde1905fc933ab5d9f68870746. Preserve its base
branch and the old privacy worktree/stash. Do not revive the old candidate as
the current scheduler. The seven original privacy fixtures are frozen at Git
blob 2f6036c88c979bc5aa5f2fe0bf3fe4f766710c7c.

## Scope (in)

- Freeze supported executable entrypoints and launcher ownership.
- Add bounded cohort/entrypoint instrumentation and negative controls first.
- Cover strict 429/430 leaders, owners, pending grants, waiters and pre-ticket
  launchers. Refuse missing, unknown, busy or inconsistent evidence.
- Only then select private record/status writers and preserve admission contracts.

## Scope (out)

- No runtime code, deployment, live queue inspection or owner setting change
  in this registration. No public issue, comment or contribution.
- No reset, stash, deletion, commit or salvage rewrite in the old privacy
  worktree. Keep its useful staged work and frozen fixtures intact.
- No session/history transfer, historical-record purge or unowned process kill.
- No full queue language port or second benchmark framework. Use the existing
  rust-shared-queue, rust-native-delivery and rust-measurement-harness tasks.

## GET before IMPLEMENT

Reuse the current flock/gate protocol, strict fixtures, reader normalization,
interoperability controls and owner-configured heavy-run queue. Use maintained
native Rust adapters for bounded files, locks and process evidence. Do not
reuse the old candidate's stale scheduler or unbounded observations.

Agentbrew owns the shared Rust measurement/inventory engine. Dotfiles consumes
an exact reviewed revision through the pinned adapter in rust-migration.md.
Functional cutover fixtures are domain tests, not another measurement engine.
Native artifact/install bootstrap precedes runtime cutover. If unavailable,
record the dependency; add no shell or Python control-plane fallback.

## Boundary contracts

### Supported entrypoints and closure

Before code, freeze the actual managed source executable, installed PATH routes,
declared direct callers and symlink aliases in one installation manifest. Use
logical entrypoint IDs and hashes in receipts, not private absolute paths.
Unexpected symlinks, missing routes or unknown reachable old code refuse.

Include source bin/heavy-run: home/zshrc places it on PATH. Replacing a separate
user-bin link is insufficient. Inspect managed hook/PATH launch routes and
explicit direct callers. Fixture/worktree copies use isolated state; never
silently certify them for the live queue. Arbitrary obsolete copies and
anonymous copied shell bodies are outside managed rollout. If reachable through
a supported route, they are unknown evidence and refuse.

Every new managed launcher takes a shared generation barrier and publishes
content-free enrollment before resolving/loading its pinned controller body.
Hold this barrier only through verified handoff and acknowledgment, then release
it. Acknowledgment attests the artifact, generation and controller identity; it
does not wait for scheduler, sequence or workload locks. The separate invocation
participation lease lasts through the final possible queue read/write/decision,
including nested/fallback paths. It is not the generation-barrier lock. Transfer
its held identity without a gap; missing acknowledgment or transfer refuses.
A replacement cannot retroactively enroll old opened or loaded code.

The transition coordinator takes the exclusive barrier and closes new handoffs.
It takes no workload slot and creates no fake queue lease. Define/test lock
ordering: it must not wait for sched.lock while a compatible leader waits for
the generation barrier. Old queue/gate/slot bytes stay untouched.

For each protocol-sensitive operation, a controller acquires the shared
generation barrier, reads the committed generation, performs its consistent
read/decision/publication, releases operation locks, then releases the barrier.
Barrier acquisition is nonblocking. While it is unavailable, continue existing
cancellation and resource monitoring but do not admit work or publish format-
sensitive metadata. The compatible-controller controls must preserve that service.
An existing leader may retain sched.lock between operations. While holding the
barrier, acquiring scheduler, sequence or slot locks is nonblocking: release
the barrier before retrying an unavailable lock. Never wait for work completion
or hold the barrier for the lifetime of an owner, grant or waiter. Participation
identity remains held independently across these short operations.

The exclusive coordinator never waits for scheduler, sequence, slot or
participation locks. It only makes nonblocking ownership probes and checks
the stable participation evidence. Thus compatible active P02/P03 cohorts do
not prevent exclusive-barrier acquisition or introduce a lock cycle. Their
controls must exercise that acquisition and subsequent operation handoff.

### Complete cohort evidence

Cover the selected queue namespace and managed processes that could subsequently
touch it. Inspect held numeric and s<n> slots, exclusive ownership, sched.lock,
held tickets, temporary unpublished tickets, pending grants, waiters and
enrollments. Bind evidence to held lock/inode, code/artifact identity and process
lifetime. A marker, bare PID or workload-start file does not prove ownership.

A bounded native observer must also cover pre-ticket old Bash launchers and
loaded Perl controllers. Inspect arguments/source descriptors only in bounded
process-local memory to classify known code. Never persist or print raw argv,
environment, working folders or source payloads. Incomplete visibility, denied
query, truncated data, inaccessible descriptors or stale identity refuses.

PID reuse, exit/reap and exec transitions need controls. Two empty snapshots
are not closure. Couple the final observation to the closed entrypoint barrier
and stable participation leases. Independently review native completeness and
platform support. Missing support is a prerequisite failure, not an empty cohort.

The observer must close the enumeration-to-commit fork/exec gap. Require a
verified event/identity coverage boundary from before the census through commit,
including children born before a parent changes executable identity. Missing
coverage, overflow, dropped events or an unobserved birth/exec interval refuses.
Polling equal PID lists cannot substitute for that native capability. Freeze
the supported observer API and bootstrap proof before implementing activation.

Reader compatibility alone is insufficient. Any process that may publish raw
text or print unsanitized status must drain, including raw-only Phase A writers.
A compatible active cohort must attest typed reading AND private publication/
status behavior. Existing records remain owned by their controller; the guard
does not rewrite them.

### State ownership and atomic transition

Installation manifests/barriers have machine-user/queue-namespace scope.
Enrollment leases and raw/normalized identity have controller-invocation scope.
Fixture homes, groups and receipts have fixture-run scope. Epochs/certificates
contain versions, opaque IDs/hashes, fixed categories and bounded numeric data.

Proposed states: RAW, CHECKING, OPAQUE. Missing/damaged/stale evidence does not
grant RAW permission: fail closed. First bootstrap verifies its owned
installation state before handing off.

1. Stage/verify the native artifact and complete entrypoint set.
2. Install guarded launchers with content-free recoverable per-path receipts.
3. Close handoffs; capture the complete old/current cohort under that barrier.
4. Refuse strict/unknown or raw-only participants. Do not stop them. A bounded
   busy attempt leaves verified RAW operation in place.
5. Recheck identities, installed bytes/targets and generation.
6. Commit OPAQUE atomically while handoffs stay closed, then release them.

A compatible controller holds the shared barrier around each protocol-sensitive
decision/publication and observes the committed generation there. It cannot
cache RAW permission and publish later. The coordinator never rewrites an old
held record. Supported status reads sanitize legacy text without changing bytes.

Entrypoints need not rename simultaneously, but activation has one linearization
point after every route is verified guarded. Partial replacement grants nothing.
Every managed source updater, sync/apply path and rollback that can replace a
guarded executable must honor this transaction. An unadapted updater refuses
activation; it cannot later restore an unguarded writer behind a valid receipt.
Interrupted CHECKING stays closed/non-green until verified recovery. Recovery
may restore verified RAW routes before commit. After OPAQUE, never restore raw
writers while typed records remain live. Rollback uses the same closure/cohort
proof and preserves unowned data/jobs.

### Bounds and native prerequisites

Proposed fixed limits: 8,192 process identities, 64 KiB metadata per process,
64 MiB aggregate inspected process bytes, 4,096 queue entries and 8 MiB aggregate
queue-record bytes. Exceeded limits are unknown. Persist no names or argv.
One five-second absolute attempt includes lock acquisition, observations,
entrypoint verification, commit and recovery; reserve its last second for owned
transaction cleanup. No post-deadline repair loop or indefinite automatic retry.

These are acceptance inputs, not performance results. A complete bounded native
observer, launch-before-load bootstrap, locked artifact integrity and recoverable
installation are prerequisites, not existing commands. If the pinned adapter or
native delivery is unavailable, stop dependent implementation and retain reader
preparation. A forced fixture result cannot qualify a production host/entrypoint.

## Registered hypothesis and measurements

- **Hypothesis:** clear cohorts accepted by the fail-closed stub move from zero
  of four to four of four; unsafe activations remain zero in 24 negative controls.
  These are predictions. Then frozen disclosures move from seven of seven to
  zero of seven, with zero wrong admissions or lost scheduling contracts.
- **Success:** 100% expected decisions across the 28 rows; zero unsafe activation,
  old-record mutation, unowned termination or policy change; all seven privacy
  cases and required regressions/gates pass.
- **Pivot:** any disclosure, wrong admission, unverified activation, changed limit
  or old-file mutation rejects the boundary. Keep RAW preparation and redesign.
  Missing/invalid evidence remains explicitly non-green.
- **Anchor:** OWASP Logging Cheat Sheet, Data to exclude; Basili, Caldiera,
  Rombach (1994), GQM; Herlihy and Wing (1990), Linearizability. Preserve the
  ad87838 prediction and current project-cap protocol.

The Rust target and seven-case privacy file are proposed repository paths,
not installed commands. This checkout does not yet contain rust/Cargo.toml or
tests/heavy-run-privacy.bats. Integrate the latter from its exact frozen blob
before running its command. Commit this prediction before fixtures/code/results;
observe a real instrument-stub assertion red before implementation.

The existing helper paths, fixture paths and options below were checked against
this base: duplicate_identity.py declares --candidate, --legacy-429 and
--legacy-430, and selects its four cases explicitly; heavy-run-project-interop.py
declares the same three options and contains the original ten cases. The two
wrappers in tests/heavy-run-project-identity.bats use these exact inputs.
Strict fixture blobs remain f7c345a9c6fd4eac7bec36a36e918cddc740c5c5 (429) and
32e591a590f56d4a4c1d8c7784082cbd125c2f05 (430). These existing regression
oracles are distinct from the not-yet-delivered Rust and privacy targets.

Proposed domain sources are rust/src/bin/queue-cutover.rs and
rust/tests/queue_private_cutover.rs in the repository's single native workspace.
The instrument exposes inspect and activate; activate requires explicit --yes.
Its controller handoff is an inherited capability, not a forgeable marker or
runtime switch that forces a successful observation. Exact supported routes
and the native observer API remain prerequisites for implementation approval.

```sh
JOBS=1 CARGO_BUILD_JOBS=1 heavy-run cargo test --locked --manifest-path rust/Cargo.toml --test queue_private_cutover -- --test-threads=1
heavy-run env JOBS=1 bats ./tests/heavy-run-privacy.bats
heavy-run python3 ./tests/helpers/duplicate_identity.py --candidate bin/heavy-run --legacy-429=tests/fixtures/heavy-run-429 --legacy-430=tests/fixtures/heavy-run-430
heavy-run python3 ./tests/helpers/heavy-run-project-interop.py --candidate bin/heavy-run --legacy-429=tests/fixtures/heavy-run-429 --legacy-430=tests/fixtures/heavy-run-430
heavy-run env JOBS=1 bats tests/heavy-run.bats
JOBS=1 heavy-run make check BATS_JOBS= TEST_FILE_JOBS=
```

Timing controls use heavy-run --exclusive. Separate queue wait from execution.
The existing Python commands are regression oracles, not a new engine. New
non-UI domain/test logic is Rust. Preserve the seven fixtures byte-for-byte.
Use synthetic content; never copy real queue payload into a fixture/transcript.

### Frozen guard matrix

Each row has deterministic owned barriers/receipts. Every representation in a
row must satisfy its decision. Missing or unvisited cases do not pass.

| ID | Seeded condition | Expected |
| --- | --- | --- |
| N01 | Missing manifest or marker-only capability | refuse |
| N02 | Strict 429 loaded scheduler leader | refuse |
| N03 | Strict 430 loaded scheduler leader | refuse |
| N04 | Strict 429 numeric-slot owner | refuse |
| N05 | Strict 430 s-slot owner | refuse |
| N06 | Strict 429 exclusive owner | refuse |
| N07 | Strict 430 exclusive owner | refuse |
| N08 | Strict 429 live waiter | refuse |
| N09 | Strict 430 live waiter | refuse |
| N10 | Strict 430 pending grant before owner publication | refuse |
| N11 | Held temporary ticket before rename | refuse |
| N12 | Partial/missing held owner identity | refuse |
| N13 | Duplicate raw/typed identity | refuse |
| N14 | Unknown live kind/reader or raw-only Phase A publisher | refuse |
| N15 | PID/start/inode/code mismatch | refuse |
| N16 | Strict 429 Bash paused before any ticket | refuse |
| N17 | Strict 430 Perl paused before any ticket | refuse |
| N18 | Reachable old alias or already-open old source | refuse |
| N19 | Partial replacement or damaged recovery evidence | refuse |
| N20 | Failed/denied/truncated/stale/exhausted observer | refuse |
| N21 | Launcher races closed commit barrier | no old handoff |
| N22 | Interrupt before/at/after commit | no unsafe activation |
| N23 | Exit/reap/PID reuse during observation | no stale authority |
| N24 | Old-code cohort appears between checks | refuse |
| P01 | Fresh verified routes; complete empty old cohort | activate |
| P02 | Only attested private-capable active owners/leader | activate safely |
| P03 | Only attested private-capable pending grants/waiters | activate safely |
| P04 | Verified transition with worktree cap and independent project | correct admissions |

Use actual strict fixture bytes. Pause 429 with an owned external dependency
barrier; pause 430 before publication with an owned sequence-lock barrier. Do
not change old-source behavior. Every refusal compares legacy bytes unchanged
and keeps owned work alive until fixture release. Readiness uses actual held
locks and participant identity. Never signal through a stale receipt.

## Numbered work breakdown

### 1. Deliver native bootstrap and observation prerequisites

- **Why:** old loaded code cannot be enrolled retroactively.
- **Parallelism:** first; source inventory/frozen-fixture review can continue.
- **Owner / boundary:** dotfiles native delivery and pinned agentbrew adapter.
- **Change:** locked artifact, managed-route manifest, bounded observer contract
  and closed fixture target. Instrumentation precedes writers.
- **Evidence / acceptance:** complete routes, fail-closed budgets/unknowns and
  four real clear-cohort stub assertion failures.
- **Verification:** proposed Rust command above; no deployment.

### 2. Prove closure and recoverable commit

- **Why:** empty files do not rule out pre-ticket or loaded old readers.
- **Parallelism:** depends on 1 and independent platform/source review.
- **Owner / boundary:** one installation transaction; fixture-owned cohorts.
- **Change:** enrollment, cohort adapter and atomic generation/recovery.
- **Evidence / acceptance:** 28 correct rows; removing the entrypoint barrier
  fails N18/N21; ignoring pre-ticket processes fails N16/N17/N24.
- **Verification:** same frozen Rust command and limits.

### 3. Add private writers after guard acceptance

- **Why:** privacy must preserve admission correctness.
- **Parallelism:** depends on 2; no writer activation before source review.
- **Owner / boundary:** queue protocol and controller-owned records.
- **Change:** opaque fields and fixed categories behind verified generation;
  retain normalized reading and kind=v2 semantics.
- **Evidence / acceptance:** zero of seven disclosures, ten original reader and
  four duplicate-field controls pass; legacy bytes unchanged.
- **Verification:** frozen privacy/interoperability commands above.

### 4. Verify and deliver

- **Why:** every repo shares the machine policy and entrypoints.
- **Parallelism:** after 3; source review may overlap queued gates.
- **Owner / boundary:** dotfiles delivery; no owner-capacity change.
- **Change:** README/how-to, hook guide, recovery and task status. Keep legacy
  Bash/Perl/Bats responsibilities in the Rust migration inventory.
- **Evidence / acceptance:** scheduling/full gate zero on the composed tree;
  independent review approves activation.
- **Verification:** final two gate commands and normal leak gates.

## Risks and mitigations

- **Incomplete routes.** Refuse missing/unknown routes; test direct source,
  aliases, open files and exec transitions before certification.
- **Hidden old process.** Require complete bounded visibility and stable identity;
  unavailable fields refuse instead of becoming an empty cohort.
- **Corrupt old work.** Never rewrite records or kill unowned jobs; compare
  bytes/liveness across every refusal and interrupted transaction.
- **Raw write after activation.** Attest writer/status behavior and guard each
  operation; reader compatibility alone grants nothing.
- **Language/measurement duplication.** Deliver native prerequisites first,
  reuse the pinned engine and legacy oracles, add no Python control plane.

## Acceptance criteria

1. The Rust command reaches all 28 rows, satisfies every decision and rejects
   both planted closure mutations.
2. The unchanged seven-fixture privacy command reports zero disclosures.
3. Both interoperability commands, scheduling tests and required gate exit zero
   with unchanged limits, status, queue and process-lifetime contracts.
4. N01–N24 prove no supported old-code handoff after commit and refusal on unknown
   evidence. An operator's visual empty snapshot is not verification.

## Rollout and regression coverage

Registration precedes instrumentation. Native bootstrap and complete cohort
proof precede opaque writers. Deploy only the verified entrypoint set after
normal gates/review; this plan authorizes no live change. Keep the task open
until every acceptance holds. Preparation or scratch success is not completion.

Open decisions: exact native artifact/pinned adapter revision, supported route
manifest and bounded complete observer API. Each needs source review and real
negative controls. Unavailable prerequisites block dependent runtime code; do
not invent a fallback.

## Reviewer verdict

- **Verdict**: conditional source-plan approval; not runtime approval
- **Reviewer**: root, source-plan review
- **Date**: 2026-11-02
- **Concerns**: native bootstrap, observer API and supported-entrypoint closure
  still need independent source review before implementation/activation.
- **Approval rationale**: root's conditional review required separating the
  short handoff barrier from invocation participation and checking the existing
  regression command paths/options. This revision records those corrections.
  Gate/registration commit and native capability review remain pending; this
  verdict does not authorize opaque writers or claim any runtime result.
