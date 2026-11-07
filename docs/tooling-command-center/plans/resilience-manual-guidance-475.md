# Register tmux and wakeup guidance (#475)

The resilience doctor currently gives echo-only fixes for missing tmux and a
missing or incorrect wakeup hook. These leave failures without a named owner
in ordinary output. Predict both checks retain their existing pass/fail tests,
stop presenting an echo as an automatic fix, and give `You:` plus the exact
relevant command on failure. A missing tmux requires `brew install tmux`; a
missing wakeup hook requires `dotfiles apply`. Neither action runs under
`doctor --fix`.

Success: 2/2 missing guidance cases, 2/2 existing-state passing controls,
and one real scratch doctor `--fix --json` case pass with no brew or dotfiles
launch. The real-doctor test must include an independent harmless fix-mode
control, isolated PATH, and one result per check. The complete resilience suite
and the registered fresh serial selected repository gate also pass. Pivot on
any missing guidance, changed failure/pass, command launch, test failure or
gate regression. This is a slice of #475, not fresh-Mac acceptance.

Freeze this prediction before tests or code. First add only the two missing
cases to `tests/module-resilience.bats`. Each uses the actual module check,
synthetic isolated input and a fixed diagnostic on missing owner guidance.
Run each named case separately; require exit 1, exactly the named `not ok`, and
the fixed diagnostic. Setup failures are inconclusive. The first reproductions
must fail before changing production code.

```sh
JOBS=1 heavy-run bats --filter '^tmux missing shows manual guidance$' tests/module-resilience.bats
JOBS=1 heavy-run bats --filter '^wakeup missing shows manual guidance$' tests/module-resilience.bats
```

Then add passing-state and real-doctor controls; modify only the two checks,
the resilience tests and their module reference documentation. Run the five
named cases and the full resilience suite. Capture logs; assert exactly one
`ok` per named case, the five-case TAP plan, no `not ok` or skip, and no
launch marker. Require the full suite exit 0.

```sh
JOBS=1 heavy-run bats --filter '^(tmux missing shows manual guidance|wakeup missing shows manual guidance|tmux present remains passing|wakeup present remains passing|resilience real doctor fix shows both steps without launches)$' tests/module-resilience.bats
JOBS=1 heavy-run bats tests/module-resilience.bats
```

The candidate starts from `10d0ec8` with only the three named tracked files
changed. Use a new private cache and verify `bats-affected --pairs` selects
exactly the following 12 files before running the full registered serial gate:
`deprecated-agents`, `doctor-result-verification`, `doctor`, `errors-log`,
`keep-awake-tools`, `launchd-maxfiles`, `module-resilience-amphetamine-stale`,
`module-resilience`, `power-protect-readiness`, `sleepwatcher-doctor-guidance`,
`smoke`, and `verify-counts` (each in `tests/` with `.bats`). Hash the three
candidate files before and after the gate. Require `make check` exit 0, the
11+1 fresh checked-file summaries with zero cached hits, and `All checks passed`.
Inspect plugin and skip output and state limitations. The serial overrides avoid
the separately observed Bats one-job flag failure. The plan stays in this
coordination branch, not product docs, to avoid the volatile-count guard.

```sh
CACHED_RUN_DIR="$cache" JOBS=1 heavy-run make check BATS_JOBS= TEST_FILE_JOBS=
```

Independent review must verify the selector, logs, hashes, final commit and
absence of unintended launches. Anchor: issue #475; Basili, Caldiera and
Rombach (1994), Goal Question Metric; Munafò et al. (2017), preregistration.
