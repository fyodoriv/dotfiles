# Queue probe measurement preparation

## Overall goal and vision

Measure the remaining resource-probe failures before replacing their execution
path. The queue must use the owner's available capacity without authorizing
work from unknown resource state or losing guard refresh behind a stalled
lookup. This is a preparation change, not completion of queue safety.

## Decision and alternatives

Add the measurement engine to agentbrew's shared Rust measurement boundary.
Dotfiles owns a thin pinned Rust adapter and a declarative synthetic queue
fixture catalogue. Keep shell only where its execution context is required;
Bats logic is not a blanket exception. Do not create a second generic
process supervisor or a new Python/Perl measurement implementation.

Reuse the registered Rust child-ownership work where its actual contract fits.
Its fixed Git worker is not automatically a general queue-probe API. Register
any required adapter separately and prove its ownership and deadline contract.
GNU Coreutils is already managed by dotfiles. Assess its timeout command as a
maintained adapter candidate; do not claim it bounds output or every escaped
descendant. Do not reuse lib/run-with-timeout.sh as a complete supervisor: its
timeout path sends TERM and then waits without a second bound.

## Evidence ledger

| Claim | Source | Status |
| --- | --- | --- |
| Generic command capture waits synchronously and retains stdout | bin/heavy-run, cmd_out | fact |
| App lookup is cached by each controller; load and memory reads share the output helper | bin/heavy-run, realtime/load1/pressure | fact |
| Exhausted load/memory fallback can look clear | bin/heavy-run, load1/pressure | fact |
| Custom memory probe status one can deliberately mean clear | tests/heavy-run.bats | fact; preserve this documented policy |
| The separate app-status fix rejects failed and malformed lookup results | local baadea48, queue-realtime-probe-validity plan | reviewed local work; not deployed |
| Held-ticket evidence can be stale when a grant exists | strengthened realtime-probe fixture | fact; reject the coexisting grant |
| A native shared measurement engine and queue adapter can expose bounded-probe failures | proposed artifacts below | proposed |
| A two-second aggregate guard-refresh contract is met | future measured queue adapter | verify; not current behavior |

## Scope, ownership and lifecycle

The subject is one exact trusted heavy-run source hash. Seal its test and
fixture hashes before measurements. The measurement engine belongs to the
shared Rust harness in agentbrew. The Rust adapter and fixture catalogue belong to
dotfiles. One invocation owns its scratch queue, probe children, workloads,
readiness receipts and output directory. Delete scratch data only after owned
work has ended. Never kill a PID merely because a receipt contains that number.

Retain the outer Mac-wide heavy-run reservation and its worker budget. Inner
synthetic queues must not inherit a nesting bypass, read owner settings, or
authorize extra real work. No machine setting, service, installed entrypoint,
native conversation store or live queue record changes in this preparation.

Raw command lines, paths and real probe output stay out of committed fixtures
and public reports. Use only generated markers and fixed wait categories.
Keep private measurement artifacts in the owner's local state folder.

## Registered preparation hypothesis

- **Goal/question/metric:** can the measurement system distinguish a safe
  response, a missed resource decision and an invalid timing sample? Measure
  false-safe verdict rate against a separately sealed fixture oracle.
- **Hypothesis:** false-safe verdict rate is zero across the registered fault
  controls; valid positive controls complete successfully. This is measurement
  validity, not a claim that current production behavior is safe.
- **Measurement:** implement the proposed adapter contract below, then run its
  self-check, sealed current-source baseline and required repository checks.
  Capture actual exit codes, source hashes, readiness, timing validity,
  decisions and owned-process absence. No manually timed observations.
- **Success:** zero false-safe verdicts, zero invalid timing samples reported
  green, every positive control passes and every negative capability control
  rejects the seeded bad outcome. Record the baseline even when unsafe.
- **Pivot:** any false-safe verdict, leaked child, missing readiness, subject
  hash mismatch, unchecked grant, or invalid sample reported green rejects the
  measurement approach. Do not weaken the oracle or count setup/compiler errors
  as product failures.
- **Anchor:** Basili, Caldiera and Rombach (1994), Goal Question Metric;
  preregistered failure controls and source-bound lifecycle measurements.

Proposed commands, not installed commands at registration:

```sh
heavy-run --exclusive cargo run --locked --manifest-path rust/Cargo.toml --bin migration-check -- probe-measure self-check
heavy-run --exclusive cargo run --locked --manifest-path rust/Cargo.toml --bin migration-check -- probe-measure baseline --check
heavy-run make check BATS_JOBS= TEST_FILE_JOBS=
```

The Rust adapter must refuse when its pinned shared runner is unavailable
or unverified. It must not silently fall back to a second measurement engine.
The current docs-only gate is the existing make check command above.

## Sealed policy and fault matrix

Freeze these IDs, expected outcomes, fixture hashes and subject hash before
engine implementation. Additional cases require a prediction amendment before
their results are viewed. Do not redefine existing first/exclusive policies.

