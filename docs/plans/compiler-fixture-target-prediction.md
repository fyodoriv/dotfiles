# Compiler fixture target verification prediction

Registered on 2026-11-12 before building the checker. An exploratory read
of the pinned manifest found three explicit test paths. That observation is
not a pre-registered discovery result.

Hypothesis: a pinned checker can preserve those three declarations and reject
changed target paths or source identities without running Cargo. Measurement:
run a focused checker test against the pinned manifest and three files, with
planted path, kind, mode and blob changes. Success: all 3 declarations match
and all planted changes are rejected. Pivot: any unsupported declaration or
accepted change leaves the relationship unresolved. These are source
declarations only; they do not establish execution, ownership or migration
scope.

Anchor: the pinned Bats discovery receipt and the
[Cargo target reference](https://doc.rust-lang.org/cargo/reference/cargo-targets.html);
Basili, Caldiera and Rombach 1994 (GQM).
