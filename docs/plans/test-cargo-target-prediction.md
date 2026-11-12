# Test fixture Cargo target prediction

Registered on 2026-11-12 before target inspection. Four unresolved test-tree
files sit in two Rust fixture layouts; exact full-path search did not find
their callers.

Hypothesis: pinned Cargo manifests and documented target conventions can
identify at least one of those files as a declared fixture target. Measurement:
reopen the four pinned file identities and their fixture manifests, parse the
manifest fields, and verify each claimed path and target kind.

Success: account for all four files, confirm at least one target from pinned
manifest or default layout, and record zero unsupported target claims. Pivot:
if no target can be established or a relevant manifest setting is ambiguous,
leave that file unresolved. Do not run Cargo or the fixtures. A target
declaration does not prove a test ran, ownership, caller coverage or migration
scope.

Anchor: [test source references](test-source-references.json) and the
[Cargo target reference](https://doc.rust-lang.org/cargo/reference/cargo-targets.html);
Basili, Caldiera and Rombach 1994 (GQM).
