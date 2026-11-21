# Queue privacy cutover admission

The compatibility reader keeps the existing record format. Before changing
writers, prove that an old controller cannot participate in the managed queue.
An empty queue and an atomic entrypoint replacement cannot give that proof.
A disposable check with the unmodified strict 429 and 430 launchers let each
publish a held ticket after both conditions were true. Each payload then
exited successfully and removed its ticket.

## Open lock handles can outlive the path

A scratch Darwin control held the old lock while the strict 429 and 430
launchers opened it. A directory at the sequence-file path forced each
launcher to wait without a ticket. The control verified the open lock
descriptor for each owned process and found no payload tickets.

An atomic path swap replaced the lock file with a directory. Both fresh
launches refused before their payloads ran. Both pre-open waiters started
exactly once after the fixture released its original lock. The path swap
rejected fresh opens after that release. An open handle survived the swap.
An empty ticket scan cannot establish that the old lock is unused.

Require independent evidence that old handles are gone before new admission.
Use the boot and launch-route checks below to cover that gap. These controls
used disposable directories and unmodified fixtures. The live queue was
outside the test.

## Required evidence

Bind the staged receipt to the authoritative boot identity on this host.
Reject missing, malformed and nil boot identities. A boot change can exclude
processes that were already running. Also verify that old executables cannot
start again against the managed queue through another route.

Verify the complete reservation cohort, including normal, legacy, exclusive
and fallback locks. Reject a partial record, unqualified held reservation,
old controller, pending grant or waiting ticket. The dispatch lock must stay
held from validation through atomic publication. Reject interrupted
transitions, changed identities or a receipt that no longer binds to the
staged entrypoints.

## Decision fixture

```sh
heavy-run cargo test --offline --locked --manifest-path tests/fixtures/queue-privacy-cutover/Cargo.toml
```

The test-only Rust fixture accepts a fully qualified synthetic transition
and rejects the registered unsafe alternatives. The older decision logic
failed the extra boot, launch-route, lock and cohort controls. The fixture
does not read the machine's boot identity or inspect the live queue.
Native evidence collection and the installed cutover remain open.

Keep the compatible writer until every required fact is independently
verified. Any false activation rejects the approach.

Anchor: the strict 429/430 queue reader controls and Basili, Caldiera and
Rombach (1994), Goal Question Metric.

## Native boot identity experiment

Goal: qualify the boot-identity input to the existing cutover decision.
Question: can a bounded Darwin reader get the current boot identity without
writing queue state or invoking another process? Measure with
`heavy-run cargo test --offline --locked --manifest-path tests/fixtures/queue-privacy-cutover/Cargo.toml --test activation`.

Keep the approach only if two reads match on the same boot, match the local
system utility in the test, and malformed, nil, or unterminated inputs yield
zero accepted identities. A mismatch, unavailable host read, or a malformed
identity accepted by the parser rejects the probe. The fixture must leave
all existing cutover decisions intact. It does not authorize activation or
establish that an earlier boot ended. Measurement framing: Basili, Caldiera,
and Rombach (1994), Goal Question Metric.

On macOS, the activation suite went from 17 of 19 passing with the empty
reader to 19 of 19 passing with the bounded native read. Both reads matched
the system utility, and the five malformed inputs returned no identity.
The test compares the value in memory and does not print it.

## Stage route replacement before a reboot

- **Hypothesis**: A staging receipt can identify an intact pair of
  replaced routes before later activation. A partial replacement,
  changed route or artifact, and replaced dispatch lock prevent handoff.
- **Measurement**: Run `heavy-run cargo test --offline --locked --manifest-path tests/fixtures/queue-privacy-cutover/Cargo.toml --test route_staging`.
  Use two inert launcher files, one inert artifact, a real lock and
  synthetic boot identities below a disposable directory. Replace the
  route files by rename. Validate both before publishing a receipt by
  rename. Compare the receipt to the current identities and fixed
  content while the dispatch lock is held.
- **Success**: One complete replacement publishes one matching receipt.
  Same-boot handoff refuses, and the staged receipt is recognized after
  one synthetic boot change. Partial replacement leaves zero receipts.
  A changed route, changed artifact, replaced dispatch lock or busy
  dispatch lock yields zero handoffs and no retained-state changes.
- **Pivot**: One receipt for partial state, one handoff after drift or
  on the same boot, or one state change during a refusal rejects the
  staging design.
- **Anchor**: The existing cutover admission fixture and the
  [managed route inventory](heavy-run-private-metadata.md#reviewed-managed-launch-routes).
  See Basili, Caldiera and Rombach (1994), Goal Question Metric.

The fixture checks a transaction in scratch space. Native reboot
provenance, actual installed route closure and fresh verified cohort
evidence remain separate activation prerequisites.
