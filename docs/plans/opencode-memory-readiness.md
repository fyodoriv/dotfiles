# OpenCode memory readiness

## Doctor launcher discovery prediction

- **Root cause:** The doctor only looks for text resembling an `oc` alias. A
  stale alias can pass, and the supported executable alone can fail.
- **Hypothesis:** Checking for the managed executable or its deployed alias
  will report the usable launcher without accepting a stale attach alias.
- **Measurement:** `bats tests/opencode-service.bats` with synthetic homes and
  launcher paths covering the executable, deployed alias, and stale alias.
- **Success:** Each usable path passes and the stale-only path fails; no
  existing service test fails.
- **Pivot:** If a working launcher fails or an unrelated `oc` passes, do not
  ship the doctor change.
- **Anchor:** `modules/local-ai/doctor.sh` and `home/zshrc.ai-tools`.

The first review found two additional cases: a stale local alias can override
the executable, and the doctor can run from a checkout other than the deployed
one. The follow-up must reject a known legacy alias even with the managed
executable on `PATH`, and accept the launcher from the deployed checkout.
Success is zero failures across those new cases and the existing service
fixtures. If either classification is wrong, do not ship the doctor change.
The measurement remains `bats tests/opencode-service.bats`.

## Run directory with global options

- **Root cause:** The wrapper detects `run` only as the first argument, so a
  preceding global option makes it append the directory to the message.
- **Hypothesis:** Recognizing `run` after supported global options preserves the
  requested working directory without treating an option value as a command.
- **Measurement:** `bats tests/opencode-service.bats` with cases for a global
  option before `run` and for an option whose value is `run`.
- **Success:** The new regression fails before the fix; all cases pass after it.
- **Pivot:** If either case fails or existing launcher cases regress, do not ship.
- **Anchor:** OpenCode 2.2.6 `--help` and `bin/dotfiles-opencode`.

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

The first hosted trial verified the release checksum and passed the synthetic
network-denial control. Service configuration and start returned zero, but the
subsequent authenticated API command returned nonzero. The test suppressed
service output, so the failure cause is not yet known. Reproduce it locally and
investigate the isolation boundary before changing the installed launcher.

- **Diagnostic hypothesis:** Classifying the synthetic API command's output in
  memory can distinguish connection, access, and HTTP failures without writing
  raw output or credentials to a log.
- **Measurement:** Run the isolated hosted check and inspect its category only.
- **Success:** The failing command emits one bounded category; raw service
  output and credentials appear in zero log lines.
- **Pivot:** If the category is unknown, or cannot be emitted safely, keep the
  failure unclassified and do not deploy a launcher change.
- **Anchor:** The first hosted isolated-service run in dotfiles PR 641.

The hosted diagnostic reported a permission error and a listener left after
cleanup. A focused local sandbox probe reproduced the cleanup boundary: a
process could not signal its child under the original policy. With a single
sandbox and `target same-sandbox`, one child could signal another, while it
could not signal its outside parent. This explains the unsafe cleanup boundary;
it does not yet prove the cause of the API failure.

- **Cleanup hypothesis:** Running the scratch service and client in one
  sandbox with same-sandbox signals permits safe shutdown without letting the
  trial signal outside processes.
- **Measurement:** Repeat the focused signal probe and the hosted service
  trial, including listener and registration cleanup checks.
- **Success:** Both inside signal checks pass, the outside signal check is
  denied, and zero scratch listeners or registrations remain after the trial.
- **Pivot:** If the sandbox cannot enforce that boundary, or cleanup leaves
  state, do not run the service trial against the installed Mac.
- **Anchor:** The focused macOS `sandbox-exec` signal probe and upstream
  `packages/client/src/effect/service.ts` service-stop implementation.

The revised hosted macOS trial passed with checksum-verified OpenCode 2.2.6.
The scratch service started, its client reached the authenticated API, and the
listener and registration were absent after stop. The same test also denied
signals to the outside parent and blocked access to the synthetic network
control. It did not exercise the installed user's service, alias, or memory.
The installed binary's SHA-256 matches the executable from the verified
upstream archive used by the hosted trial. The hosted and local macOS versions
differ, so the installed-machine trial remains necessary.

The installed binary also passed the isolated local trial: the managed service
started, its authenticated client succeeded, and no scratch listener or
registration remained. The sandboxed shell printed a working-directory warning
before entering the scratch home. The test did not change the live service,
run Kimi, or recall shared memory.

## Version-aware launcher prediction

- **Hypothesis:** Route `oc` and the login job through the upstream managed
  service on OpenCode 2, while keeping the existing attach path for OpenCode 1.
  This removes the startup loop and avoids writing service credentials to logs.
- **Measurement:** Run `bats tests/opencode-service.bats` and
  `bats tests/module-local-ai.bats` with synthetic version 1 and 2 binaries,
  the isolated service trial, then
  `dotfiles doctor --full --module local-ai` and one synthetic Kimi
  shared-memory recall after deployment.
- **Success:** All version 1 and 2 fixture cases pass; the installed version 2
  service is healthy, the old failing loop is gone, no credential enters logs,
  and 1 of 1 synthetic Kimi memory recalls succeeds.
- **Pivot:** If either version loses its supported path, the service cannot be
  stopped safely, any credential is logged, or Kimi recall fails, do not deploy
  the migration; keep the current configuration and diagnose the failure.
