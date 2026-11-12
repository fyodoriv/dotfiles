# Source evidence refresh prediction

Registered before updating the join on 2026-11-12. The first join reported 305
exact, 11 stale-only and 428 absent candidates against nine family receipts.
The tooling-checkup and current-doctor receipts were reviewed afterward.

Hypothesis: adding those two pinned receipts will supply exact identity evidence
for the eleven previously absent skill scripts and five stale-only doctor
paths, while preserving all earlier evidence links and leaving other paths
unchanged.

Measurement: validate both new receipts against their own source trees, rerun
the join at a pinned revision containing them, compare every old and new link,
and plant input and output errors. Run focused tests and hosted CI.

Success: the 744 candidate partition becomes 321 exact, 6 stale-only and 417
absent; every prior link remains present; all planted errors are rejected and
regeneration is byte identical. Pivot: any different count, lost link, ambiguous
schema or source mismatch stops the refresh for investigation. The counts are
identity evidence only, not ownership, execution or a complete inventory.

Anchor: `source-evidence-join.json`, the reviewed tooling-checkup and doctor
receipts, Basili, Caldiera and Rombach 1994 (GQM), and Munafò et al. 2017
(pre-registration).
