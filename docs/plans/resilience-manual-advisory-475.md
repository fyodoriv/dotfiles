# App Store keep-awake advisory

Issue #475 reports doctor lines that require a person but appear as failures
or offer interactive fixes to a noninteractive agent. Amphetamine is an App
Store app whose installation requires the person's own sign-in and choice.

Goal: make this one manual step actionable without launching an interactive
wizard from doctor. Question: can the missing-app check move from fail to warn,
name the person and steps, and retain pass for an installed app? Prediction:
one missing-app failure becomes one advisory, the installed control remains
passing, and `--fix` opens no App Store or wizard.

Measurement: `heavy-run bats tests/module-resilience.bats
tests/module-resilience-amphetamine-stale.bats`. Capture the missing-app red
control before the change. Success requires the warning, owner/steps, installed
pass and no-open controls plus existing tests. Any lost installed check,
automatic UI launch, missing guidance or continued failure rejects the change.
This covers only the App Store line; #475 remains open for its other items.

Anchor: Basili, Caldiera and Rombach (1994), Goal Question Metric; Munafò et
al. (2017), preregistration; issue #475's reported manual steps.
