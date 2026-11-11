# Register the ownership-model TAP reporter

The first Node test run reported 11 passes in Node's default spec format. The
registered checker expected TAP and failed to parse that output. The test
process exited zero, but the required machine-checked evidence is missing;
treat that run as inconclusive.

Goal: obtain the registered exact-name evidence without changing the model.
Question: does Node's explicit TAP reporter expose all 11 unchanged synthetic
cases to the checker? Predict exactly 11 ordered named passes, zero failures,
skips or TODOs, and an unchanged source hash. Measure with
`NODE_OPTIONS=--test-reporter=tap JOBS=1 heavy-run node --test scripts/updates-landed-ownership-model.test.mjs`.
Machine-check the TAP plan, names, counts and skip/TODO fields; the checker
must itself exit nonzero on failure. Any missing, duplicate or wrong case,
changed source, failed checker, test failure or unsafe action rejects this
reporting approach. Setup failure remains inconclusive. The original model
and operating-system limitations in `3bb4fd0` and `8c122c0` remain unchanged.

Anchor: Node's local `--help` and `process.allowedNodeEnvironmentFlags` for
`--test-reporter`; Basili, Caldiera and Rombach (1994), Goal Question Metric;
Munafò et al. (2017), preregistration.
