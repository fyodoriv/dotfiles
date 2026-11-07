# Scoped core-rule references

Issue #826 asks for core opt-in rules without copying their text. Promoting all
six globally changes every user's rules, including rules with different
approval policies. The proposed alternative is an explicit plugin manifest
reference resolved from the base catalog when `agentbrew plugin rules` serves
an eligible session. It must use the existing signed-lock, repository and
agent boundaries; it must not write the rule to shared state.

Goal: deliver a requested core rule to an eligible session without widening
scope. Predict the positive control improves from zero to one canonical rule
body and every negative scope control produces zero bodies. Measure 12
isolated controls in `src/plugins/core-rule-references.test.ts`, using the
existing signed `pluginFixture`, scratch HOME and public synthetic repo IDs:

1. One trusted, locked plugin scoped to `git.example.com/team/**`, with
   `capabilities.agents: [claude]`, `capabilities.core_rules:
   [pr-evidence-labels]` and `contributes.enableRules: [pr-evidence-labels]`, returns the
   current base catalog body exactly once for `claude-code` in that repo.
2. The same plugin returns no body for a non-matching or unknown repository.
3. The same plugin returns no body for an undeclared agent.
4. A tampered checkout contributes nothing after lock drift.
5. Removing the plugin removes the referenced body.
6. Two eligible trusted plugins referencing the same core ID return its body
   once, not twice.
7. An eligible plugin with both a valid and a declared unknown core ID fails
   explicitly and produces no partial plugin block; no unknown text is treated
   as a rule.
8. An ineligible plugin with a syntactically valid, capability-declared unknown
   ID neither reveals its ID nor blocks another eligible plugin. Excludes
   override includes; public hosts and unknown repositories remain denied.
9. A requested ID absent from `capabilities.core_rules`, or references without
   declared agents, are refused. A local rule still renders unchanged and no
   shared-rules file is written.
10. Duplicate, empty, non-string or otherwise malformed IDs fail manifest
    validation. An existing manifest without the new fields remains valid.
11. A signed update previews added and removed core IDs, including an added
    reference already declared in the unchanged capability list. A capability
    change still requires its separate approval even with `--yes`; approved
    update and rollback restore the correct references and bodies.
12. The real `plugin rules --agent ... --cwd ...` handler prints the eligible
    canonical body for a signed scratch plugin and an actual scratch git repo.
    Separately assert the supported SessionStart hook invokes that command.
    Agents without a session hook remain unsupported.

Pin the names as `eligible core rule`, `repository scope`, `agent scope`,
`lock drift`, `removal`, `deduplicate references`, `unknown eligible`,
`unknown ineligible`, `undeclared capability`, `malformed references`,
`update approval and rollback`, and `cli session path`. The positive fixture
has no rules directory, so it checks the existing early-return boundary.
Before code changes, run the positive with the JSON reporter and require one
named failure containing both `Invalid plugin manifest` and `additional
properties`. Save this output privately. Register the exact self-checking red
and green commands before adding tests.

```sh
bash <<'BASH'
receipt=$(mktemp) || exit 2
trap 'rm -f "$receipt"' EXIT
JOBS=1 heavy-run npm exec -- vitest run src/plugins/core-rule-references.test.ts --maxWorkers=1 -t 'eligible core rule' --reporter=json --outputFile="$receipt" >/dev/null 2>&1
result=$?
[ "$result" -ne 0 ] || exit 2
node - "$receipt" <<'NODE'
const fs = require('node:fs');
const data = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const matches = data.testResults.flatMap(x => x.assertionResults).filter(x => x.title === 'eligible core rule');
const message = matches.flatMap(x => x.failureMessages || []).join('\n');
if (matches.length !== 1 || matches[0].status !== 'failed' || !message.includes('Invalid plugin manifest') || !message.includes('additional properties')) process.exit(2);
NODE
BASH
```

Extend the manifest schema with `contributes.enableRules` and an explicit
`capabilities.core_rules` list. The requested IDs must be a subset of the
declared list and agents must be declared. The capability list participates in
the existing capability hash and separate update approval. Show reference
additions and removals in the update preview. Resolve only against the trusted
base catalog after active-plugin, repository and agent checks. Use the
catalog's current `content`, not copied or overlay-provided text. Unknown IDs
in an eligible plugin fail explicitly before returning a partial block.
Catalog existence is checked only after eligibility. Ineligible plugins must
not block or reveal their references. Deduplicate
eligible core IDs deterministically across plugins. Do not mutate installed or
global rule state or change any existing plugin's scope.

After implementation run the registered exact named-result oracle for the new
file, then
`JOBS=1 heavy-run npm exec -- vitest run src/plugins/capabilities.test.ts src/plugins/plugins.test.ts src/plugins/update.test.ts src/plugins/claude-native.test.ts src/team/overlay-contract-baseline.test.ts --maxWorkers=1`,
then the ordinary unfiltered full gate and independent review. Success requires
12/12 new controls, one canonical body in the positive, zero unsafe scoped
outputs, no shared-state writes, existing plugin and signature controls green,
and the full gate. Any unauthorized output, copied/stale core text, silent
unknown ID, duplicate body or broken existing plugin contract rejects this
approach. The CLI/session-start path must also be exercised in a test before
claiming the issue closed; a helper-only pass is not delivery proof.

```sh
bash <<'BASH'
receipt=$(mktemp) || exit 2
trap 'rm -f "$receipt"' EXIT
JOBS=1 heavy-run npm exec -- vitest run src/plugins/core-rule-references.test.ts --maxWorkers=1 --reporter=json --outputFile="$receipt" >/dev/null 2>&1 || exit 1
node - "$receipt" <<'NODE'
const fs = require('node:fs');
const data = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const expected = ['eligible core rule', 'repository scope', 'agent scope', 'lock drift', 'removal', 'deduplicate references', 'unknown eligible', 'unknown ineligible', 'undeclared capability', 'malformed references', 'update approval and rollback', 'cli session path'];
const results = data.testResults.flatMap(x => x.assertionResults);
if (results.length !== expected.length || data.numFailedTests !== 0 || data.numPendingTests !== 0 || data.numPassedTests !== expected.length || !data.success) process.exit(2);
for (const name of expected) {
  const matches = results.filter(x => x.title === name);
  if (matches.length !== 1 || matches[0].status !== 'passed') process.exit(2);
}
NODE
BASH
```

Anchors: the existing plugin lock/scope contract and #826 acceptance; Basili,
Caldiera and Rombach (1994), Goal Question Metric; Munafò et al. (2017),
preregistration.
