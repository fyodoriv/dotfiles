# Real-time app probe validity implementation plan

## Overall goal and vision

The shared queue must not call a failed app lookup proof that no protected app
is running. Preserve safe parallel work when the lookup succeeds. Hold new
admissions and keep the real-time pause active while the result is unknown.
This step classifies real-time probe results; it does not complete all queue
resource, lifetime or private-metadata work.

## Decision and alternatives

Normalize the real-time lookup result as clear, present or unknown, preserving
its command status. Use a fixed non-payload reason for unknown. Keep the
controller-owned two-second cache and all configured slot/project limits.
Do not change the shared cmd_out helper without accounting for its other
load, memory and process-tree callers.

Treating every nonzero status as an error is wrong: pgrep status one is a
known no-match. The existing custom memory probe also uses stdout semantics
and deliberately permits a clear branch with status one. Neither contract
changes. A general resource supervisor or timeout rewrite is separate work.

## Evidence and current state

| Claim | Current source of truth | Delivery path | Status |
| --- | --- | --- | --- |
| Command capture discards status | bin/heavy-run, cmd_out | realtime lookup | fact |
| Empty stdout becomes no protected app | bin/heavy-run, realtime | decide before normal/exclusive admission | fact |
| Known real-time apps hold every run and pause running work | docs/agent-hooks.md and tests/heavy-run.bats | current real-time policy | fact |
| Failed probes permit the seeded admissions | proposed controls below | real scratch controllers | verify |
| Status normalization holds every unknown result | proposed narrow normalizer | existing real-time cache | proposed |

## Scope and boundaries

The probe and cache belong to one Perl controller process. A cached result
expires under the existing two-second policy and disappears with that process.
A verified clear result is pgrep status one with empty stdout. A present result
has status zero and valid PID output. Failed, unavailable, signaled, malformed
or contradictory results are unknown. Never place raw stderr, command text or
probe payloads in wait reasons.

Unknown holds first normal, idle exclusive and additional admissions. It must
not look like an app quit and resume already paused work. Only a later known
clear result releases that real-time hold. An empty configured app list remains
an explicit opt-out. Preserve known load/memory first-run allowances, the custom
memory probe's status-one clear branch, FIFO, caps, priority and memory ordering.

## Registered hypothesis and measurement

- **Hypothesis:** preserving and validating app-lookup status reduces twelve
  seeded unsafe admissions to zero and one seeded incorrect resume to zero.
  The twelve admissions are four unknown cases across first normal, idle
  exclusive and additional-job contexts. These baseline numbers are predictions
  until actual old-source assertions are observed.
- **Unknown cases:** status two with empty output, status three with empty
  output, unavailable/status 127 with empty output, and status zero with empty
  output. Add malformed or contradictory-output controls without counting an
  already blocked old case as a new unsafe-admission baseline.
- **Measurement:** proposed `realtime probe:` controls in the existing Bats file,
  followed by its scheduling suite and required gate. First freeze the controls
  against unchanged production code. Record actual semantic failures; setup,
  compiler or readiness failures are inconclusive.
- **Success:** zero wrong admissions and incorrect resumes; every known-clear,
  known-present, explicit-off and retained scheduling control passes; every
  required gate exits zero.
- **Pivot:** any wrong admission, incorrect resume, unproved probe readiness,
  changed owner limit or retained-policy regression rejects the approach. Do not
  shorten waits, skip assertions or weaken the app-detection contract.
- **Anchor:** Basili, Caldiera and Rombach (1994), Goal Question Metric;
  pgrep's installed manual status contract; the existing documented hold policy.

```sh
heavy-run bats --filter 'realtime probe:' ./tests/heavy-run.bats
heavy-run bats ./tests/heavy-run.bats
heavy-run make check BATS_JOBS= TEST_FILE_JOBS=
```

## Numbered work breakdown

### 1. Reproduce status loss

- **Why:** prove actual unsafe decisions before changing capture logic.
- **Parallelism:** first; the Rust inventory can proceed separately.
- **Owner / boundary:** scratch Bats state, fake app lookup and recorded children.
- **Change:** add source-bound probe fixtures and the registered controls.
- **Evidence / acceptance:** own probe-ready receipts precede admission/pause
  observations; a workload marker exposes the old unsafe grant. Keep positive
  no-match, present-app and explicit-off controls.
- **Verification:** the filtered command above on frozen unchanged code.

### 2. Normalize the real-time result

- **Why:** unknown app state must not authorize heavy work or a resume.
- **Parallelism:** depends on a valid red from step 1 and this committed plan.
- **Owner / boundary:** the existing real-time probe and per-controller cache.
- **Change:** preserve status for this lookup, classify it, and expose only a
  fixed safe unknown reason. Keep other command-output consumers unchanged.
- **Evidence / acceptance:** identical controls pass without changed assertions;
  the known-present to unknown transition retains the pause until known clear.
- **Verification:** the same filtered command and complete scheduling suite.

### 3. Integrate and review

- **Why:** retain all existing machine-policy and compatibility behavior.
- **Parallelism:** depends on step 2; source review can run beside queued checks.
- **Owner / boundary:** dotfiles source, hook guide and required repository gate.
- **Change:** document the three results, ownership scope and unchanged policy.
- **Evidence / acceptance:** exact-tree gate zero and independent source review;
  no claim that all probes or the queue are now fully safe.
- **Verification:** required make check command above and normal leak checks.

## Rollout, security and remaining work

Commit this prediction before fixture or production changes. Use only private
scratch state and owned children; preserve and reap fixture work after both
positive and negative outcomes. Never probe, pause or kill the owner's jobs.
A separate registered adapter is still required for bounded/output-capped probe
execution and hung-probe guard refresh. Exhausted load/memory reads, workload
lifetime, worker budgets and private writer rollout remain separate unfinished
boundaries. Reuse the managed Coreutils dependency where suitable; do not add a
silent unbounded fallback. Public delivery waits for fresh GitHub authentication;
local tests and review may continue.
