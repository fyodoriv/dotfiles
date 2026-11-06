# JetBrains doctor app detection

Issue #477 reports that an app-shaped stub without an executable triggers IDE
checks. One incident is evidence of the defect, not a measured fleet rate.

Goal: skip checks for unusable IDE bundles. Question: do executable-based
fixtures reject a stub while retaining a runnable app? Metric: one stub false
positive moves from 1 to 0, one runnable control remains detected, and the
existing JetBrains doctor suite passes.

Measurement: `heavy-run bats tests/module-jetbrains.bats`. First add the
fixture and capture its failing result before the fix. Success requires zero
stub false positives, a detected executable fixture and all existing tests
passing. Any false positive, missing runnable fixture or regression rejects
this approach; revisit app identity rather than bypass the check.

Anchor: Basili, Caldiera and Rombach (1994), Goal Question Metric; Munafò et
al. (2017), preregistration; the observed bundle in #477.
