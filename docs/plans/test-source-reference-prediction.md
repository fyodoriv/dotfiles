# Test source reference prediction

Registered on 2026-11-12 before collection. The 40 test-tree candidates
without Bats-glob discovery remain unresolved.

Hypothesis: exact literal path references at the pinned candidate revision
can identify some declared callers without treating test names as execution.
Measurement: check a pinned source-reference receipt against the 40 records in
`bats-discovery-receipt.json` and exact path/line matches in that revision.

Success: all 40 candidates are accounted for, every recorded reference
reopens at the exact pinned path and line, at least one candidate has a
reference, and zero references are invented. Pivot: if no candidates have
exact references or identities cannot be checked, retain all discovery as
unresolved. A textual match is not proof of execution, ownership, dynamic
imports or complete caller coverage. Keep unmatched candidates unresolved.

Anchor: the [Bats discovery receipt](bats-discovery-receipt.json), Basili,
Caldiera and Rombach 1994 (GQM), and Munafò et al. 2017 (pre-registration).
