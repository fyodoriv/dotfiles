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
  [managed route inventory](heavy-run-private-metadata.md#source-inventory-qualification).
  See Basili, Caldiera and Rombach (1994), Goal Question Metric.

The fixture checks a transaction in scratch space. Native reboot
provenance, actual installed route closure and fresh verified cohort
evidence remain separate activation prerequisites.

## Restore one interrupted scratch route before the reboot

- **Hypothesis**: A scratch restart can restore the first replaced route
  when a private record still identifies its original bytes, its staged
  replacement, the untouched route, the artifact and the dispatch lock.
- **Measurement**: Run `heavy-run cargo test --offline --locked --manifest-path tests/fixtures/queue-privacy-cutover/Cargo.toml --test route_staging`.
  Save the first route and record identities before the rename. Interrupt
  after that rename, reopen the dispatch lock and try recovery on the
  same synthetic boot. Compare the restored file and all retained state.
  Repeat with a changed route, archive, untouched route, lock, or journal,
  after a synthetic boot change, and after a final receipt appears.
- **Success**: One exact scratch restoration with no changed neighboring
  route or artifact. Recovery consumes its archive and journal. A repeat
  makes zero changes. Each of seven invalid recovery attempts changes
  zero files and retains its evidence.
- **Pivot**: One unrecorded replacement, one lost archive on refusal,
  one restoration on the wrong boot, or one changed unrelated file
  rejects the recovery design.
- **Anchor**: The existing staged-route fixture and the retained-state
  contract above. See Basili, Caldiera and Rombach (1994), Goal Question Metric.

This case stops the first staging attempt after a known rename. It does
not prove recovery from a power loss, native installation or another
interruption while restoring. The live queue stays outside the fixture.

## Finish scratch cleanup after a second interruption

- **Hypothesis**: A second scratch restart can finish cleanup when the
  first recovery already moved the exact archive into place.
- **Measurement**: Run hosted
  `cargo test --offline --locked --manifest-path tests/fixtures/queue-privacy-cutover/Cargo.toml --test route_staging`.
  Stage the first route, rename its archive over it, and stop before
  removing the recovery record. Reacquire the lock and retry on the
  same synthetic boot. Try the same retry with a byte-identical route
  at a different inode, a malformed journal, and a different boot.
- **Success**: One retry removes the recorded journal and makes zero
  other changes. A repeat and all 3 invalid cases make zero changes.
  All existing route cases still pass.
- **Pivot**: One removed journal on a refusal, one change to a restored
  route, or one regression in an existing case rejects cleanup.
- **Anchor**: The staged-route recovery fixture above and the exact
  file identity checks in its dispatch lock.

The [hosted baseline](https://github.com/fyodoriv/dotfiles/actions/runs/44869078709/job/136739284408)
failed with a missing archive. Recovery always looked at its old path.
After the rename, compare the archive identity at the live route in the
scratch directory. Recheck the lock, untouched route, and artifact in
the same bounded journal. The old replacement no longer exists, so only
its recorded shape and device can be checked. This step changes only
the fixture and covers a known rename boundary.

## Refuse staging when a recovery record remains

- **Hypothesis**: A recovery record in scratch space prevents
  receipt publication and later handoff even when both replaced
  routes match their expected files.
- **Measurement**: Run hosted
  `cargo test --offline --locked --manifest-path tests/fixtures/queue-privacy-cutover/Cargo.toml --test route_staging`.
  Prepare both fixture routes and keep a recovery record. Check
  receipt publication with a record from the partial replacement.
  Separately present a record after a valid receipt and check
  handoff after the synthetic boot change.
- **Success**: Both ambiguous cases refuse with 0 changed paths.
  The publication case creates 0 receipts. The original complete
  staging, handoff and recovery controls still pass.
- **Pivot**: One receipt or handoff with a recovery record,
  changed evidence on refusal, or a failed clean case rejects the check.
- **Anchor**: The existing recovery check refuses when a final
  receipt exists. Both operations must exclude the other's record.

The fixture keeps the record for review. This does not authorize
cleanup or activation on an installed route.

The [hosted baseline](https://github.com/fyodoriv/dotfiles/actions/runs/44889788643/job/136802919756)
published a receipt and allowed handoff in the two conflicting
cases. The receipt check compared both route identities and
ignored the recovery record. It now requires that record to be
absent under the dispatch lock before either action.
