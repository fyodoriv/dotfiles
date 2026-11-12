# Scripts source receipt prediction

Registered before implementation on 2026-11-11. The tracked `scripts/`
family has eight files at `8a2cb8ce664277d54c5b4a93cde20d360fb940fa`.
It includes shell, Node and Perl entrypoints and selected inline interpreter
or child-command boundaries. A source anchor proves text at a revision; it
does not prove execution, complete embedded code, dynamic targets or ownership.

Hypothesis: extending the existing receipt checker can pin all eight file
identities and selected entry and child-command anchors while rejecting every
registered identity or anchor mutation.

Measurement: record mode, blob and selected exact lines; regenerate the
receipt twice and compare bytes. Independently review all identities and
anchors. For every file plant removal, wrong mode, wrong blob, duplicate
path and removal of its anchors; for every anchor plant removal, wrong line,
wrong text and duplicate. Run the prior doctor, library, source-syntax and
Git-hook modes. No source program is run by the receipt.

Success: 8/8 identities and all selected anchors match; every planted mutation
is rejected; both generations agree; earlier modes pass. Pivot: any missed
identity, accepted mutation or claim that the selected anchors cover complete
behavior rejects this method. Dynamic targets and the full inventory remain
open.

Anchor: `rust-source-inventory`, the existing receipt checker, Basili,
Caldiera and Rombach 1994 (GQM), and Munafò et al. 2017 (pre-registration).
