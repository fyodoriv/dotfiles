# Register network LaunchAgent guidance (#475)

The resilience doctor gives echo-only fixes for a network-resilience agent
that last exited 127 or is not loaded. Predict both failures remain failures,
no echo is presented as an automatic fix, and each gives `You:` plus exact
steps: reload the stale agent using `launchctl bootout` then `launchctl
bootstrap`, or run `dotfiles apply` and, if needed, bootstrap the missing
agent. Existing healthy-state tests must remain passing. Neither launchctl
mutation nor dotfiles apply may run from `doctor --fix` for these checks.

Success: 2/2 missing-guidance cases, 2/2 healthy-state controls, and a scratch
real-doctor `--fix --json` control pass. The real doctor uses a fake launchctl
whose read-only `list` and `print` paths return a missing job and exit 127;
any other launchctl action or dotfiles call writes a canary. Verify fake
commands are resolved through isolated PATH, both exact failures and empty fix
fields appear once, the canary is absent, and an independent harmless fix
proves `--fix` ran. The full resilience suite and fresh serial repository gate
must pass. Any changed healthy/failing outcome, missing step, mutating call,
test or gate failure rejects the approach. This does not finish #475.

Commit this prediction before the test or behavior change. Add only the two
named missing-guidance tests first, using synthetic launchctl responses through
the real module. Run each named case separately and require exit 1, its exact
`not ok` line, and fixed `expected manual network clean guidance` or `expected
manual network loaded guidance` diagnostic. Setup errors are inconclusive.

```sh
JOBS=1 heavy-run bats --filter '^network clean failure shows manual guidance$' tests/module-resilience.bats
JOBS=1 heavy-run bats --filter '^network unloaded shows manual guidance$' tests/module-resilience.bats
```

Then add the passing controls and scratch-doctor control, change only the two
checks and their resilience documentation, and run five named cases plus the
complete resilience suite. Require exactly one `ok` for each named case, TAP
plan `1..5`, no failure or skip, and zero launch canaries.

```sh
JOBS=1 heavy-run bats --filter '^(network clean failure shows manual guidance|network unloaded shows manual guidance|network clean remains passing|network loaded remains passing|network real doctor fix shows both steps without launches)$' tests/module-resilience.bats
JOBS=1 heavy-run bats tests/module-resilience.bats
```

The candidate starts from `975a254` with only module, test and module-reference
files changed. Before the repository gate, use a new private cache, save the
`bats-affected --pairs` selector, and require exactly the same 12 selected
files registered for the previous resilience slice. Hash the three files before
and after the gate. Require gate exit 0, `All checks passed`, and the fresh
11+1 checked-file summaries with zero cached hits. Inspect plugin and skip
output. The serial overrides avoid the separately observed Bats one-job flag
failure. Keep this plan in the coordination branch, not product docs.

```sh
CACHED_RUN_DIR="$cache" JOBS=1 heavy-run make check BATS_JOBS= TEST_FILE_JOBS=
```

An independent reviewer must verify selector, logs, test canaries, hashes and
final commit. Anchor: issue #475; Basili, Caldiera and Rombach (1994), Goal
Question Metric; Munafò et al. (2017), preregistration.
