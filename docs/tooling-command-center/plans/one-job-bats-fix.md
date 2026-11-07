# Register the one-job Bats fix

Dotfiles task `make-check-one-job-bats` reports that GNU parallel makes the
Makefile pass Bats an invalid one-job flag combination. Goal: let one-job
checks run their selected tests without weakening parallelism or isolation.
Predict three out of three test targets reject the one-job recipe before the
change and zero do after; three out of three multi-job controls must retain the
parallel arguments. The red baseline must be measured, not inferred.

After this prediction and the task are committed, extend the existing
`tests/makefile-bats-jobs.bats` scheduler fixture. It must run actual Make
recipes with a task-owned fake Bats executable that rejects the precise
one-job flag combination Bats rejects, records each test file and flags, and
checks exact selected-file coverage, failure propagation and doctor-last
ordering. Include the separate heavy-run file path for `test`. Keep the
existing no-parallel and multi-job controls. First add a named red test
`one-job recipes execute selected tests serially`; it must run `test`,
`test-all`, and `test-force` with GNU parallel present and `JOBS=1`, verify
all three attempted recipes with nonempty selected peers. Require a separate
target marker and proof that each failure is the exact rejected `--jobs 1` plus
`--no-parallelize-within-files` pair, not a setup or doctor-only failure. Emit
the fixed diagnostic `expected all
one-job recipes to run serially` on their expected failure. Require Bats exit
1, its exact named `not ok` result and the fixed diagnostic; any setup error is
inconclusive. Record each target's exit before any production edit.

```sh
JOBS=1 heavy-run bats --filter '^one-job recipes execute selected tests serially$' tests/makefile-bats-jobs.bats
```

Then add named positive controls for multi-job arguments, missing GNU parallel,
selected tests and doctor/heavy-run isolation. Add a tiny real-Bats smoke
fixture under owned temporary storage: run the Makefile's chosen one-job Bats
arguments captured from the actual Makefile recipe on a named passing file.
Verify the resolved executable is real Bats, not the fixture stub, and require
the named test and TAP plan; a reconstructed argument list, dry-run or empty
selection is not evidence. Modify only the Makefile selection,
its tests and the contributor test guidance. A one-job path must omit the
parallel-only Bats and cached-run job arguments; more than one job keeps the
existing flags. Run the whole scheduler test file and the actual selected gate:

```sh
JOBS=1 heavy-run bats tests/makefile-bats-jobs.bats
cache=$(mktemp -d)
env -u BATS_JOBS -u TEST_FILE_JOBS JOBS=1 CACHED_RUN_DIR="$cache" heavy-run make check
```

The selected-gate receipt must show a nonempty list of affected files, each
run fresh with zero cache hits, the scheduler test among them, plugin results,
and final success. Save the exact selector and compare it with the per-file
fresh results. Do not use the old Bats override. Preserve the cache and
logs privately for independent review. Success requires all three serial
recipes, all three multi-job recipes, exact fixture coverage and ordering,
real-Bats smoke, complete scheduler suite and fresh repository gate. Any
wrong recipe, missing selected test, stale cache, isolation regression, failed
gate or incorrect success rejects the approach; preserve its evidence and
redesign instead of weakening controls. Test setup failure is inconclusive.

Anchor: Bats parallel execution documentation
https://bats-core.readthedocs.io/en/stable/usage.html#parallel-execution;
Basili, Caldiera and Rombach (1994), Goal Question Metric; Munafò et al.
(2017), preregistration.
