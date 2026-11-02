# Preserve the current Space

Keep background activation from restoring the two settings named in issue #398.
Predictions adfa278 and cab7465 preceded the regression run: two failed
setting checks become zero. Measure with `bats tests/module-macos.bats`.
Keep the change only with zero failures and the core-profile control passing.
If either setting remains wrong, abandon the settings approach and investigate
the activation source. Anchor: Basili, Caldiera, Rombach (1994), GQM.

Set automatic Space switching off in core defaults. Disable the bottom-right
hot corner in full-profile visual defaults. Doctor checks use the same values,
with the visual check scoped to the full profile. Tests source the real module
against a per-test scratch defaults store. No live macOS preferences are changed
by the tests. The normal apply deploys the reviewed source after merge.

Evidence: both new regressions failed before implementation. The final module
suite passed, including the core-profile control. Full make check
exited 0 on ff1771f's source content. The final documentation-only gate must
also pass before this plan is committed and the PR merges.
