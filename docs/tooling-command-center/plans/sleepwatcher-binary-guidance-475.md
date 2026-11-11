# Sleepwatcher binary guidance: doctor prediction

Issue #475 asks human-only failures to name the person and exact steps. When
the sleepwatcher binary is missing, `resilience.sleepwatcher_binary` currently
offers an echo-only auto-fix. The recheck still fails, and the normal failure
does not say who should install it.

Goal: give a missing binary a person-owned install step without implying that
doctor installed it. Predict the missing case retains its failure and names
`You:` and `brew install sleepwatcher`, the present case still passes, and a
scratch real-doctor `--fix --json` case shows the steps without invoking brew,
the setup wizard or UI. The missing check has an empty fix argument and puts
the owner guidance in its fifth, failure-only description. Success is 3/3 named cases with zero launch attempts,
the full resilience suite and the normal serial repository gate passing. Any
lost failure/pass, missing guidance, launch or regression rejects the approach.
This slice does not claim fresh-Mac acceptance for all of #475.

Commit this prediction before adding the test or changing behavior. Tests use
the real module with synthetic availability for the two absolute binary paths.
The real-doctor case extracts the actual check and substitutes exactly those
two path literals with task-owned scratch paths, preserving the rest of the
check. It proves both original path occurrences are unique and substituted,
uses an isolated PATH, verifies each launch canary resolves there, and proves
fix mode with a separate harmless control. The missing result must remain
`fail`, doctor must return its failing status, and the present case must pass
for either supported location. It must not change the host's installed binary.

First add `sleepwatcher missing gives manual install steps` with fixed failure
diagnostic `expected manual sleepwatcher guidance`. The red command must fail
for that assertion, not setup:

```sh
set -e
log=$(mktemp)
set +e
JOBS=1 heavy-run bats --filter '^sleepwatcher missing gives manual install steps$' tests/module-resilience.bats >"$log" 2>&1
status=$?
set -e
[ "$status" -eq 1 ]
grep -Fq 'not ok 1 sleepwatcher missing gives manual install steps' "$log"
grep -Fq 'expected manual sleepwatcher guidance' "$log"
printf 'Private red log: %s\n' "$log"
```

After the reproduction, add the other two cases, change only this check and
its documentation, and run:

```sh
set -euo pipefail
log=$(mktemp)
JOBS=1 heavy-run bats --filter '^sleepwatcher (missing gives manual install steps|present remains passing|real doctor fix shows steps without launches)$' tests/module-resilience.bats >"$log" 2>&1
for name in 'sleepwatcher missing gives manual install steps' 'sleepwatcher present remains passing' 'sleepwatcher real doctor fix shows steps without launches'; do
  [ "$(grep -Ec "^ok [0-9]+ $name$" "$log")" -eq 1 ]
done
grep -Fxq '1..3' "$log"
! grep -Eiq '(^not ok|# skip)' "$log"
printf 'Private focused log: %s\n' "$log"
JOBS=1 heavy-run bats tests/module-resilience.bats
test "$(git rev-parse HEAD)" = bd83044343c63a82ed3dcc2b02aa84fee10be320
expected_status=$(printf ' M docs/module-reference.md\n M modules/resilience/doctor.sh\n M tests/module-resilience.bats\n?? docs/plans/sleepwatcher-binary-guidance-475.md\n')
test "$(git status --porcelain --untracked-files=all)" = "$expected_status"
cache=$(mktemp -d)
chmod 700 "$cache"
./bin/bats-affected --pairs > "$cache/pairs"
selected=$(cut -f1 "$cache/pairs" | awk -v root="$PWD/" 'index($0, root) == 1 { print substr($0, length(root) + 1); next } { exit 1 }' | LC_ALL=C sort -u)
expected_selected=$(printf '%s\n' tests/deprecated-agents.bats tests/doctor-result-verification.bats tests/doctor.bats tests/errors-log.bats tests/keep-awake-tools.bats tests/launchd-maxfiles.bats tests/module-resilience-amphetamine-stale.bats tests/module-resilience.bats tests/power-protect-readiness.bats tests/sleepwatcher-doctor-guidance.bats tests/smoke.bats tests/verify-counts.bats)
test "$selected" = "$expected_selected"
shasum -a 256 modules/resilience/doctor.sh tests/module-resilience.bats docs/module-reference.md docs/plans/sleepwatcher-binary-guidance-475.md > "$cache/inputs.sha"
gate_log=$(mktemp)
printf 'Private gate log: %s; selector and input hashes: %s\n' "$gate_log" "$cache"
if CACHED_RUN_DIR="$cache" JOBS=1 heavy-run make check BATS_JOBS= TEST_FILE_JOBS= >"$gate_log" 2>&1; then
  grep -Fq '✓ All checks passed' "$gate_log"
  grep -Fq 'cached-run: 11 files: 0 unchanged (passed before), 11 checked' "$gate_log"
  grep -Fq 'cached-run: 1 files: 0 unchanged (passed before), 1 checked' "$gate_log"
  shasum -a 256 -c "$cache/inputs.sha"
else
  printf 'Gate failed; inspect %s\n' "$gate_log"
  exit 1
fi
```

The final command uses the repository's serial Bats override because Bats
1.14 rejects the default one-job parallel flags. It uses a fresh private cache,
requires all 12 selected files and retains logs; report platform skips without
counting them as passes. Require the full module and normal repository gate
to pass, and independently review the final diff.
Anchor: issue #475; Basili, Caldiera and Rombach (1994), Goal Question Metric;
Munafò et al. (2017), preregistration.
