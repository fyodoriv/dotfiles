# Keyboard-layout test diagnostic

Registered before instrumentation on 2026-11-11. The custom-layout pairing
test returned nonzero during one local gate, then passed, failed and passed
in focused runs. The cause is unknown. Its fixture uses fake Bluetooth tools;
it must never open the real settings app.

Hypothesis: a bounded receipt of the status and observed test-output markers
will distinguish planted failure observations without exposing raw output.

Measurement: add a test-only formatter for numeric status and fixed yes/no
flags for the confirmation prompt, connected message, saved-layout message,
and timeout message. Plant a missing-prompt output, a connection timeout,
and a connected-but-unsaved output. Check each expected flag and add a
private canary to each input; no canary may appear in the receipt. Unknown
status is printed as `unknown`. Run the formatter cases and the existing
custom-layout case as focused Bats tests; hosted CI runs the affected suite.
The fixture's fake `open` and `system_profiler` remain first on PATH.

Success: all three planted observations produce the expected flags, zero
canary disclosures occur, and existing pairing and keymap tests pass. Pivot:
any raw output, real Bluetooth action, or inference of an unverified cause
rejects the diagnostic. A flag reports only text observed; it does not prove
why a step failed. The intermittent cause remains open until evidence shows it.

Anchor: the `glove80-custom-layout-test-diagnostic` task; Basili, Caldiera and
Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration).
