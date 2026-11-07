# Register raw-JSON discovery model

The earlier uncommitted guard proposal is not qualified: Bash command substitution can discard NUL bytes before its exact
comparison. Tool-executor interpretation of malformed or ambiguous JSON has
not been established. Do not add an allowance to the production hook yet.

Goal: prepare a conservative, test-only raw-input decision model. Question:
can a standard-library JSON parser recognize two exact synthetic probes while
refusing every frozen ambiguous input without executing it? Predict **2/2**
exact probes return `allow`, **28/28** unsafe or unsupported inputs return
`fallback`, and **zero** fixture commands run. `fallback` means no new
allowance; it is not a claim that the existing guard blocks the input. This
model is not production enforcement or proof of executor parity.

After this prediction is committed, add a Bats black-box suite at
`tests/heavy-run-discovery-json.bats` and a test-only Python standard-library
model under `tests/fixtures/`. The model reads raw stdin bytes, writes only
`allow` or `fallback`, and never executes decoded content. Read at most 65,537
bytes and reject inputs over 65,536. Return exactly `fallback` on parser or
resource errors, including recursion depth and oversized numeric literals.
Reject invalid UTF-8, malformed or trailing JSON, duplicate keys at any object
depth, non-standard numeric constants, unpaired surrogates and NUL in any
string. Reject numeric literals longer than 128 characters. Require a top-level
object with a `tool_input` object and a
string `command`. Allow only the exact two decoded command strings below:
`command -v bats` and `command -v bats\ncommand -v greadlink` (the latter
contains one actual newline). All other inputs fall back. The model must not
read real user config, call subprocesses, contact a network or persist input.

Freeze these independently asserted controls. They are raw JSON bytes, not
shell commands to execute. Each case must assert exactly one fixed result and
no dispatch marker:

- P01: the exact single probe; P02: the exact two-line probe. Both allow.
- N01–N04: `\u0000` respectively before, inside and after the single probe,
  and between it and `; bats`.
- N05: a raw NUL byte in JSON. N06–N07: duplicate `command` keys with unsafe
  then safe values, and safe then unsafe values.
- N08–N09: duplicate `tool_input` objects with unsafe then safe commands, and
  safe then unsafe commands. N10: a duplicate key in an unrelated nested object.
- N11: malformed JSON. N12: two JSON documents in one input. N13: a top-level
  array. N14: missing command. N15: a non-string command.
- N16: `command -v bats && bats`. N17: `$(command -v bats)`. N18: the two
  probes with CRLF rather than LF. N19: a literal backslash-u sequence, not a
  decoded NUL, added to the probe. N20: a 65,537-byte input. N21: invalid
  UTF-8. N22: a non-standard `NaN` value. N23: a lone surrogate escape in a
  JSON string. N24: a whitespace-altered probe. N25: `heavy-run bats`.
  N26: `bats tests/fixture.bats`. N27: 2,000 nested JSON arrays in an otherwise
  valid object containing the allowed single probe, after confirming the
  isolated interpreter's recursion limit is below 2,000. N28: a 129-digit
  numeric literal in an otherwise valid object containing that same allowed
  probe. All return fallback.

Run the resolved Python executable with `-I -S` and a clean scratch HOME, config
and temporary directory. Record its resolved path and version privately.
Include a synthetic `sitecustomize.py` that creates a scratch canary. First run
a separate positive control without `-I` or `-S` and prove it creates that
canary; remove only that canary. Then run with `-I -S` and the same synthetic
`PYTHONPATH` and prove the canary stays absent.
No real user configuration or environment data is passed to the model.

Name the Bats cases exactly P01, P02, then N01 through N28. First add only
P01 with a deliberately unimplemented model that returns
`fallback`. The red command must exit 1 for the named test and emit the fixed
diagnostic `expected exact discovery allow`, not a setup error:

```sh
log=$(mktemp)
set +e
JOBS=1 heavy-run bats --filter '^P01$' tests/heavy-run-discovery-json.bats > "$log" 2>&1
result=$?
set -e
[ "$result" -eq 1 ]
grep -Fxq 'not ok 1 P01' "$log"
grep -Fq 'expected exact discovery allow' "$log"
printf 'Private red log: %s\n' "$log"
```

Then implement the model and remaining individually named controls. Run:

```sh
set -e
log=$(mktemp)
JOBS=1 heavy-run bats tests/heavy-run-discovery-json.bats > "$log" 2>&1
grep -Fxq '1..30' "$log"
[ "$(grep -Ec '^1\.\.[0-9]+$' "$log")" -eq 1 ]
[ "$(grep -Ec '^ok [0-9]+ ' "$log")" -eq 30 ]
i=0
for id in P01 P02 N01 N02 N03 N04 N05 N06 N07 N08 N09 N10 N11 N12 N13 N14 N15 N16 N17 N18 N19 N20 N21 N22 N23 N24 N25 N26 N27 N28; do
  i=$((i + 1))
  grep -Fxq "ok $i $id" "$log"
done
! grep -Eiq '(^not ok|# (skip|todo))' "$log"
printf 'Private focused log: %s\n' "$log"
cache=$(mktemp -d)
CACHED_RUN_DIR="$cache" JOBS=1 heavy-run make check BATS_JOBS= TEST_FILE_JOBS=
```

Require exactly one `1..30` TAP plan and exactly 30 `ok` results, in order:
P01, P02, then N01 through N28. Require no `not ok`, skip or TODO, 2/2 exact
allows, 28/28 fallbacks, no fixture dispatch, and the fresh repository gate.
Save the exact selected-file list, require the new suite to run fresh,
compare selection to per-file results, and hash all candidate files before
and after. Record platform skips separately. Any wrong allowance, incorrect
fallback, duplicate/missing case, fixture dispatch, missing selected suite or
gate failure rejects the model. Setup failure is inconclusive; preserve the
outcome and redesign rather than narrowing the corpus. Independently review
fixtures, input boundary, full gate and final commit.

The existing guard remains untouched. Before any production integration,
separately qualify the real tool's JSON/executor contract, parser availability,
boundedness, lifecycle, failure behavior and runtime cost. A missing parser
must not grant the new allowance. A model fallback does not prove the current
guard handles arbitrary ambiguous shell text safely.

Anchor: observed Nov 7 queue-guard refusal; JSON RFC 8259 sections 4 and 8;
Basili, Caldiera and Rombach (1994), Goal Question Metric; Munafò et al.
(2017), preregistration.
