# Register per-child confinement receipts

The first synthetic preflight reported all four controls passing, but its
receipt has only overall cleanup status. It does not retain one exit and close
record per child. Treat the cleanup evidence as incomplete; the first run does
not qualify the later CLI experiment.

Goal: make each owned child's termination reviewable. Question: can the same
four synthetic controls produce four individually named, successful exit and
observed-close records with unchanged tool identities? Predict four of four
records have exit code zero, no signal and an observed `close`; the four
original control outcomes must also pass, and the total operation must remain
under 30 seconds. Measure with the same registered
`JOBS=1 heavy-run node scripts/sync-preview-confinement-preflight.mjs` command,
then machine-check the private receipt against the exact four control names,
exit codes, close flags and pre/post hashes. No missing, duplicate or skipped
record is allowed. Any wrong control, missing close, signal, identity mismatch,
outside write, unexpected connection or deadline breach rejects this receipt
approach. A setup failure is inconclusive. Independently review the changed
preflight and receipt. Its limitations remain those in `248f96c`.

Anchor: Basili, Caldiera and Rombach (1994), Goal Question Metric; Munafò et al.
(2017), preregistration; first preflight's incomplete cleanup receipt.
