# Bats discovery prediction

Registered before implementation, 2026-11-12.

Hypothesis: a pinned, content-free receipt can connect unmatched Bats paths to
the Makefile discovery patterns, making their next inventory review easier
without assuming they ran or are out of scope.

Measurement: compare all absent test-tree candidates in the pinned source
join with the candidate Git tree. Match the Makefile's declared root and e2e
Bats globs as lexical path patterns. Check Makefile pattern lines at the same
revision. Verify exact candidate coverage and reject planted record omissions,
duplicates, identities and discovery labels. An independent reviewer checks
the pattern interpretation. No test or candidate source executes.

Success: all 343 Bats candidates and 40 remaining non-Bats candidates are
accounted for; zero identity mismatches; all planted errors rejected.

Pivot: if the pinned declaration cannot be verified or a file does not match
a declared pattern, record the gap rather than infer discovery. Pattern
membership does not prove runtime selection, test behavior, ownership, or
installation. This is not a complete inventory or the agentbrew validator.

Anchor: [source join](source-evidence-join.json) and the pinned Makefile.
