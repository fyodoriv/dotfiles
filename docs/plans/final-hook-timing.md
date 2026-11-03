# Missing-timeout fixture classification

Prediction committed in 2825ace before the fixture changes. The completed
integration gate reported an additional failure at the missing-timeout
test's whole-hook elapsed assertion. The no-GitHub-call canary had not yet
run. A later host-load observation does not establish the historical
cause, and the fixture's squash message is normal setup output.

The production helper and timeout-selection code match the unchanged
default base. An explicitly empty timeout path returns before invoking
GitHub. No production guard change is part of this correction.

## Hypothesis and measurement

Keep zero GitHub canary writes at every load and zero accepted unsaturated
runs at or above the unchanged ten-second bound. Only an elapsed overrun
with observed one-minute load above CPU count may be reported inconclusive.
A saturated skip is not a passing timing measurement.

Run `heavy-run bats --filter 'without a timeout binary|local proof never calls gh|a hung gh|missing-timeout timing policy' tests/agent-hooks-block-dangerous-git-merged.bats`.
Success requires the existing missing-timeout, local-proof, and hung-call
controls, plus every planted canary/unsaturated/fast/saturated classification.
Any masked canary, accepted unsaturated violation, or false timing-pass
claim abandons this approach.

## Fixture behavior

Capture elapsed immediately after the target hook call. Run its fail-closed
status and no-call canary assertions first. Run the existing local-diff
proof and repeat the canary check before evaluating timing. Reuse only
`host-load.bash`, so this file's custom setup remains unchanged.

The test-only classifier returns an explicit inconclusive code for a slow
saturated observation. Bats then marks that test skipped with elapsed and
the observed load-versus-CPU condition. Planted controls keep a written
canary and an unsaturated violation failing under that policy.

Anchor: Basili, Caldiera, Rombach (1994), Goal Question Metric; Forsgren,
Humble, Kim (2018), stability; existing `tests/host-load.bash` policy.
