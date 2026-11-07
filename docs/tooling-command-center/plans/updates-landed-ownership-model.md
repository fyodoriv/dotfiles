# Register a non-signaling timeout ownership model

The updates-landed timing fixture sent a signal to a process group during its
normal run. Its failure reported five seconds where the assertion required
less than five; a focused rerun passed. The group ownership and cleanup
boundary has not been independently qualified. Do not run that hung fixture,
or a full gate that includes it, until a safe method is qualified.

Goal: check a candidate timeout decision without starting or signaling any
process. Question: does a pure decision model request at most one recorded
action only for an alive, verified, matching owned group after the deadline?
Predict seven individually named controls pass with zero real process starts
or signals: `RECORDER_CONTROL`, `VERIFIED_TIMEOUT`, `BEFORE_DEADLINE`,
`UNVERIFIED`, `LEADER_EXITED`, `GROUP_MISMATCH`, and `SIGNAL_FAILURE`.
The positive recorder control must prove the fake adapter records one action;
the failure control must preserve the failed action as unqualified. Negative
cases record no action, and the supplied synthetic result is preserved.

After this registration, implement only a standalone synthetic model and test
at `scripts/updates-landed-ownership-model.test.mjs`. Measure with
`JOBS=1 heavy-run node --test scripts/updates-landed-ownership-model.test.mjs`.
The model receives a fake clock, fake ownership and group identity, and an
in-memory recording adapter. It imports no process, child-process, network or
filesystem action API, invokes no real signal, and stores no private input.
Machine-check exactly the seven named passing cases, no skips or TODOs, and
independently review both the test and the existing Perl path. Compare hashes
of tested source before and after. Any missing/extra case, wrong decision,
real process or signal, unqualified failed action, changed result, or test
gate failure rejects the approach. Setup failure is inconclusive.

This preparation does not establish operating-system group identity, PID
reuse, descendant cleanup or timing, and does not authorize the current hung
fixture or prove the hook fixed. A production change needs a separate
registered design and a safely qualified execution method.

Anchor: observed Nov 7 gate failure; Basili, Caldiera and Rombach (1994), Goal
Question Metric; Munafò et al. (2017), preregistration.
