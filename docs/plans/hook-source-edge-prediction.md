# Hook source edge verification prediction

Registered on 2026-11-12 before checker implementation. An exploratory read
of the pinned launcher found a path assignment, dynamic import and later
launch of the hook memory harness. The earlier role receipt left this
candidate unresolved; that exploratory observation is not a predicted
discovery.

Hypothesis: a pinned context checker can preserve this source-level edge and
reject changes to any of its required anchors. Measurement: reopen the pinned
launcher and prior reference receipt, and run a focused mutation test.
Success: all required assignment, import and launch anchors match, and every
planted anchor or identity change is rejected. Pivot: any ambiguous or missing
anchor leaves the edge unresolved. This does not prove the launcher ran, a
child completed, ownership, or full caller coverage. Do not run the launcher.

Anchor: [test reference roles](test-reference-roles.json); Basili, Caldiera
and Rombach 1994 (GQM).
