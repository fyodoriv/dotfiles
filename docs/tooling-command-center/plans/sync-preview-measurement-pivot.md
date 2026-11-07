# Sync preview measurement: rejected candidate

The synthetic runner measurement observed all eight predicted changes and
passed four real-run controls. The first full gate found five TypeScript errors.
The registered correction removed those errors, and all 12 controls passed
again. The next full gate passed typecheck but failed Biome: the new test file
was not formatted as required. A focused Biome check reproduced that failure.

The correction prediction rejected the candidate on any full-gate failure.
Keep the candidate and private logs as evidence; do not present it as ready or
retry that correction as though it had passed. A new materially distinct
measurement design must be registered before implementation. The observations
are synthetic runner evidence, not proof of all CLI or installed-state effects.
