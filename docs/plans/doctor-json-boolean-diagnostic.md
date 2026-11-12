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

## Fixture correction prediction

Registered before the fixture correction. The second hosted run reported an
unexpected status. Source inspection showed that hosted `DOTFILES_CI=1` makes
`check_defaults` return `skip` before the fixture can exercise a fix. Running
the isolated test with that environment reproduced the failure locally.

Hypothesis: disabling CI mode only for this scratch-domain doctor invocation
will exercise the intended fix path under both inherited CI settings.
Measurement: run the focused boolean tests with `DOTFILES_CI=1` and with it
unset, then use the hosted required gate. Success: both focused runs pass all
boolean tests, and the hosted case returns `fixed`; no other doctor invocation
changes environment. Pivot: any real preferences domain access or failure in
either environment stops the correction and retains the original behavior.
Anchor: `check_defaults` in `bin/dotfiles-doctor`, PR #600 hosted logs, Basili,
Caldiera and Rombach 1994 (GQM), and Munafò et al. 2017 (pre-registration).
