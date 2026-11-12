# Root executable source receipt prediction

Registered before implementation on 2026-11-11. A read-only candidate scan
at `861c94fbe37176c95fed04e258abc942f31e45db` found six root-level tracked
blobs with an executable mode, a shebang, or a shell/Python/Perl/Node source
suffix. This includes sourced non-executable shell files. The predicate does
not cover extensionless non-executable programs without a shebang, generated
files or dynamic callers; those remain open.

Hypothesis: the existing receipt checker can reproduce this bounded root
candidate set and reject every registered identity and selected-anchor error.
The result will not claim actual execution or complete repository coverage.

Measurement: derive candidate paths, modes and blobs from the pinned Git tree;
record selected entry, helper and command anchors; regenerate twice and
compare bytes. Independently review identities, anchors and predicate. Plant
removal, wrong mode, wrong blob, duplicate path and missing anchors per file;
plant removal, wrong line, wrong text and duplicate per anchor. Run all prior
receipt modes. The checker reads blobs; it never executes the recorded files.

Success: six of six candidate identities and all selected anchors match; every
planted mutation is rejected; both generations agree; prior modes pass. Pivot:
any missed predicate result, accepted mutation or completeness claim rejects
the method. Generated output, extensionless non-shebang code and semantic
caller coverage remain open for the full inventory.

Anchor: `rust-source-inventory`, the existing receipt checker, Basili,
Caldiera and Rombach 1994 (GQM), and Munafò et al. 2017 (pre-registration).
