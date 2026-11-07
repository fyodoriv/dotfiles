# Compiler queue synthetic decision model

## Goal and boundary

The sealed observation fixture and independent receipt oracle can now exercise
a trusted in-process callback. Prepare a pure decision model for that fixture.
The model receives only an observation object and returns one bounded verdict
response. It must not read case IDs, answer keys, fixture order, fixture files,
private records, environment values, or live processes.

This is synthetic preparation for `compiler-queue-observation`, not a live
observer. Its booleans and identity records are supplied fixture assertions,
not proof that the operating system or queue actually supplied them. Live
capture, reservation authority, epoch coherence, process output and deployed
privacy remain separate unqualified boundaries.

## Independent holdout

Before implementation, an independent reviewer will prepare eight synthetic
holdout cases and expected outcomes from the existing protocol: two owned, two
outside, and four unknown. The reviewer retains the bytes independently and
shares only their SHA-256 before implementation. Land that hash in a follow-up
registration before any subject code or baseline run. The reviewer must confirm
that the cases contain only synthetic values, follow the protocol, and exercise
boundaries beyond the original receipt controls. Reveal the bytes only after
the candidate source is committed. Reject a hash mismatch; do not change the
holdout after the first candidate result. This is an independent-review
boundary, not a claim of operating-system isolation from the same user.

## Prediction and decision

Goal: determine whether the proposed pure decision boundary handles its
registered synthetic inputs safely. Question: does one general rule set match
the independent oracle without turning unknown evidence into ownership or an
outside verdict? Predict **24 of 24** original decisions and **8 of 8** holdout
decisions correct, with zero false-owned or false-outside results and zero
synthetic private-marker bytes in serialized results or diagnostics.

Success requires every case, every retained harness control, unchanged frozen
inputs and oracle, and independent source review. Any wrong decision, private
marker in output, missing case, changed fixture or safety regression rejects
the model approach. Preserve the failed result; do not change cases or lower
the threshold to make it pass. Setup failures are inconclusive, not a model
result. An initial deliberately unimplemented callback is a red harness
control, not a candidate model attempt.

The original observations, receipt oracle, epoch tests, lockfile and harness
must remain byte-for-byte unchanged from revision
`a984de1c7d3673cd7b6f201d88178e067c6ed9e3`. Its manifest may add only a
`compiler_queue_decision` test target at `decision_tests.rs`. An independent
reviewer checks that the model does not encode case identities, expected
answers or fixture-specific process identities.

## Measurement

After this prediction and the hash-only registration land, add an unimplemented
callback and run the original-case test as a red control. Implement the
candidate, run that same original-case test, and commit the candidate source.
Record its full SHA with the independent reviewer. Only then reveal the exact
holdout bytes and run the complete measurement from
the repository root. The hash-only registration landed at
`d377204da6e1b9305552119251f8bbfb7c411ba4`, before subject code. The
measurement binds that immutable commit in the command below.

The red control uses a callback that returns an explicit error. The named test
must run and fail with the fixed `subject_error` reason. A compilation error,
missing test, panic before the decision, or any other failure is inconclusive:

```sh
bash <<'BASH'
set -o pipefail
log=$(mktemp) || exit 2
trap 'rm -f "$log"' EXIT
fixture_dir=tests/fixtures/compiler-queue-observer
shasum -a 256 "$fixture_dir/decision.rs" "$fixture_dir/decision_tests.rs" || exit 2
heavy-run cargo test --offline --locked --manifest-path tests/fixtures/compiler-queue-observer/Cargo.toml --test compiler_queue_decision -- --exact sealed_decisions_match --show-output --test-threads=1 2>&1 | tee "$log"
test_status=${PIPESTATUS[0]}
[ "$test_status" -eq 101 ] && grep -Fxq 'running 1 test' "$log" && grep -Fxq 'test sealed_decisions_match ... FAILED' "$log" && grep -Fq 'sealed decision test rejected: subject_error' "$log"
BASH
```

For the candidate's pre-disclosure test, select that same one named test. It
prints the fixed count only after checking all original cases:

```sh
bash <<'BASH'
set -o pipefail
log=$(mktemp) || exit 2
trap 'rm -f "$log"' EXIT
heavy-run cargo test --offline --locked --manifest-path tests/fixtures/compiler-queue-observer/Cargo.toml --test compiler_queue_decision -- --exact sealed_decisions_match --show-output --test-threads=1 2>&1 | tee "$log" || exit 1
grep -Fxq 'running 1 test' "$log" && grep -Fxq 'sealed: 24/24' "$log" && grep -Fxq 'test sealed_decisions_match ... ok' "$log"
BASH
```

