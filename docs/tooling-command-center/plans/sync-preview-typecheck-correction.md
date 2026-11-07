# Register preview harness type correction

The first full Agentbrew gate stopped at typecheck. The compiler reported four
`TS2339` errors for `.default` on typed Node built-in module namespaces and one
`TS2322` for assigning `process.exitCode` to an overly narrow type. A separate
`JOBS=1 heavy-run npx tsc --noEmit` reproduced all five. The 12 runtime cases
passed before this correction.

Goal: make the measured harness typecheck without weakening its sentinels.
Question: do using the built-in module namespace as the mock default and the
actual exit-code type remove the errors? Predict five reported errors become
zero under `JOBS=1 heavy-run npx tsc --noEmit`, while the exact 12 named cases
still pass under the registered focused command and verbose name check. Any
remaining compiler error, changed or missing case, sentinel failure, or full
gate failure rejects this correction. Retain the red and green logs and request
independent review. This does not claim a production sync fix.

Anchor: the repository's TypeScript gate; Basili, Caldiera and Rombach (1994),
Goal Question Metric; Munafò et al. (2017), preregistration.
