# Reviewer event controls: gate discovery

Goal: ensure the ordinary hook suite rejects missing or forged evidence from
the six synthetic event controls. Predict a new wrapper accepts both valid
Python report formats and rejects all five invalid report classes: nonzero
exit, missing case, skipped case, extra case and forged summary. The existing
classifier wrapper and gate remain unchanged. No live event is involved.

Before implementing the wrapper, add a shell gate test with six named modes:
`valid`, `nonzero`, `missing`, `skipped`, `extra`, and `forged`. The valid
mode checks both stock and newer unittest formats; forged checks conflicting
counts and a failed summary. Each invocation uses a private scratch HOME,
`env -i`, a fake `python3`, a one-line invocation sentinel and no network.
The gate test must print `not ok - valid: event wrapper missing` and exit 1
when the wrapper is absent. Before adding the wrapper run:

```sh
bash <<'BASH'
log=$(mktemp) || exit 2
trap 'rm -f "$log"' EXIT
[ ! -e hooks/checks/review-ask-event.test.sh ] || exit 2
JOBS=1 heavy-run bash hooks/checks/review-ask-event-gate.test.sh >"$log" 2>&1
result=$?
[ "$result" -eq 1 ] && [ "$(grep -Fxc 'not ok - valid: event wrapper missing' "$log")" -eq 1 ]
BASH
```

Then add the wrapper at
`hooks/checks/review-ask-event.test.sh`. Require exactly six ordered named
passes, one `Ran 6 tests` and one `OK`, zero skips, errors, duplicate or
conflicting summaries, and zero nonzero producer exits. The hook suite's
existing test discovery must run both shell files. Resolve the Python test
relative to the wrapper; fail on missing Python, test or report. Propagate
child and output failures. The extra/forged cases include duplicate result
lines and conflicting `Ran`, `OK` and `FAILED` summaries.
The case order is `failure_event_silent`, `input_is_not_disclosed`,
`interrupted_event_silent`, `malformed_event_silent`,
`matching_event_reminds`, `unrelated_command_silent`.

Measurement: run the self-checking gate oracle below, then the wrapper with
`JOBS=1 heavy-run bash hooks/checks/review-ask-event.test.sh`, then
`JOBS=1 heavy-run bash hooks/checks/review-request-classifier.test.sh`
and its `-gate.test.sh` counterpart. Success requires all six gate modes,
six adapter cases, 10 classifier cases and six original gate modes to pass,
followed by the ordinary unfiltered full gate and independent review. Any
accepted forged or incomplete report, undiscovered wrapper, changed old
contract or test failure rejects the approach.

```sh
bash <<'BASH'
log=$(mktemp) || exit 2
trap 'rm -f "$log"' EXIT
JOBS=1 heavy-run bash hooks/checks/review-ask-event-gate.test.sh >"$log" 2>&1 || exit 1
for mode in valid nonzero missing skipped extra forged; do [ "$(grep -Fxc "ok - $mode" "$log")" -eq 1 ] || exit 2; done
[ "$(grep -Ec '^ok - ' "$log")" -eq 6 ] && [ "$(grep -Fxc 'review ask event gate: 6 passed' "$log")" -eq 1 ]
BASH
```

Also run `JOBS=1 heavy-run bash scripts/run-hook-fixtures.sh` under its default
stock Bash 3.2 restricted PATH. Its log must contain exactly one successful
fixture line each for `hooks/checks/review-ask-event.test.sh` and
`hooks/checks/review-ask-event-gate.test.sh`, with no failed fixtures.

Anchor: the existing #851 gate contract; Basili, Caldiera and Rombach (1994),
Goal Question Metric; Munafò et al. (2017), preregistration.
