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

## Kimi launcher prediction

- **Root cause:** The launcher passes `--dir` to `opencode run`; OpenCode 2.2.6 rejects that option before a model call.
- **Hypothesis:** Starting the command in the requested directory instead will preserve project scope and let the Kimi launcher reach OpenCode 2.2.6.
- **Measurement:** Run the Kimi launcher tests with a fake OpenCode executable that records its working directory and arguments, then run one real Kimi memory recall after deployment.
- **Success:** Every launcher test passes, the child process uses the requested directory, no `--dir` argument is sent, and the Kimi recall test calls the memory tool and returns its expected public fact.
- **Pivot:** If the real recall does not pass, preserve the failure and investigate provider, permissions, and MCP activation before calling the path repaired.
- **Stability guard:** Existing dry-run, credential-source, and model-selection tests pass.
- **Anchor:** `opencode run --help` and the actual 2.2.6 `Unrecognized flag: --dir` error.
