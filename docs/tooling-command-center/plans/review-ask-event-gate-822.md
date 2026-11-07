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
Run `JOBS=1 heavy-run bash hooks/checks/review-ask-event-gate.test.sh` first;
it must exit nonzero before the wrapper exists. Then add the wrapper at
`hooks/checks/review-ask-event.test.sh`. Require exactly six ordered named
passes, one `Ran 6 tests` and one `OK`, zero skips, errors, duplicate or
conflicting summaries, and zero nonzero producer exits. The hook suite's
existing test discovery must run both shell files.

Measurement: run the gate test and wrapper with `JOBS=1 heavy-run bash` for
each, then `JOBS=1 heavy-run bash hooks/checks/review-request-classifier.test.sh`
and its `-gate.test.sh` counterpart. Success requires all six gate modes,
six adapter cases, 10 classifier cases and six original gate modes to pass,
followed by the ordinary unfiltered full gate and independent review. Any
accepted forged or incomplete report, undiscovered wrapper, changed old
contract or test failure rejects the approach.

Anchor: the existing #851 gate contract; Basili, Caldiera and Rombach (1994),
Goal Question Metric; Munafò et al. (2017), preregistration.
