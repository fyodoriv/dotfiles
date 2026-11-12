# Non-test source classification prediction

Registered before the classification is produced, 2026-11-12.

Hypothesis: a bounded, source-backed review can distinguish executable-source
candidates from declarative or generated-input candidates outside the test
folder, while keeping unclear cases unresolved. This makes the next inventory
review more useful without claiming ownership or execution.

Measurement: a read-only checker compares the reviewed records with the 34
non-test candidates marked absent by `source-evidence-join.json` at its pinned
revision. It verifies each path, mode and blob against Git, checks cited line
spans and rejects planted omissions, duplicates, wrong identities and invalid
categories. An independent reviewer inspects the source-backed classifications.
It does not run sources, render templates or print source contents.

Success: exactly 34 unique records; zero identity or span mismatches; every
planted omission, duplicate, wrong identity and invalid category is rejected;
zero unsupported classifications in independent review. Preserve unclear
cases as unresolved. Record the unreviewed 383 test-tree candidates and six
stale-only candidates separately.

Pivot: if source evidence cannot support a classification, mark the record
unresolved. If the checker cannot verify an identity or source span, stop and
fix the checker before claiming coverage. This triage is not a complete
manifest, a runtime observation, or the pinned agentbrew validator.

Anchor: [source evidence join](source-evidence-join.json) at its recorded
candidate revision and [migration plan](rust-migration.md#numbered-work-breakdown).
