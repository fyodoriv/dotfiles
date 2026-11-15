# Inventory snapshot bridge prediction

Registered before implementation on 2026-11-15 for `rust-source-inventory`.
The shared comparator and committed-tree snapshot are merged separately.

**Hypothesis:** Binding reviewed entries and independently observed embedded
and generated identities to every tracked path and its Git object prevents
omitted files and stale source reviews from passing the shared comparison.

**Measurement:** Hosted Rust controls plant an omitted extensionless file, an
omitted embedded identity, an omitted generated identity, and a changed source
object. They also check a complete fixed fixture.

**Success:** The complete fixture passes and every planted omission or stale
identity fails. **Pivot:** Any accepted omission or stale source rejects the
bridge; do not mark the inventory complete.

The caller still must discover embedded and generated identities independently
and review ownership, callers, and states. This bridge does not prove that
the supplied observations are complete or include uncommitted work.

**Anchor:** `rust-source-inventory`, the shared comparator, and the tracked
snapshot prediction; Basili, Caldiera, Rombach 1994; Munafò et al. 2017.
