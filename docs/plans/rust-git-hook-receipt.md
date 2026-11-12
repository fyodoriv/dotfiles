# Git hook source receipt prediction

Registered before implementation on 2026-11-11. The tracked `git-hooks/`
family has three files at `81bcb6879d481d2ba3dedde256db278255b6e1ee`.
These hooks can source shared helpers, run inline AWK and delegate to other
hooks. A selected source anchor is evidence of text, not proof of execution,
complete embedded code, installed configuration or downstream ownership.

Hypothesis: the existing receipt checker can pin all three file identities
and selected entry, source, inline-interpreter and delegation anchors, while
rejecting every registered identity or anchor mutation.

Measurement: extend the existing checker with a Git-hook mode. Record mode,
blob and selected exact source lines. Independently review the selected
boundaries and regenerate the receipt twice. Plant removal, wrong mode, wrong
blob, duplicate path and missing anchors per file; plant wrong line, wrong
text and duplicate per anchor. Run the earlier doctor and library modes too.

Success: 3/3 identities match; every selected anchor matches; all planted
mutations are rejected; both generations agree; and prior checks pass. Pivot:
any missing identity, accepted mutation or claim that selected anchors cover
all behavior rejects the receipt. Installed and dynamic hook edges remain
open for the final inventory.

Anchor: `rust-source-inventory`, the existing receipt checker, Basili,
Caldiera and Rombach 1994 (GQM), and Munafò et al. 2017 (pre-registration).
