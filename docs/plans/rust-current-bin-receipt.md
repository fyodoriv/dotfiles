# Current bin identity receipt prediction

Registered before implementation on 2026-11-11. The earlier bin receipt is
pinned to `a1928495a953055ff7db3d8f525d504faef2dc3a`. The tracked `bin/` tree
at `c5ed285bbd51278501536bc40602761f779d24d2` has 135 blobs, including new
and changed paths. All have a first line. The earlier embedded-code anchors
remain historical until separately rechecked against current source.

Hypothesis: the existing checker can pin every current bin path, mode, blob
and first line and reject every registered identity or anchor mutation,
without claiming current semantic or caller coverage.

Measurement: derive identities and first lines from the pinned Git tree,
regenerate twice and compare bytes. Independently review the source count and
identities. For every file plant removal, wrong mode, wrong blob, duplicate
path and removal of its anchor; for every anchor plant removal, wrong line,
wrong text and duplicate. Run all earlier receipt modes. The checker reads
blobs and never runs recorded executables.

Success: all 135 identities and anchors match; every mutation is rejected;
both generations agree; earlier modes pass. Pivot: any omitted path, accepted
mutation, changed earlier mode or unsupported semantic claim rejects the
method. Embedded interpreter bodies, dynamic callers and generated outputs
remain open.

Anchor: `rust-source-inventory`, the existing receipt checker, Basili,
Caldiera and Rombach 1994 (GQM), and Munafò et al. 2017 (pre-registration).
