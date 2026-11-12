# OpenCode memory readiness

## Managed service trial prediction

- **Root cause:** The legacy launch agent uses a log-level value rejected by OpenCode 2. Its former `attach` client interface was removed. The obvious log-level correction exposes a generated password in the existing stdout log.
- **Hypothesis:** OpenCode 2's maintained shared service can start, authenticate its own CLI client, and stop inside an isolated synthetic home without printing its generated credential to our logs.
- **Measurement:** Run `heavy-run bash /tmp/opencode-managed-service-trial/run.sh` with synthetic paths, a scratch port, denied external network, and stdout discarded; check only exit codes and service cleanup.
- **Success:** The start, authenticated API check, and stop each exit zero in 1 of 1 trials; the scratch listener is gone afterward; no generated credential is captured.
- **Pivot:** If any check fails or the isolation boundary permits access to the live memory service, do not alter the installed launcher or alias; inspect upstream behavior first.
- **Anchor:** [OpenCode shared service documentation](https://opencode.ai/docs/cli/web/) and `launchagents/com.dotfiles.opencode-serve.plist.tmpl`.

The same isolated check can run on hosted macOS CI with a checksum-verified
OpenCode release. Its network-denial control uses a synthetic local listener.
This does not replace a later check on the installed Mac.

## Prediction before the fix

**Pivot:** OpenCode 2.2.6 prints a generated server password at startup.
The existing launch agent writes stdout to a log, so the lowercase-only change
would put a credential there. Revert that proposed change. Investigate the
upstream managed service and its client authentication before changing the
launch agent or `oc` alias. The live launch agent remains unverified and fails
on the uppercase log level.

Upstream says OpenCode v2 can start and authenticate to its own shared
background service. The old `oc` alias uses the removed `attach` interface,
and the dotfiles doctor checks the old port without authentication. A safe
migration must account for the alias, launch agent, and doctor together. The
upstream path is documented at <https://opencode.ai/docs/cli/web> and
<https://opencode.ai/docs/troubleshooting/>. This is source research, not a
live verification of Kimi or memory.

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

## Failed launcher status prediction

- **Root cause:** The launcher discards the OpenCode pipeline's exit status with `|| true`, so a failed invocation can return success.
- **Hypothesis:** Preserving that status makes a failed OpenCode run visible to the caller.
- **Measurement:** `bats tests/kimi-goal.bats` uses a fake OpenCode command that exits 23.
- **Success:** The launcher returns a nonzero status for that failure and every existing launcher test passes.
- **Pivot:** If either condition fails, retain the red test and investigate status propagation before delivery.
- **Stability guard:** Successful goal and dry-run cases keep their current output and exit status.
- **Anchor:** `bin/kimi-goal` at commit `9c9c292`, where the pipeline is followed by `|| true`.
