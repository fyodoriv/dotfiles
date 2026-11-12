# Workflow source inventory prediction

Registered before implementing the receipt on 2026-11-12. Workflow `run:`
blocks can contain owned executable code outside the script inventory. A
lexical receipt is a review aid, not a YAML execution model.

Hypothesis: recording every line that matches the registered workflow `run:`
predicate, together with its indented block when present, will expose those
pinned source candidates for the later executable inventory.

Measurement: read every tracked `.github/workflows/` blob at the pinned Git
revision. Match lines whose trimmed text starts with `run:` or `- run:`;
record the source blob, line and exact indented continuation for block scalars.
Regenerate byte for byte and plant missing, duplicate, blob, line and content
errors. Run focused checks and the hosted required gate.

Success: every matching line in every tracked workflow is present; all planted
receipt errors are rejected; regeneration is byte identical. Pivot: an omitted
matching line, ambiguous block boundary or accepted error leaves the receipt
unqualified. This lexical predicate does not establish valid YAML, runtime
execution, dynamic code, or code outside `run:` candidates.

Anchor: `rust-source-inventory`, the pinned workflow tree, Basili, Caldiera
and Rombach 1994 (GQM), and Munafò et al. 2017 (pre-registration).
