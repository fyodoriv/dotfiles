# Judge native asset preparation

## Boundary

The local #755 composition pins draft source `9db12ffc85591dddc75f38e7170c6ab0f7a60f25`
and main `24a3c6fbbd83b685fe142699eaf0d935f0e70406`. Its auto-merged
`publish-dist.rs` hashes to
`88e5367f3e70cf92ff6638c4e395712de5ce269654f0f5fff418b5caefbeb626`, which
is not the hash in main's checked-in prebuilt pair. That pair also contains no
judge reader. An ignored local target or old package is not source-bound proof.
Recheck these inputs when either parent changes.

The existing #764 contract fixes a verified checkup/publisher pair; do not
weaken its manifest, source allowlist, atomic publisher, no-Cargo path, or
compiler-error refusal. Investigate rebuilding that pair under its existing
recipe for the changed publisher and binding the judge reader through a
separate source-qualified receipt. This is a candidate boundary, not a claim
that a binary or clean source build is qualified.

## Synthetic preparation prediction

Goal: prepare a fail-closed capability decision before building or publishing
new assets. Question: can a bounded synthetic contract distinguish a complete,
compatible asset set from unsafe combinations? Predict **1/1** complete fixture
is admitted and **10/10** unsafe fixtures are refused, with zero execution of
fixture bytes, zero compiler calls on the absent-toolchain path and zero
predecessor mutation. The baseline is unmeasured.

The ten negative fixtures are: missing reader; changed reader source; changed
reader lockfile; changed publisher source; wrong architecture; corrupt bytes;
symlink; unsafe ownership or mode; mixed asset versions; and an available but
failing compiler. The last case must refuse rather than select prebuilt
fallback. Fixtures are synthetic and must not use ignored target binaries,
owner credentials, installed agent configuration or real production data.

Commit this prediction before adding the proposed test harness. The test-only
harness does not publish a real executable or alter #764's frozen cases.
Run the measurement from the composed Agentbrew worktree, after the file
exists. The JSON report must contain exactly eleven passed tests, zero failures,
skips or todos, and each named decision exactly once:

```sh
bash <<'BASH'
set -o pipefail
report=$(mktemp) || exit 2
trap 'rm -f "$report"' EXIT
test -f src/judges/native-assets-preparation.test.ts || exit 2
JOBS=1 heavy-run npm exec -- vitest run src/judges/native-assets-preparation.test.ts --maxWorkers=1 --reporter=json --outputFile="$report" || exit 1
node - "$report" <<'NODE'
const fs = require('node:fs');
const r = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const names = ['complete set admitted', 'missing reader refused', 'changed reader source refused', 'changed reader lockfile refused', 'changed publisher source refused', 'wrong architecture refused', 'corrupt bytes refused', 'symlink refused', 'unsafe ownership refused', 'mixed versions refused', 'compiler failure refused'];
const tests = r.testResults.flatMap((file) => file.assertionResults);
if (!r.success || r.numTotalTests !== 11 || r.numPassedTests !== 11 || r.numFailedTests !== 0 || r.numPendingTests !== 0 || r.numTodoTests !== 0 || tests.length !== 11) process.exit(1);
for (const name of names) {
  if (tests.filter((test) => test.fullName.endsWith(name) && test.status === 'passed').length !== 1) process.exit(1);
}
console.log('11 named synthetic decisions passed');
NODE
BASH
```

The pure test-only decision boundary must accept injected fake launcher,
compiler and publication adapters; source review must verify it has no other
process-launch path. The fixtures use non-executable synthetic bytes. Each test
checks recorded adapter calls and compares a private scratch predecessor's
bytes and hash before and after. A control canary first demonstrates that the
injected counters detect a call; the positive fixture then exercises the
absent-toolchain decision with zero launch/compile calls. The failing-compiler
fixture must observe its attempted compiler call and zero fallback calls. These
are synthetic assertions, not evidence about a real OS or toolchain.

