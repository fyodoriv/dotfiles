# OpenCode memory readiness

## Prediction before the fix

- **Hypothesis:** OpenCode 2.2.6 rejects the launch agent's uppercase log level. Using its supported lowercase value will let the agent start and make a Kimi session able to retrieve the shared memory service.
- **Baseline:** `opencode serve --hostname 127.0.0.1 --port 4096 --log-level WARN` exits 1 with an invalid-value error. The loaded job reports exit 1.
- **Measurement:** Run `bats tests/module-local-ai.bats`, check `launchctl print gui/$(id -u)/com.dotfiles.opencode-serve`, and run a Kimi session that retrieves a known public test fact through the shared memory tool. Check the tool invocation and returned fact.
- **Success:** The regression test passes, the service stays running, and 1 of 1 Kimi retrievals calls the shared memory tool and returns the expected fact.
- **Pivot:** If the service does not start or Kimi does not retrieve the fact, do not call the integration repaired. Inspect the next failure and revise the approach.
- **Stability guard:** The existing local-AI tests pass and the service remains loopback-only.
- **Anchor:** [OpenCode 2.2.6 MCP cold-start issue](https://github.com/anomalyco/opencode/issues/62902); the installed CLI lists `warn`, not `WARN`, as a valid level.

This test does not establish that OpenCode or any memory provider is the best.
It checks one required path before a broader memory comparison.
