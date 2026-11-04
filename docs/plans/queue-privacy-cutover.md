# Queue privacy cutover admission

The compatibility reader keeps the existing record format. Before changing
writers, prove that an old controller cannot participate in the managed queue.
An empty queue and an atomic entrypoint replacement cannot give that proof.
A disposable check with the unmodified strict 429 and 430 launchers let each
publish a held ticket after both conditions were true. Each payload then
exited successfully and removed its ticket.

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
