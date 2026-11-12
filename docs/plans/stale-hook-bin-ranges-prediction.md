# Stale hook and bin range prediction

Registered before implementation, 2026-11-12.

Hypothesis: a content-free comparison of the three remaining stale-only
source paths will identify changed line ranges and preserve both old and
candidate identities for later boundary review. It will not prove behavior.

Measurement: a read-only checker uses the pinned source join and family
receipts to compare both Git blobs for each path. It records non-equal
line-alignment ranges and rejects planted file and range errors. An
independent reviewer checks the relationships and receipt. No source programs
run and no source text is copied into the receipt.

Success: exactly three uniquely matched path pairs; zero mode or blob
mismatches against their source receipts and Git trees; all changed ranges
reproduce; every planted file or range mutation is rejected.

Pivot: if an old source identity, candidate identity or complete comparison
cannot be verified, retain that path as unresolved. Ambiguous or missing old
anchors do not become current evidence. The receipt does not establish caller
coverage, semantic equivalence, ownership, execution or installed behavior.

Anchor: [source evidence join](source-evidence-join.json) and
[migration inventory](rust-source-inventory.md).
