# Shared inventory core ownership evidence

Registered before the repository check on 2026-11-15. A read-only comparison
found the vendored core source matches agentbrew's pinned Git blob. The core
is agentbrew-owned; the dotfiles copy is a pinned dependency.

**Hypothesis:** A source-bound ownership record and hosted check can detect a
changed vendored source, pin or file set without fetching or executing source.

**Measurement:** Hosted CI compares the committed vendor tree and Cargo pin
with the reviewed identities and checks planted source, pin and path changes.

**Success:** The current record matches and all three planted changes are
rejected. **Pivot:** Any mismatch or accepted planted change leaves the
ownership record unqualified until corrected.

This evidence does not complete executable discovery or the migration audit.
Anchor: the pinned shared-core dependency, `rust-source-inventory`, and Basili,
Caldiera and Rombach 1994 (GQM).