| IDs | Input and context | Expected policy or instrument verdict |
| --- | --- | --- |
| P01-P03 | Known app no-match; first normal, idle exclusive, additional | admit |
| P04-P06 | Known app present; the same three contexts | hold |
| P07 | Running workload, app present then unknown then clear | pause, retain pause, resume |
| P08 | Explicit empty app list | no app probe; preserve other policies |
| P09 | Custom memory probe status one with empty output; additional | admit |
| P10-P11 | Known high memory pressure; first normal, idle exclusive | preserve admission allowance |
| P12-P13 | Known high load; first normal, idle exclusive | preserve admission allowance |
| P14 | Known high load; additional, enabled load check | hold |
| P15 | High load; additional, max-load zero | preserve disabled-load admission |
| P16 | Known high memory pressure; additional | hold |
| F01-F03 | App probe silent stall; first normal, idle exclusive, additional | no unsafe grant; refresh decision within subject target |
| F04 | Partial app output then stall; additional | no unsafe grant; bounded decision |
| F05 | App output exceeds 64 KiB; additional | unknown, hold; bounded decision |
| F06 | Probe leader exits but descendant retains output; additional | unknown, hold; bounded cleanup and decision |
| F07-F08 | All enabled load sources unavailable or malformed; additional | unknown, hold |
| F09-F10 | All enabled memory sources unavailable or malformed; additional | unknown, hold |
| M01 | Stale wait reason with existing grant | measurement rejects safe-wait claim |
| M02 | Owned descendant survives reported completion | measurement rejects cleanup claim |
| M03 | Invalid timing/resource sample | inconclusive, never green |
| M04 | Subject hash mismatch | setup refusal, never product red or green |
| M05 | Fixture hash mismatch | setup refusal, never product red or green |
| M06 | Missing readiness | setup refusal, never product red or green |

F07-F10 apply only where a resource check is enabled by existing policy.
They do not silently remove first-normal/idle-exclusive allowances, enable
disabled load checks, or reinterpret the custom memory probe's exit contract.
Separate changes to those policies require a new explicit prediction.

The future two-second subject clock starts at the fixture's atomic guard-state
change and ready receipt. It ends only when the externally observed admission
or pause decision reflects that state and any probe cleanup has completed.
Include cache delay, every configured app, fallback reads and cleanup in this
aggregate budget. A probe-only duration does not meet it.

The instrument has a separate 30-second per-case total deadline, including
spawn, input/output, cancellation, joins, cleanup and reaping. Reserve the final
two seconds for cleanup; parent cancellation also gets a two-second complete
cleanup budget. The full matrix invocation ends within 20 minutes. Retain no
more than 64 KiB per captured child stream and 1 MiB of total event/output data
per case. Overflow is an explicit non-green outcome, not truncated evidence
reported safe. Baseline subject failures stay unsafe; instrument failures are
inconclusive. None of these bounds is proof until the self-check validates it.

## Numbered work breakdown

### 1. Build and validate the instrument

- **Why:** a broken stopwatch or stale wait receipt can approve a broken queue.
- **Parallelism:** the fixture contract and source review can proceed now;
  executable adapter integration depends on the shared Rust measurement owner.
- **Owner/change:** shared Rust engine, thin dotfiles Rust adapter and sealed
  oracle fixtures; production admission remains unchanged.
- **Acceptance:** known-safe and deliberately unsafe trace controls produce
  the correct verdict. A stale wait reason plus an existing grant cannot pass.
  Missing helper, failed launch, missing readiness and malformed receipts are
  non-green setup outcomes.
- **Verification:** the proposed self-check command and independent oracle
  review. Commit its prediction before fixture results are seen.

### 2. Record the unchanged-source baseline

- **Why:** the later fix needs before/after numbers from the same sealed cases.
- **Parallelism:** after step 1 passes and the instrumentation preparation is
  delivered; it can run separately from other repository work.
- **Owner/change:** one private measurement invocation; no runtime source fix.
- **Acceptance:** cover normal first, idle exclusive and additional admissions,
  plus a running protected workload. Separate valid no-match, app present,
  explicit opt-out and the custom memory probe's status-one clear behavior.
  Faults include unavailable/error/malformed readings, a partial-output stall,
  a silent stall, output overflow and a descendant retaining an output pipe.
- **Verification:** the proposed baseline command. Read actual assertions and
  receipts; keep invalid and incomplete observations separate from failures.

### 3. Register and deliver the runtime change separately

- **Why:** measurements must precede the fix, not be chosen after it works.
- **Parallelism:** depends on the delivered instrument and valid baseline.
- **Owner/change:** a separate task and PR for the measured probe adapter.
- **Acceptance:** preregister exact observed-to-target movements, an aggregate
  two-second guard-refresh budget including probe execution and cleanup,
  bounded retained output, unknown-state refusal, and zero wrong admissions.
  Use the same controls; preserve owner limits and approved scheduling policy.
- **Verification:** identical before/after commands, required gates and an
  independent source/behavior judge. Do not close resource-safety work merely
  because the app-status classifier or instrumentation is delivered.

## Timing validity and negative capability

Reuse the already registered quiet-run validity policy rather than inventing
post-hoc thresholds: finite CPU readings at or below 80%, available RAM at or
above 15%, a 20 ms observer with gaps no greater than 200 ms, CPU refreshes at least
250 ms apart, and wall/monotonic
divergence no greater than 200 ms. An unavailable sampler, sleep, pause, load
saturation or invalid sample is non-green and inconclusive. Keep thresholds
unchanged when retrying. Timing runs use exclusive heavy-run ownership.

The engine must distinguish owner completion from descendant absence. Its
deadline includes input, output, cancellation, joins, cleanup and reaping.
Include positive and negative descendants, inherited signal policy, protected
unrelated work and a deliberately misordered cleanup control. Reuse the shared
lifecycle proof rather than weakening this adapter's absence oracle.

## Rollout and remaining work

Land the preparation first. Do not change bin/heavy-run execution in it. Only
after its measurement validity and baseline are independently accepted may the
runtime task start. Publication follows normal source/leak gates when GitHub
sign-in is restored; local preparation is allowed meanwhile.

CPU headroom, aggregate worker budgets, workload reservation lifetime, private
metadata activation and starvation/exclusive fairness remain separate proof
obligations. The aggregate timing target does not by itself prove them.
