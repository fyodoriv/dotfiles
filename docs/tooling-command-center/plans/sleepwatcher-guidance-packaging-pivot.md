# Sleepwatcher guidance: packaging pivot

The [original prediction](sleepwatcher-binary-guidance-475.md) was committed
before implementation at `7b0b17bdb02a5342c061a4d617da421644bac976`. Its red
test reproduced missing guidance; all three focused tests and the 15-test
resilience module suite then passed. Its fresh full gate failed at
`tests/verify-counts.bats:73`: three command lines in the copied prediction
were interpreted as volatile inventory counts. The exact failure was reproduced
locally. The original full gate is non-green and remains preserved.

This distinct packaging approach keeps the immutable prediction in the
coordination PR instead of copying it into the product PR. Preserve the
current-session untracked copy in a new private directory; do not overwrite
or delete it. Keep the doctor, test and module-reference bytes identical.
Predict all 12 selected test files and the normal serial gate pass with a fresh
cache. A changed input, changed selection, failed test or missing gate summary
rejects this approach; setup failure is inconclusive. The focused checks are
the already measured original controls, not a new baseline. The module
reference remains in the product PR. This does not close all of issue #475.

After independent review and commitment, run the exact command once from the
task worktree. It preserves the copied plan before the gate and retains the
selector, input hashes and gate log privately. Platform-specific skips must be
reported, not counted as passes.

```sh
set -euo pipefail
test "$(git rev-parse HEAD)" = bd83044343c63a82ed3dcc2b02aa84fee10be320
expected_before=$(printf ' M docs/module-reference.md\n M modules/resilience/doctor.sh\n M tests/module-resilience.bats\n?? docs/plans/sleepwatcher-binary-guidance-475.md\n')
test "$(git status --porcelain --untracked-files=all)" = "$expected_before"
printf '%s  %s\n' \
  d450691e50af570c4e748567c9492a6d8758bee9e0e61a0431c34b646985c575 modules/resilience/doctor.sh \
  2572c2765e6fefbb12a41ccebd353685a74916d39df29903727b6a4c5a404d78 tests/module-resilience.bats \
  32a60d0056ce6a3773f393083c27afa095ecdd5d54459b0f5f945649690fafe4 docs/module-reference.md \
  d3679d34e34095a10ac012b19601a90dfd1631c9ebc78b6654d0b4d474cdde49 docs/plans/sleepwatcher-binary-guidance-475.md | shasum -a 256 -c
preserved=$(mktemp -d "${TMPDIR:-/private/tmp}/sleepwatcher-plan.XXXXXXXX")
chmod 700 "$preserved"
printf 'Private preserved plan: %s\n' "$preserved"
test ! -e "$preserved/original.md"
mv docs/plans/sleepwatcher-binary-guidance-475.md "$preserved/original.md"
printf '%s  %s\n' d3679d34e34095a10ac012b19601a90dfd1631c9ebc78b6654d0b4d474cdde49 "$preserved/original.md" | shasum -a 256 -c
expected_after=$(printf ' M docs/module-reference.md\n M modules/resilience/doctor.sh\n M tests/module-resilience.bats\n')
test "$(git status --porcelain --untracked-files=all)" = "$expected_after"
cache=$(mktemp -d)
chmod 700 "$cache"
./bin/bats-affected --pairs > "$cache/pairs"
selected=$(cut -f1 "$cache/pairs" | awk -v root="$PWD/" 'index($0, root) == 1 { print substr($0, length(root) + 1); next } { exit 1 }' | LC_ALL=C sort -u)
expected_selected=$(printf '%s\n' tests/deprecated-agents.bats tests/doctor-result-verification.bats tests/doctor.bats tests/errors-log.bats tests/keep-awake-tools.bats tests/launchd-maxfiles.bats tests/module-resilience-amphetamine-stale.bats tests/module-resilience.bats tests/power-protect-readiness.bats tests/sleepwatcher-doctor-guidance.bats tests/smoke.bats tests/verify-counts.bats)
test "$selected" = "$expected_selected"
printf '%s  %s\n' \
  d450691e50af570c4e748567c9492a6d8758bee9e0e61a0431c34b646985c575 modules/resilience/doctor.sh \
  2572c2765e6fefbb12a41ccebd353685a74916d39df29903727b6a4c5a404d78 tests/module-resilience.bats \
  32a60d0056ce6a3773f393083c27afa095ecdd5d54459b0f5f945649690fafe4 docs/module-reference.md > "$cache/inputs.sha"
log=$(mktemp)
printf 'Private gate log: %s; selector and input hashes: %s; preserved plan: %s\n' "$log" "$cache" "$preserved"
if CACHED_RUN_DIR="$cache" JOBS=1 heavy-run make check BATS_JOBS= TEST_FILE_JOBS= >"$log" 2>&1; then
  grep -Fq '✓ All checks passed' "$log"
  grep -Fq 'cached-run: 11 files: 0 unchanged (passed before), 11 checked' "$log"
  grep -Fq 'cached-run: 1 files: 0 unchanged (passed before), 1 checked' "$log"
  shasum -a 256 -c "$cache/inputs.sha"
else
  printf 'Gate failed; inspect %s\n' "$log"
  exit 1
fi
```

Independent review must verify the exact selection and complete gate log
before delivery. Anchor: issue #475; Basili, Caldiera and Rombach (1994), Goal
Question Metric; Munafò et al. (2017), preregistration.