Success requires all eleven decisions,
zero unsafe accepts, no skipped control and independent source review. Any
unsafe accept, missed valid fixture, fallback after compiler failure, changed
predecessor or missing guard rejects the synthetic contract. This preparation
does not resolve the #755 merge conflicts or prove a real no-Cargo build.

## Later qualification

Before a production verifier, builder or artifact change, register a separate
prediction with a concrete source-bound receipt, build recipe, exact inputs
and tests. Requalify the changed publisher pair and judge reader with two
independent clean, offline builds; bind source, lockfile, toolchain, target,
recipe and artifact hashes. Preserve #764's frozen controls, existing
architecture and ownership checks, private staged bytes, atomic publication,
three-target package coverage and binary privacy scan.

A real no-Cargo proof must establish that every resolver candidate, including
fixed Rustup and Homebrew locations, is unavailable in the isolated fixture,
and independently observe zero compiler launches. Do not alter the owner's
toolchain. A test double alone is not a clean-install proof. Missing asset,
source mismatch, wrong architecture, unsafe path, compiler failure or partial
publication must leave the predecessor intact. No unqualified binary may be
copied from a local target directory or downloaded at build time. The model
calibration and live connector remain separate issue #752 acceptance work.

Anchor: `docs/plans/source-build-prebuilt-764.md` on main; #755's judge reader
and publication contracts; Basili, Caldiera and Rombach (1994), Goal Question
Metric; Munafò et al. (2017), preregistration.

## First model rejected

On Nov 7, 2026, the 11 named synthetic tests reported 11 passes, zero
failures and zero skips. Independent source review found that the model did
not receive the checkup/publisher artifact pair. Its version control changed
one reader version against its own receipt rather than mixing independently
valid assets. The registered success condition required independent review,
so this model failed the gate. It cannot establish asset-set compatibility.
Its uncommitted file remains in the composed worktree as evidence; do not
ship it as the solution.

## Pivot: independently bound asset set

Before implementing a replacement, predict that a distinct decision model
which validates three independently described assets and their shared release
identity will accept 1/1 complete fixtures and reject 13/13 unsafe fixtures.
Each asset has its own bytes, source and lock bindings, architecture and
version. Checkup and publisher have independently checked entries in their
existing shared pair receipt; the reader has a separate receipt. The mixed-release fixture must use individually valid
receipts from different releases. A missing or corrupt pair member must fail.

Measure with a fresh report and an exact parser:

```sh
bash <<'BASH'
set -o pipefail
report=$(mktemp) || exit 2
trap 'rm -f "$report"' EXIT
test -f src/judges/native-assets-set.test.ts || exit 2
JOBS=1 heavy-run npm exec -- vitest run src/judges/native-assets-set.test.ts --maxWorkers=1 --reporter=json --outputFile="$report" || exit 1
node - "$report" <<'NODE'
const fs = require('node:fs');
const r = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const names = ['complete set', 'missing reader', 'changed reader source', 'changed reader lockfile', 'changed publisher source', 'wrong architecture', 'corrupt reader', 'symlink', 'unsafe ownership', 'mixed releases', 'compiler failure', 'missing checkup', 'missing publisher', 'corrupt publisher'];
const tests = r.testResults.flatMap((file) => file.assertionResults);
if (!r.success || r.numTotalTests !== 14 || r.numPassedTests !== 14 || r.numFailedTests !== 0 || r.numPendingTests !== 0 || r.numTodoTests !== 0 || tests.length !== 14) process.exit(1);
for (const name of names) {
  if (tests.filter((test) => test.fullName.endsWith(name) && test.status === 'passed').length !== 1) process.exit(1);
}
console.log('14 named synthetic asset-set decisions passed');
NODE
BASH
```

Use the fake adapter counter canary, require one observed failing compiler call
with zero fallback, and check scratch predecessor bytes and hash in every
case. Do not execute fixture bytes or launch a compiler on the absent path.

Success requires 14/14 and independent review of all three bindings. Any
unsafe acceptance, missed positive, skipped test or missing binding rejects
this approach. This remains a synthetic boundary, not an installation proof.
The GQM and preregistration anchors above apply.
