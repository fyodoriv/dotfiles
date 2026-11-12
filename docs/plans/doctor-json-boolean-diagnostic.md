# Doctor boolean test diagnostic prediction

Registered before changing the test on 2026-11-12 after hosted PR #600
expected `fixed` at `tests/doctor-json-status.bats:131` but did not report the
actual value. The same isolated test passed on the owner Mac. The cause of the
hosted failure is unknown.

Hypothesis: a bounded diagnostic will distinguish an empty, known alternate,
or unexpected status when this assertion fails, without printing a defaults
path or JSON payload. This improves the evidence for the next occurrence; it
does not claim to fix the underlying failure.

Measurement: exercise the classifier with `fixed`, `fail`, `skipped`, empty,
and an arbitrary private canary. Run the isolated doctor boolean test and the
hosted required gate. Inspect failure output for the bounded category only.

Success: all five classifier cases produce their registered categories; the
canary and fixture path never appear in the diagnostic; the real passing test
still passes. Pivot: leave the old assertion and keep the investigation open if
any private content appears or a legitimate result is misclassified.

Anchor: `tests/doctor-json-status.bats`, PR #600 hosted test log, Basili,
Caldiera and Rombach 1994 (GQM), and Munafò et al. 2017 (pre-registration).
