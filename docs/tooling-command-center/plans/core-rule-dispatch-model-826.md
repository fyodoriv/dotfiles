# Core-rule dispatch: synthetic single-dispatcher model

The earlier per-plugin aggregate design was rejected after two modeled hooks
delivered the same body twice. Explore a distinct design: one shared dispatcher
receives a trusted, complete snapshot of enabled and eligible plugins and
selects each referenced core ID once. This test-only model neither reads nor
writes settings, installs hooks, starts agents, or asserts that such a trusted
snapshot exists. It does not qualify live delivery.

Goal: distinguish modeled selection from cases with insufficient evidence.
Predict 10/10 synthetic controls pass, with zero duplicate IDs or false
modeled-success classifications. In a test-only helper, return a sorted unique
ID list only when the snapshot is explicitly trusted and complete, the session
ID is nonempty, exactly one new dispatcher is present, no legacy dispatcher is
present, and that dispatcher is modeled as having completed. Otherwise return
`unqualified`. A completed dispatcher with no enabled eligible plugins yields
an empty list, not a failure. Do not infer actual enabled state, session
identity, output receipt, hook scheduling, or crash recovery from this model.
Require exact booleans for trusted, complete, enabled, eligible and completed;
missing or malformed fields are unqualified. Session IDs must be nonblank
strings. Rule IDs and known IDs must be valid nonempty strings. Reject invalid
arrays or records rather than treating them as empty or disabled. Dispatcher
counts other than one are unqualified.
Legacy-hook presence must also be an exact boolean, and plugin IDs must be
nonblank strings; malformed values are unqualified.

Freeze these 10 named controls in
`src/plugins/core-rule-dispatch-model.test.ts` before implementing the helper:
`two eligible share rule`, `disabled former owner`, `all disabled`, `separate
sessions`, `missing session`, `untrusted snapshot`, `legacy coexistence`,
`dispatcher failure`, `unknown eligible rule`, and `conflicting plugin ids`.
The first uses two enabled eligible synthetic plugins requesting the same known
ID and expects that ID once. The second disables the first plugin and requires
the other plugin's ID. The third expects an empty list. The fourth evaluates
two independent synthetic session IDs. The fifth and sixth require
`unqualified` for missing identity or untrusted/incomplete snapshot. The seventh
requires `unqualified` when a legacy per-plugin hook might also run. The eighth
requires `unqualified` when the sole dispatcher fails before completion. The
ninth requires `unqualified` for an eligible unknown ID. The tenth requires
`unqualified` for duplicate plugin IDs with conflicting data. Assert that the
deep-frozen input object is unchanged in every case, including unqualified
paths. Fold zero and two dispatcher counts into the seventh case, malformed
types, including the legacy flag, into the fifth through seventh, invalid
rule/known-ID values into the ninth, and invalid plugin IDs into the tenth.
No file or settings mutation is part of the helper.

Before the helper, the first named case must fail against a test-only
placeholder with the assertion diagnostic `dispatcher placeholder`. After
implementation use the exact JSON oracles below. Each
oracle requires the expected named status, and green requires exactly 10
passed, zero failed or pending tests. Preserve the green qualification report
privately if a control fails. Any duplicate selected ID, false success on an unqualified case,
input mutation, process or network call, or missing case rejects this model.
Process/network absence is source-reviewed only, not a measured sandbox claim.
An independent source review is required. Gate discovery and any production
integration need separate registration.

```sh
bash <<'BASH'
receipt=$(mktemp) || exit 2
trap 'rm -f "$receipt"' EXIT
JOBS=1 heavy-run npm exec -- vitest run src/plugins/core-rule-dispatch-model.test.ts --maxWorkers=1 -t 'two eligible share rule' --reporter=json --outputFile="$receipt" >/dev/null 2>&1
result=$?
[ "$result" -ne 0 ] || exit 2
node - "$receipt" <<'NODE'
const d = JSON.parse(require('node:fs').readFileSync(process.argv[2], 'utf8'));
const t = d.testResults.flatMap(x => x.assertionResults).filter(x => x.title === 'two eligible share rule');
if (t.length !== 1 || t[0].status !== 'failed' || !(t[0].failureMessages || []).join('\n').includes('dispatcher placeholder')) process.exit(2);
NODE
BASH
```

```sh
bash <<'BASH'
umask 077
receipt=$(mktemp) || exit 2
trap 'result=$?; if [ "$result" -eq 0 ]; then rm -f "$receipt"; else printf "failed report retained: %s\n" "$receipt" >&2; fi' EXIT
JOBS=1 heavy-run npm exec -- vitest run src/plugins/core-rule-dispatch-model.test.ts --maxWorkers=1 --reporter=json --outputFile="$receipt" >/dev/null 2>&1 || exit 1
node - "$receipt" <<'NODE'
const d = JSON.parse(require('node:fs').readFileSync(process.argv[2], 'utf8'));
const expected = ['two eligible share rule', 'disabled former owner', 'all disabled', 'separate sessions', 'missing session', 'untrusted snapshot', 'legacy coexistence', 'dispatcher failure', 'unknown eligible rule', 'conflicting plugin ids'];
const results = d.testResults.flatMap(x => x.assertionResults);
if (!d.success || d.numPassedTests !== 10 || d.numFailedTests !== 0 || d.numPendingTests !== 0 || results.length !== 10) process.exit(2);
for (const name of expected) { const rows = results.filter(x => x.title === name); if (rows.length !== 1 || rows[0].status !== 'passed') process.exit(2); }
NODE
BASH
```

Before any real implementation, qualify settings precedence and explicit user
disable choices, preservation of user-owned hooks/settings, the supported
session identity and resume semantics, atomic migration from old hooks, and
what proves successful delivery. Existing native sync rewrites its own enable
flags, so the local settings file alone is not proven authoritative.

Anchors: [Claude Code hooks](https://code.claude.com/docs/en/hooks), which
documents parallel matching hooks and separate plugin copies; Basili, Caldiera
and Rombach (1994), Goal Question Metric; Munafò et al. (2017), preregistration.

The ten original controls passed. Independent review then identified sparse
arrays as a missing malformed-input case. A focused reproduction failed twice:
sparse known IDs and sparse plugin-rule IDs were classified as modeled instead
of unqualified. This meets the registered false-success pivot. Preserve the
uncommitted model and `/tmp/core-dispatch-sparse-red.log`; do not qualify a
later patch to this approach as success. Register a distinct design first.
