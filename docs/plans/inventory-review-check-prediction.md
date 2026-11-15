# Inventory review check prediction

Registered before implementation on 2026-11-15 for `rust-source-inventory`.
The tracked-tree snapshot and shared comparison bridge are merged.

**Hypothesis:** A strict review ledger bound to each tracked source object,
combined with independently recorded embedded and generated observations,
will reject missing reviews, missing manifest entries, and stale source data.

**Measurement:** Hosted Rust controls check a complete fixed fixture and
plant missing extensionless, embedded, generated, and review records, changed
source objects, duplicate records, invalid states, and malformed input.

**Success:** The complete fixture passes and every planted error fails.
**Pivot:** Any accepted omission, stale identity, or malformed record rejects
the check. It must not report a complete audit from incomplete data.

The check does not independently discover embedded programs or generated
outputs. Each source review and observation must still be established from
the source before the migration inventory or final audit can be completed.
It reads one committed Git tree; uncommitted and untracked work remain outside
this check and must be assessed separately.

**Anchor:** `rust-source-inventory`, the shared bridge prediction, Basili,
Caldiera, Rombach 1994, and Munafò et al. 2017.
