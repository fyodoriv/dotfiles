# Rebuild a stale applied Agentbrew distribution

- Hypothesis: a current checkout with stale build inputs reports a rebuild instead of current. The reported-current count for planted stale inputs drops from one to zero.
- Measurement: hosted controls in `tests/update-tooling-capability.bats` run the update skill against current checkouts with a stale, current, or unavailable Agentbrew build check.
- Success: one queued build for the stale case, zero builds for the current and unavailable cases, and all existing capability cases pass.
- Pivot: stop if the Agentbrew source probe cannot identify its own build inputs or if endpoint safe mode runs any probe. Report an unavailable probe explicitly.
- Anchor: task `update-tooling-stale-agentbrew-dist` and Agentbrew's `src/cli-build-health.ts` build-input contract.

Use Agentbrew's existing check from the applied source checkout. Its compiled bundle can predate the current build input list.
