# Unmatched test source relationship prediction

Registered on 2026-11-12 before inspecting remaining caller context. After
the Cargo fixture receipt, 12 of the 16 candidates without exact full-path
mentions still lack a source relationship in this pass.

Hypothesis: bounded source context can establish at least one explicit
relationship for these 12 candidates, including references written with a relative
path or a unique basename. Measurement: inspect the pinned source tree and
record only exact anchored declarations, with the candidate identities and
independent review.

Success: account for all 12 candidates, establish at least one unambiguous
declaration, and reject all planted identity or anchor changes. Pivot: leave
any dynamic, ambiguous or unsupported relationship unresolved. A declaration
does not prove execution, ownership, complete callers or migration scope. Do
not run the fixtures.

Anchor: [test source references](test-source-references.json),
[Cargo fixture receipt](test-cargo-targets.json), and Basili, Caldiera and
Rombach 1994 (GQM).