After the candidate is committed and the holdout is revealed, export
`CANDIDATE_COMMIT` as the
full pre-disclosure candidate SHA. Then run:

```sh
bash <<'BASH'
check_inputs() {
  printf '%s  %s\n' '33ba1ee6adbdb3274cc96f41e22f6a6cdc37dce0c8bcb84551adb92ad84a6d02' 'tests/fixtures/compiler-queue-observer/observations.json' 'a4f26621acb63fa9dd624e5a95a5b883eb8fff66328466b4ab9aee523f7829ba' 'tests/fixtures/compiler-queue-observer/receipts.rs' '1ecd705cd5bb35555adce034a011eb96479b46ff657b6caee05697740dcec3b7' 'tests/fixtures/compiler-queue-observer/epoch.rs' '2aff136bf2debabd4b723f6b1ef60133909293664dbc23303f6327ba1c6508cd' 'tests/fixtures/compiler-queue-observer/Cargo.lock' 'c78b9edd9ed8d4a5e52c2c3aba027f9ca2c14f9ba0724ddc5a6bf487219862fe' 'tests/fixtures/compiler-queue-observer/harness.rs' | shasum -a 256 -c || return 1
  hash=$(git show "$HOLDOUT_COMMIT:docs/plans/compiler-queue-holdout.sha256") || return 1
  printf '%s\n' "$hash" | LC_ALL=C grep -Eq '^[0-9a-f]{64}$' || return 1
  printf '%s  %s\n' "$hash" 'tests/fixtures/compiler-queue-observer/decision-holdout.json' | shasum -a 256 -c || return 1
  for path in tests/fixtures/compiler-queue-observer/decision.rs tests/fixtures/compiler-queue-observer/decision_tests.rs tests/fixtures/compiler-queue-observer/Cargo.toml; do
    git cat-file -e "$CANDIDATE_COMMIT:$path" || return 1
  done
  git diff --quiet "$CANDIDATE_COMMIT" -- tests/fixtures/compiler-queue-observer/decision.rs tests/fixtures/compiler-queue-observer/decision_tests.rs tests/fixtures/compiler-queue-observer/Cargo.toml || return 1
  python3 - <<'PY'
import hashlib, pathlib, subprocess, tomllib
path = 'tests/fixtures/compiler-queue-observer/Cargo.toml'
base = subprocess.check_output(['git', 'show', 'a984de1c7d3673cd7b6f201d88178e067c6ed9e3:' + path])
assert hashlib.sha256(base).hexdigest() == 'f36be60c6fed71dc1ddbcf43873f0bcdb67957d4373d2ee63be30208d8a51823'
expected = tomllib.loads(base.decode())
expected['test'].append({'name': 'compiler_queue_decision', 'path': 'decision_tests.rs'})
assert tomllib.loads(pathlib.Path(path).read_text()) == expected
print('original manifest plus registered decision target: verified')
PY
}
: "${CANDIDATE_COMMIT:?set to the full pre-disclosure candidate commit}"
[[ "$CANDIDATE_COMMIT" =~ ^[0-9a-f]{40}$ ]] || exit 2
HOLDOUT_COMMIT=d377204da6e1b9305552119251f8bbfb7c411ba4
[[ "$HOLDOUT_COMMIT" =~ ^[0-9a-f]{40}$ ]] || exit 2
git merge-base --is-ancestor "$HOLDOUT_COMMIT" "$CANDIDATE_COMMIT" || exit 2
set -o pipefail
log=$(mktemp) || exit 2
trap 'rm -f "$log"' EXIT
check_inputs || exit 2
heavy-run cargo test --offline --locked --manifest-path tests/fixtures/compiler-queue-observer/Cargo.toml -- --show-output --test-threads=1 2>&1 | tee "$log"
test_status=$?
check_inputs || exit 2
grep -Fxq 'sealed: 24/24' "$log" || exit 2
grep -Fxq 'holdout: 8/8' "$log" || exit 2
grep -Fxq 'test sealed_decisions_match ... ok' "$log" || exit 2
grep -Fxq 'test holdout_decisions_match ... ok' "$log" || exit 2
exit "$test_status"
BASH
```

The test must feed observations, not case IDs, to the subject. It must check
the original fixture through the existing receipt oracle and separately check
all holdout answers without printing inputs or raw response bytes. Verify the
five fixed source hashes and the independently registered holdout hash before
and after the run. Bind the subject, driver and manifest to the recorded
candidate commit before and after the run. A missing hash, input or named test
makes the measurement inconclusive, not green. The independent reviewer
verifies the candidate commit before revealing the holdout.

Anchor: [compiler observation protocol](compiler-queue-observation.md);
Basili, Caldiera and Rombach (1994), Goal Question Metric; Munafò et al.
(2017), preregistration.
