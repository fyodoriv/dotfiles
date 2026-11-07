# Optional mas check: serial gate pivot

The [original prediction](mas-advisory-475.md) reproduced the missing-mas
failure, then passed all three named synthetic/scratch-doctor cases and all
12 resilience module cases. Its exact full-gate command did not pass: Bats
rejected `--jobs 1 --no-parallelize-within-files` with
`The flag --no-parallelize-across-files requires at least --jobs 2` before
running 11 selected files. The error was reproduced directly. The original
gate is non-green; do not describe it as a pass.

This distinct validation approach uses the repository's existing serial
override, also documented in `docs/plans/heavy-run-private-metadata.md`.
Predict the normal selected gate completes with zero failures while retaining
the already measured 3/3 named behavior checks. No product or test bytes may
change between the prediction and this gate. A failed check, unexecuted selected
file, changed inputs or missing gate summary rejects this approach. Report any
ordinary platform-specific skipped tests; never count them as passes. Setup
failure is inconclusive. Anchor: Basili, Caldiera and Rombach (1994), Goal
Question Metric; Munafò et al. (2017), preregistration.

The baseline head is `65d92c186313f55866b2190c5f8bea0835a0222f`. Exactly
12 test files are selected: `deprecated-agents.bats`,
`doctor-result-verification.bats`, `doctor.bats`, `errors-log.bats`,
`keep-awake-tools.bats`, `launchd-maxfiles.bats`,
`module-resilience-amphetamine-stale.bats`, `module-resilience.bats`,
`power-protect-readiness.bats`, `sleepwatcher-doctor-guidance.bats`,
`smoke.bats` and `verify-counts.bats`. The worktree must have exactly the
three tracked edits and the one untracked prediction named below.

The frozen candidate SHA-256 values are:

- `modules/resilience/doctor.sh`: `8db75a94594057119c756de2cd4582c10fa20bddd10fc4912ecdf0e30baa8c24`
- `tests/module-resilience.bats`: `044f420abd8661321abf68b37f092dd4b702d5d0b72605cb562954439e3d7ec6`
- `docs/module-reference.md`: `b5bd5b66476c78ea3dafe174dd8c82c93aaaa8cfbdca06dd96022969c3b54318`
- `docs/plans/mas-advisory-475.md`: `c78f45287585284a97d3691290dbd3407b604f525b4b7695c03034b4fcf2ee1f`

After independent review and commit, run once in the task worktree:

```sh
set -euo pipefail
test "$(git rev-parse HEAD)" = 65d92c186313f55866b2190c5f8bea0835a0222f
expected_status=$(printf ' M docs/module-reference.md\n M modules/resilience/doctor.sh\n M tests/module-resilience.bats\n?? docs/plans/mas-advisory-475.md\n')
test "$(git status --porcelain --untracked-files=all)" = "$expected_status"
printf '%s  %s\n' \
  8db75a94594057119c756de2cd4582c10fa20bddd10fc4912ecdf0e30baa8c24 modules/resilience/doctor.sh \
  044f420abd8661321abf68b37f092dd4b702d5d0b72605cb562954439e3d7ec6 tests/module-resilience.bats \
  b5bd5b66476c78ea3dafe174dd8c82c93aaaa8cfbdca06dd96022969c3b54318 docs/module-reference.md \
  c78f45287585284a97d3691290dbd3407b604f525b4b7695c03034b4fcf2ee1f docs/plans/mas-advisory-475.md | shasum -a 256 -c
log=$(mktemp)
cache=$(mktemp -d)
chmod 700 "$cache"
./bin/bats-affected --pairs > "$cache/pairs"
selected=$(cut -f1 "$cache/pairs" | awk -v root="$PWD/" 'index($0, root) == 1 { print substr($0, length(root) + 1); next } { exit 1 }' | LC_ALL=C sort -u)
expected_selected=$(printf '%s\n' tests/deprecated-agents.bats tests/doctor-result-verification.bats tests/doctor.bats tests/errors-log.bats tests/keep-awake-tools.bats tests/launchd-maxfiles.bats tests/module-resilience-amphetamine-stale.bats tests/module-resilience.bats tests/power-protect-readiness.bats tests/sleepwatcher-doctor-guidance.bats tests/smoke.bats tests/verify-counts.bats)
test "$selected" = "$expected_selected"
printf 'Private serial gate log: %s\n' "$log"
if CACHED_RUN_DIR="$cache" JOBS=1 heavy-run make check BATS_JOBS= TEST_FILE_JOBS= >"$log" 2>&1; then
  grep -Fq '✓ All checks passed' "$log"
  grep -Fq 'cached-run: 11 files: 0 unchanged (passed before), 11 checked' "$log"
  grep -Fq 'cached-run: 1 files: 0 unchanged (passed before), 1 checked' "$log"
else
  printf 'Serial gate failed; inspect %s\n' "$log"
  exit 1
fi
```

The override runs the selected files serially; it does not alter the test
selection or the machine-wide queue. Independent review must verify the gate
log and the earlier exact named results before delivery. This does not close
the fresh-Mac acceptance of issue #475 or fix the Makefile's one-job bug.
