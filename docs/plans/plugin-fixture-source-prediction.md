# Plugin fixture source prediction

Registered on 2026-11-12 before inspecting the remaining unmatched plugin
doctor fixture's caller context.

Hypothesis: its pinned plugin fixture declarations and test references can
identify at least one explicit source-level relationship without running the
plugin. Measurement: reopen the pinned fixture identity and relevant
declaration anchors; reject planted path, identity and anchor changes.
Success: one unambiguous declaration is supported and every planted change
is rejected. Pivot: if the path is selected dynamically or the context is
ambiguous, keep it unresolved. A declaration does not prove the plugin ran,
ownership or complete caller coverage.

Anchor: [unmatched test relationships](test-unmatched-relationships.json)
and Basili, Caldiera and Rombach 1994 (GQM).
