# CI source inventory prediction

Registered before implementing the receipt on 2026-11-12. The tracked
`.github/scripts/` family is not in the earlier source ledger. Workflow and
Makefile references can name these scripts without proving they execute.

Hypothesis: a pinned lexical receipt will account for all tracked script
identities and literal references to their basenames in the pinned Makefile
and workflow files, while leaving dynamic callers explicitly unknown.

Measurement: read the pinned Git tree, record each script path, mode, blob and
first line, then search the Makefile and tracked workflows for literal script
basenames. Regenerate byte for byte and plant missing, duplicate, identity,
line and text errors. Run the focused tests and hosted required gate.

Success: all five tracked scripts and all literal matching lines in the named
search scope are present; every planted error is rejected and regeneration is
byte identical. Pivot: an omitted source, ambiguous match or accepted planted
error keeps this family unqualified. No lexical reference proves execution or
complete workflow behavior.

Anchor: `rust-source-inventory`, the pinned Git source tree, Basili, Caldiera
and Rombach 1994 (GQM), and Munafò et al. 2017 (pre-registration).
