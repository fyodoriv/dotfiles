# Core-profile Chrome theme check

Issue #487 reports a theme check that fails when the core profile has no
managed Chrome LaunchAgent. It also reports a disabled Dock guard; the current
workflow already skips the guard when the supported headed-Chrome option
disables it, and has a regression control. An arbitrary external disable alone
does not prove the supported option is set.

Goal: eliminate the false theme failure without hiding real missing themes.
Question: can the absent core-profile LaunchAgent skip the theme check while
core with a deployed agent and full profile without a theme still fail?
Prediction: the false-failure case moves from one failure to zero, and both
missing-theme controls remain failures. The theme check remains discoverable
by doctor list and override validation.

Measurement: `heavy-run bats tests/module-agent-browser.bats
tests/module-workflow.bats`. Capture the failing core skip control first.
Success requires all three cases and existing workflow guard controls to pass.
Any missed real failure, lost discoverability, or false core failure rejects
the approach.

Anchor: Basili, Caldiera and Rombach (1994), Goal Question Metric; Munafò et
al. (2017), preregistration; issue #487's observed doctor output.
