# Compiler decision oracle harness

## Goal and boundary

The existing compiler queue fixture has sealed observations and an independent
receipt oracle, but it does not pass those observations to a decision subject.
Prepare an in-process harness before writing a decision model. It accepts only
a trusted, test-owned callback. It is not a runner for arbitrary executables,
a process sandbox, or a live queue observer.

The harness reads the existing version-2 observations and passes only each
`observation` object to the callback: never its case ID or expected answer.
The harness owns the IDs and assembles the callback's responses into the
existing version-2 receipt. The existing oracle remains the independent
decision check. Freeze the observation file at SHA-256
`33ba1ee6adbdb3274cc96f41e22f6a6cdc37dce0c8bcb84551adb92ad84a6d02`.
Keep `receipts.rs` byte-for-byte at SHA-256
`a4f26621acb63fa9dd624e5a95a5b883eb8fff66328466b4ab9aee523f7829ba`
and `Cargo.lock` at
`2aff136bf2debabd4b723f6b1ef60133909293664dbc23303f6327ba1c6508cd`.
Keep `epoch.rs` byte-for-byte at
`1ecd705cd5bb35555adce034a011eb96479b46ff657b6caee05697740dcec3b7`.
The original manifest at revision `4a040d964fc7cb5134a5a7993a67781a17e6a99a`
has SHA-256 `a331c2000e774f1ba505b00697677bb7d47efb6f2cb0233a76c8a8c87ce0a231`.
The candidate manifest may add only the separate `compiler_queue_harness`
test target at `harness.rs`. The new target includes the unchanged oracle
source; it must not alter the oracle, existing target, dependencies or lock.

Each callback response is bytes containing exactly one JSON object with a
single `verdict` field. Its value must be `owned`, `outside`, or `unknown`.
Reject duplicate or extra fields, malformed JSON, invalid UTF-8, empty or
responses over 1,024 bytes, and callback errors. The harness must not print input or
response bytes. Its diagnostics use fixed reason labels and counts only.
The synthetic private-marker case is passed to the callback but must not
appear in a serialized receipt or a harness diagnostic.

## Registered controls

Run the harness on one deliberately ordered valid fixture callback. This is a
white-box positive control for the harness, not a candidate observer or proof
of independent reasoning. It must pass. Reject these twelve controls:

1. Always `unknown`.
2. Always `owned`.
3. Invalid JSON.
4. Duplicate `verdict` keys.
5. An extra response field.
6. A synthetic private marker in a response.
7. A callback error.
8. Invalid UTF-8.
9. An empty response.
10. A response longer than 1,024 bytes.
11. A verdict outside the three permitted values.
12. Valid JSON followed by trailing data.

An input-capture control checks that the callback sees all 24 observation
objects in order and no case IDs or expected outcomes. Preserve the existing
receipt mutation and epoch tests. Do not add a default fake subject that can
be mistaken for a production result. Missing a real subject stays non-green
for the task's decision criterion.

## Prediction and decision

Goal: enable independent measurement of synthetic ownership decisions.
Question: can the sealed observations reach a subject without leaking the
answer key, and can the existing oracle reject the specified bad outputs?
Predict **1 of 1** valid control accepted, **12 of 12** invalid controls
rejected, **24 of 24** observation inputs delivered without IDs or expected
answers, and zero synthetic marker bytes in serialized output or diagnostics.

After this registration lands, implement the harness and run:

```sh
printf '%s  %s\n' '33ba1ee6adbdb3274cc96f41e22f6a6cdc37dce0c8bcb84551adb92ad84a6d02' 'tests/fixtures/compiler-queue-observer/observations.json' 'a4f26621acb63fa9dd624e5a95a5b883eb8fff66328466b4ab9aee523f7829ba' 'tests/fixtures/compiler-queue-observer/receipts.rs' '2aff136bf2debabd4b723f6b1ef60133909293664dbc23303f6327ba1c6508cd' 'tests/fixtures/compiler-queue-observer/Cargo.lock' '1ecd705cd5bb35555adce034a011eb96479b46ff657b6caee05697740dcec3b7' 'tests/fixtures/compiler-queue-observer/epoch.rs' | shasum -a 256 -c && python3 - <<'PY' && heavy-run cargo test --offline --locked --manifest-path tests/fixtures/compiler-queue-observer/Cargo.toml
import hashlib, pathlib, subprocess, tomllib
path = 'tests/fixtures/compiler-queue-observer/Cargo.toml'
original = subprocess.check_output(['git', 'show', '4a040d964fc7cb5134a5a7993a67781a17e6a99a:' + path])
assert hashlib.sha256(original).hexdigest() == 'a331c2000e774f1ba505b00697677bb7d47efb6f2cb0233a76c8a8c87ce0a231'
expected = tomllib.loads(original.decode())
expected['test'].append({'name': 'compiler_queue_harness', 'path': 'harness.rs'})
assert tomllib.loads(pathlib.Path(path).read_text()) == expected
print('original manifest plus registered harness target: verified')
PY
```

Success requires every count above, unchanged sealed input, and passing
existing fixture controls. Any accepted invalid response, missing input,
answer-key exposure, marker output, or existing regression rejects the
harness; change the measurement boundary rather than weaken a control.
Land this preparation and review it before testing any candidate decision
model. A later model needs its own prediction and measurement. This in-process
check does not establish real process output, capture authority, live queue
ownership, race safety, or a production false-positive rate.

Anchor: [compiler observation protocol](compiler-queue-observation.md);
Basili, Caldiera and Rombach (1994), Goal Question Metric; Munafò et al.
(2017), preregistration.
