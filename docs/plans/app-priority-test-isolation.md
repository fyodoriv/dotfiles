# Keep the native App Priority test isolated

**Hypothesis:** The outer isolation test can run the current native config
fixture and still prove that the inherited config stays untouched.

**Measurement:** Run the isolation fixture in hosted CI and read its TAP.
Run `bin/bats-affected --pairs` with only `tests/app-priority.bats` changed
and check that it selects the outer isolation fixture. Run the full hosted suite.

**Success:** The outer fixture exits zero, runs exactly 1 named child test,
and leaves the inherited config canary byte-for-byte intact. A child test
file change selects both its own suite and the isolation fixture.

**Pivot:** If 1 expected child test is missing or the canary changes, keep
the full gate open and inspect the fixture selection or setup.

**Anchor:** [Exact full-suite failure](https://github.com/fyodoriv/dotfiles/actions/runs/46059200365)
and [the native-only migration](https://github.com/fyodoriv/dotfiles/pull/863).
