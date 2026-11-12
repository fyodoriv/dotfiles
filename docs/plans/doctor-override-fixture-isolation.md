# Doctor override fixture isolation

Registered before the test change on 2026-11-11. Hosted PR #586 saw two
nonzero doctor exits in the per-machine override test, then a pass. Their
cause is unknown. A controlled failing `chezmoi doctor` fixture also makes
the same test return nonzero, proving this test currently depends on an
external health check.

Hypothesis: a fixture-owned healthy `chezmoi` stub makes the override test
independent of a healthy or failing simulated host executable, without hiding
real doctor failures in production or in the separate diagnostic test.

Measurement: add a regression that places a failing host stub on PATH and
checks the override result and that the host stub was never called. First
confirm it fails against the current fixture. Then run the full
`tests/doctor-validate-overrides.bats` suite in hosted CI. In the regression,
exercise healthy and failing simulated hosts 20 times each. Keep the existing
synthetic failing-doctor diagnostic test, and check that it still reports a
failure. Do not log raw doctor output in the stress case.

Success: the regression fails before the fixture change; all 40 controlled
runs pass after it, the suite passes, the failing-doctor diagnostic remains
visible, and zero private-canary strings are disclosed. Pivot: any production
change, masked diagnostic, host invocation or disclosure rejects the fixture
approach. The original hosted failure remains unconfirmed unless new evidence
identifies it.

Anchor: the `doctor-override-fixture-isolation` task; Basili, Caldiera and
Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration).
