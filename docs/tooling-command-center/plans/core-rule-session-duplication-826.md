# Core-rule session duplication: synthetic observation

Independent review found that each native plugin installs the same aggregate
SessionStart command. The current #826 renderer deduplicates within one call,
but that does not establish one delivery across multiple hooks. Measure this
before selecting a repair. The current candidate is unshipped.

Freeze the candidate's SHA-256 identities before this observation:

- `src/plugins/contributions.ts`: `fcf1d10939f24fc31b11f44a7d42e91ded673617efe073ae56779f06fedb089d`
- `src/plugins/agentbrew-plugin.schema.json`: `6736836c734029514f003e04ae9699854abb2c7df0e161621534e5b3a02fa17a`
- `src/plugins/capabilities.ts`: `374a897a1d455f638f45957b07546e7da460a55d267120e764fccd100205b271`
- `src/plugins/update.ts`: `4b79f4057788ea1f9c70989ea4f681b6bad3aa13a4a9e2b6f22f4b79a77cea84`
- `src/plugins/claude-native.ts`: `51334be5fb1f8c7fe97f8696cac239151818f0008bfe40c5522bb127a456caf6`
- `src/plugins/cli-plugin.ts`: `43622ce8c271cc830e52df4e9f94c5ff5b3a78e2934e87ecfa245a99836fde1a`

Prediction: two eligible signed scratch plugins, each referencing the same
core rule, produce two identical aggregate SessionStart commands. Calling the
real CLI handler once for each emitted command produces two copies of the
canonical body in total. Measure one named test in
`src/plugins/core-rule-session-controls.test.ts` using a scratch HOME, local
signed plugin fixtures, an actual scratch git repo, and captured CLI output.
Inspect both generated hook files, require exactly two generated commands and
their exact command text, and invoke the same handler twice with the
corresponding agent and repo. Capture the outputs independently and require
each contains the canonical body once. Do not launch a real
agent session or contact a remote service. Preserve the actual count privately.

Before the observation verify all six hashes above. Then run this exact
oracle; it accepts the predicted count only, not a fabricated empty result:

```sh
bash <<'BASH'
receipt=$(mktemp) || exit 2
trap 'rm -f "$receipt"' EXIT
JOBS=1 heavy-run npm exec -- vitest run src/plugins/core-rule-session-controls.test.ts --maxWorkers=1 --reporter=json --outputFile="$receipt" >/dev/null 2>&1 || exit 1
node - "$receipt" <<'NODE'
const fs = require('node:fs');
const data = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const tests = data.testResults.flatMap(x => x.assertionResults);
if (!data.success || data.numPassedTests !== 1 || data.numFailedTests !== 0 || data.numPendingTests !== 0 || tests.length !== 1 || tests[0].title !== 'two session hooks repeat aggregate' || tests[0].status !== 'passed') process.exit(2);
NODE
BASH
```

If the predicted two copies occur, the earlier candidate meets its duplicate
rejection threshold. Preserve it and register a distinct session-level design
before implementation or a new before/after measurement. If the observation
does not match, stop and inspect the exact evidence; do not claim either
delivery or deduplication. The control models two generated invocations; it
does not prove how a particular live agent dispatches them.

Anchors: #826's scoped-rule contract; Basili, Caldiera and Rombach (1994),
Goal Question Metric; Munafò et al. (2017), preregistration.
