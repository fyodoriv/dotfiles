# Tooling-checkup source reference prediction

Registered before implementing the receipt on 2026-11-12. Eleven candidate
scripts under the tooling-checkup skill had no exact match in the nine listed
family receipts. The candidate index already records their identities.

Hypothesis: a pinned literal-name search across tracked text will expose source
lines that mention the skill scripts, without claiming those lines execute.

Measurement: enumerate the tracked blobs under `skills/tooling-checkup/scripts/`
at one pinned revision. Search all tracked text in that tree for their literal
basenames. Record each matching path, source blob, line and matched names; do
not copy the line contents. Regenerate byte for byte and plant omissions,
duplicates and wrong identity, line or name fields. Run focused tests and the
hosted required gate.

Success: all eleven tracked script identities and all matching lines in the
registered text search appear; every planted error is rejected; regeneration is
byte identical. Pivot: a missed search match, ambiguous path or accepted error
leaves the receipt unqualified. The receipt does not establish execution,
dynamic calls, binary content, generated scripts or ownership classification.

Anchor: `source-evidence-join.json`, the pinned Git tree, Basili, Caldiera
and Rombach 1994 (GQM), and Munafò et al. 2017 (pre-registration).
