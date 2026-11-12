# Stale lifecycle source range prediction

Registered before implementing the receipt on 2026-11-12. Three lifecycle
scripts have stale identity evidence in the source join. Independent source
review found changed executable boundaries, but did not run the scripts or
establish the new relationships' runtime behavior.

Hypothesis: a deterministic line-alignment receipt can identify every changed
source range between the historical ledger and candidate revisions for those
three paths, without copying source contents into the receipt.

Measurement: validate each path's historical and candidate blob and mode
against its pinned tree and the existing ledger/index. Use Python's
`difflib.SequenceMatcher` with `autojunk=False` on the two source line lists;
record every non-equal opcode and its half-open old and new line ranges.
Regenerate byte for byte and plant omissions, duplicates, identity, opcode and
range errors. Run focused tests and hosted CI. Do not execute the source.

Success: all three identities and all non-equal alignment ranges are present;
every planted error is rejected and regeneration is byte identical. Pivot:
any missing identity, unsupported opcode or accepted error leaves the receipt
unqualified. Line alignment is not semantic equivalence, ownership, execution,
condition evaluation or proof of generated output; those remain open.

Anchor: `source-evidence-join.json`, the historical ledger, Basili, Caldiera
and Rombach 1994 (GQM), and Munafò et al. 2017 (pre-registration).