- **Anchor:** `home/zshrc.ai-tools`, `modules/local-ai/doctor.sh`,
  `launchagents/com.dotfiles.opencode-serve.plist.tmpl`, and the upstream
  [OpenCode CLI service documentation](https://opencode.ai/docs/cli/).

The local command hook treats a multi-file Bats invocation as a full suite.
The two commands above run the same named files separately.

In a network-denied scratch home, the installed OpenCode binary accepted the
wrapper's translated `-c --dir <path> --help` invocation. This checks argument
parsing only; it does not start a session or prove shared-memory recall.

On November 12, the draft `oc` wrapper returned an exact synthetic `READY`
text event from the configured Kimi model. The process exited successfully.
The separate `oc service status` check still returned `stopped` during and
after the trial, and no OpenCode process remained afterward. The first trial
verified a model reply, not a healthy persistent service. Automatic service
startup was not established by that run.

On November 12, a separate scratch-home trial began with the service stopped.
An `api get /api/info` call automatically started the installed OpenCode
binary's service and returned successfully. The sandbox denied access to the
live service, and cleanup removed the scratch listener and service state.
This tests API-triggered startup, not a deployed `oc` command or every client.

A second real `oc` session with Kimi searched for a newly stored synthetic
record. Its tool evidence included `memory_search` and the test phrase, and
its answer returned that phrase. The exact test record was deleted and an
exact search confirmed it was absent. This proves one shared read; it does
not prove the bootstrap or session-save lifecycle, or a persistent service.
The test harness set a scratch working directory but inherited `PWD` from
Agentbrew. A follow-up check confirmed that the wrapper's Bash process resets
`PWD` to the actual scratch working directory before it starts OpenCode.

The managed service was then started explicitly with the draft `oc` wrapper.
Its status returned a loopback address, and the draft doctor recognized it
as healthy. A real Kimi session called `memory_search` through that service
and returned the public advisory's fixed version. One intermediate status
check reported stopped during startup; a later check and the post-recall
doctor check passed. This does not prove bootstrap, session save, or that the
installed configuration has been updated.

Three initial synthetic Kimi session-save attempts produced no exact-search
match. Their scratch project explicitly denied `memory_commit_session_legacy`,
and one tool result reported a configuration-policy block. In a separate
scratch project with only that test denial removed, Kimi called the save tool;
exact search returned the synthetic session and decision. Both were deleted by
exact hash and a later exact search returned no match. This proves one save and
recall with the remaining scratch restrictions; bootstrap and broader lifecycle
behavior still need verification.

The obsolete launchd job was then unloaded after the managed service was
healthy. Its plist was retained. A launchd check confirmed the old job was
not loaded and the managed service remained healthy. This is temporary: the
installed configuration could load the old plist again until the source change
is delivered and applied.

## Run directory prediction

- **Root cause:** The draft wrapper translates `--dir` to a positional
  directory. OpenCode's `run` command treats positional arguments as the
  prompt, and its directory comes from `PWD`.
- **Hypothesis:** Changing directory before invoking `oc run` will select the
  requested project without adding the path to the model prompt.
- **Measurement:** Use a fake OpenCode executable to record its working
  directory, `PWD`, and arguments for `run --dir`; keep the existing
  interactive directory and version compatibility tests.
- **Success:** Both directory values equal the requested path, the prompt
  arguments contain no extra path, and every existing wrapper test passes.
- **Pivot:** If the directory or prompt is wrong, or any existing version path
  fails, leave the wrapper undeployed and investigate.
- **Anchor:** [OpenCode 2.2.6 run source](https://github.com/anomalyco/opencode/blob/v2.2.6/packages/cli/src/run/run.ts).

The fake-client regression passes. In a real Kimi run with `oc run --dir`, one
tool event contained the scratch directory and the process exited zero. The
final text did not contain the expected absolute path, so this run does not
independently prove that the tool output was `pwd` in the requested directory.

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

## Validator failure diagnostics

- **Root cause:** `tests/validate.bats` redirects validator output in
  `setup_file`. Bats stops on the failed command before saving its exit status,
  and teardown removes the only copy of the diagnostic.
- **Hypothesis:** Printing the captured validator output when setup fails will
  reveal the failing check while retaining a failing test result.
- **Measurement:** Run a Bats fixture with a fake validator that exits nonzero
  and prints a known diagnostic; also run `bats tests/validate.bats`.
- **Success:** The fixture fails and exposes the diagnostic; the real validator
  tests continue to pass locally. The hosted run identifies its failure.
- **Pivot:** If the fixture hides the diagnostic, accepts a failure, or the
  real validator tests regress, leave the change unmerged and investigate.
- **Anchor:** Hosted dotfiles run 43333887839 and `tests/validate.bats`.

## Generated Python cache in validation

- **Root cause:** Parallel tests create untracked Python bytecode in `lib/`.
  The sharing validator scans those generated files as untracked source and
  finds the runner's path embedded by Python.
- **Hypothesis:** Ignoring generated Python caches keeps them out of the
  untracked-file scan while tracked files and untracked source remain checked.
- **Measurement:** Run a fixture with an untracked cache containing a fake
  user path, plus existing untracked and tracked source-path checks.
- **Success:** The generated cache does not fail validation; both tracked and
  untracked source with a hardcoded user path still fail.
- **Pivot:** If a source path stops being reported or the cache still fails,
  do not merge; inspect Git's tracked and ignored file selection.
- **Anchor:** Hosted dotfiles run 43335347865 and `bin/dotfiles-validate`.
