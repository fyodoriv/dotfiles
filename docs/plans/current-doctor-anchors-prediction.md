# Current doctor anchor prediction

Registered before implementing the receipt on 2026-11-12. The source join
identified five doctor paths with stale identity evidence. A read-only probe
found each of the 33 historical selected anchor lines exactly once in the
current pinned doctor sources; that observation does not classify their bodies.

Hypothesis: mapping those selected anchors to the current pinned doctor blobs
will distinguish current source identities from the historical receipt while
preserving the exact reviewed line text.

Measurement: enumerate every `modules/*/doctor.sh` blob at the pinned revision;
map each historical selected anchor by exact text, requiring a unique match.
Regenerate the receipt byte for byte and reject planted omissions, duplicates,
wrong identities and anchor errors. Run focused tests and hosted CI.

Success: all 33 paths and all 33 selected anchors map uniquely; every planted
error is rejected; regeneration is byte identical. Pivot: any missing or
ambiguous anchor, omitted source or accepted error leaves the receipt
unqualified. It does not prove execution, module ownership, body equivalence,
or complete embedded-code coverage.

Anchor: `doctor-source-receipt.json`, the current Git tree, Basili, Caldiera
and Rombach 1994 (GQM), and Munafò et al. 2017 (pre-registration).
