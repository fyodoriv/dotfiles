# Vendored file ownership in the inventory ledger

Register before implementation for `rust-source-inventory`. The registry
vendor and shared-core ownership reviews have merged. The partial ledger does
not yet contain their tracked files.

**Hypothesis:** Adding source-bound vendor file records makes every reviewed
vendored path visible to the inventory comparison without treating remaining
source discovery as complete.

**Measurement:** Hosted controls compare Git tree paths and blob identities
with both ownership reviews and ledger records, reject a planted omission, and
run the existing incomplete inventory check.

**Success:** 100% of tracked vendor paths match their reviewed owner and
classification; the planted omission is rejected; the overall check exits
nonzero while other source reviews and discovery are incomplete. **Pivot:** Any
stale path, changed identity, invented owner or successful incomplete check
rejects the change.

Registry source belongs to upstream package owners. Cargo-generated checksum
metadata is declarative and managed by dotfiles. The shared core source belongs
to agentbrew; its vendored metadata is declarative. This does not establish
complete discovery or runtime behavior.

**Anchor:** The merged vendor and shared-core ownership reviews; the partial
ledger prediction; Basili, Caldiera and Rombach 1994 (GQM).
