# Judge draft: two-stage integration prediction (draft)

**Not executed.** Independent conflict review found that choosing either side
would lose a required capability: main's compiler-free source-bound native
pair, or the draft's required judge reader. A source-bound Darwin reader and a
verified composition with the pair are prerequisites. Preserve the existing
merge and register the actual composition before resolving these conflicts.

Draft #755 is at `9db12ffc85591dddc75f38e7170c6ab0f7a60f25`. Its existing
worktree has an unfinished merge of main parent
`24a3c6fbbd83b685fe142699eaf0d935f0e70406`; four paths remain conflicted.
Compared with a fresh merge preview, the only non-conflict index difference is
the already resolved `scripts/install-e2e-if-needed.sh`. Preserve and review
that resolution along with all staged and untracked work. Current Agentbrew main is
`cef72da9c68ca6598cfa60673ab529125dc2158f`. A fresh merge preview from the
draft head to current main reports six conflicts: `INSTALL.md`,
`hooks/lib/pr-command-target.py`, `scripts/build-source.sh`,
`scripts/install-e2e-if-needed.sh`, `scripts/install.sh` and `tsup.config.ts`.

Goal: reconcile both parents while preserving their install, native-build,
hook and judge safeguards. Predict 8/8 named test files have at least one
passing test and no failures at each stage, the judge hook passes at stage one,
both hook scripts pass at stage two, independent review finds
zero lost parent safeguards, and the normal full gate passes. Fewer than 8/8
qualifying files, any required failed hook, any lost safeguard or any gate failure
rejects this reconciliation approach. Do not relabel skipped tests as passes.
The original exhausted source-lease cohorts and opt-in observations remain
closed. This integration does not qualify a release, model calibration, live
connector, private artifacts or a no-Cargo installation.

First independently review this prediction and its exact test commands.
Commit it before resolving conflicts. Reconcile the existing merge against
`24a3c6f` without discarding its staged or untracked files. Independently
compare its resolutions with both parents, then run the focused commands.
Only a passing stage can be committed. Then merge the pinned current main,
preserving the first merge and any newly introduced work. Independently compare
that resolution with both parents and rerun the focused commands before the
second merge commit. The unfiltered full gate must run in a clean clone of that
exact merge commit: the original worktree contains two untracked rejected
models that default discovery would otherwise execute. Preserve them in place.
Run the gate once only after the focused checks and review pass. If either
pinned head changes, stop and register a new prediction. The original draft's
installed-package hook scenario remains required separately before delivery;
this prediction does not qualify its remaining prerequisites.

Immediately before starting the stage-two merge, run this fail-stop check from
the original draft worktree. An unrelated remote change stops the plan.

```sh
set -eu
git fetch origin main
test "$(git rev-parse origin/main)" = cef72da9c68ca6598cfa60673ab529125dc2158f
test "$(git rev-parse HEAD^1)" = 9db12ffc85591dddc75f38e7170c6ab0f7a60f25
test "$(git rev-parse HEAD^2)" = 24a3c6fbbd83b685fe142699eaf0d935f0e70406
git diff --quiet
git diff --cached --quiet
```

Run this command from the draft worktree once after each independently reviewed
stage. Set `STAGE=1` or `STAGE=2` as appropriate. The private report is retained.

```sh
set -eu
case "${STAGE:-}" in 1|2) ;; *) exit 2 ;; esac
if [ "$STAGE" = 1 ]; then
  test "$(git rev-parse HEAD)" = 9db12ffc85591dddc75f38e7170c6ab0f7a60f25
  test "$(git rev-parse MERGE_HEAD)" = 24a3c6fbbd83b685fe142699eaf0d935f0e70406
else
  test "$(git rev-parse HEAD^1)" = 9db12ffc85591dddc75f38e7170c6ab0f7a60f25
  test "$(git rev-parse HEAD^2)" = 24a3c6fbbd83b685fe142699eaf0d935f0e70406
  test "$(git rev-parse MERGE_HEAD)" = cef72da9c68ca6598cfa60673ab529125dc2158f
  git fetch origin main
  test "$(git rev-parse origin/main)" = cef72da9c68ca6598cfa60673ab529125dc2158f
fi
unset LOCKED_INSTALL_OBSERVATION LOCKED_INSTALL_OBSERVATION_NPM_CLI CHECKUP_RUN_OBSERVATION CHECKUP_RUN_TEST_CLI HISTORY_SCANNER_CALIBRATION VERIFY_PLAN
report_dir=$(mktemp -d "${TMPDIR:-/private/tmp}/judge-integration.XXXXXXXX")
chmod 700 "$report_dir"
printf 'Private focused report: %s\n' "$report_dir"
report="$report_dir/vitest.json"
files='src/install-script.test.ts src/build-pipeline-guard.test.ts src/install-e2e-trigger.test.ts src/docs/install-playbook.test.ts src/judges/ollama-version.test.ts src/judges/engine-error.test.ts src/judges/promptfoo-config.test.ts src/judges/promptfoo-dispatch.test.ts'
for file in $files; do test -f "$file"; done
JOBS=1 heavy-run npm exec -- vitest run $files --maxWorkers=1 --reporter=json --outputFile="$report"
node - "$report" $files <<'NODE'
const fs = require('node:fs');
const path = require('node:path');
const [file, ...expected] = process.argv.slice(2);
const report = JSON.parse(fs.readFileSync(file, 'utf8'));
if (!report.success || report.testResults.length !== 8 || expected.length !== 8) process.exit(1);
for (const name of expected) {
  const item = report.testResults.find((test) => path.resolve(test.name) === path.resolve(name));
  if (!item || !item.assertionResults.some((test) => test.status === 'passed') || item.assertionResults.some((test) => test.status === 'failed')) process.exit(1);
  const skipped = item.assertionResults.filter((test) => test.status !== 'passed');
  console.log(JSON.stringify({file: name, passed: item.assertionResults.length - skipped.length, skipped: skipped.map((test) => ({name: test.fullName, status: test.status}))}));
  if (skipped.some((test) => !test.fullName.includes('locked-install guard observations (qualification required)') || !['pending', 'skipped'].includes(test.status))) process.exit(1);
}
NODE
bash hooks/checks/judge-pr-delivery.test.sh
if [ "$STAGE" = 2 ]; then bash hooks/checks/review-request-classifier-gate.test.sh; fi
printf 'Private focused report: %s\n' "$report_dir"
```

After the stage-two merge commit, run the full gate with this command from the
original draft worktree. It creates a private clean clone and refuses the
exhausted controlled source-lease cohort and rejected test models. It retains
the complete private log and fails if any gate step is cached. Inspect any
failure before taking another action. The dependency helper may run `npm ci`
in the new private clone if its lockfile cannot use the local dependency copy.

```sh
set -eu
git fetch origin main
test "$(git rev-parse origin/main)" = cef72da9c68ca6598cfa60673ab529125dc2158f
test "$(git rev-parse HEAD^2)" = cef72da9c68ca6598cfa60673ab529125dc2158f
test "$(git rev-parse HEAD^1^1)" = 9db12ffc85591dddc75f38e7170c6ab0f7a60f25
test "$(git rev-parse HEAD^1^2)" = 24a3c6fbbd83b685fe142699eaf0d935f0e70406
git diff --quiet
git diff --cached --quiet
head=$(git rev-parse HEAD)
scratch=$(mktemp -d "${TMPDIR:-/private/tmp}/judge-clean-gate.XXXXXXXX")
chmod 700 "$scratch"
printf 'Private full-gate directory: %s\n' "$scratch"
git -c core.hooksPath=/dev/null clone --no-hardlinks --no-local --no-checkout "$PWD" "$scratch/repo"
git -C "$scratch/repo" -c core.hooksPath=/dev/null checkout --detach "$head"
cd "$scratch/repo"
test "$(git rev-parse HEAD)" = "$head"
test ! -e src/judges/native-assets-preparation.test.ts
test ! -e src/judges/native-assets-set.test.ts
if rg -q 'controlled source-lease release windows' src/sync/pull-source-caches.test.ts; then exit 2; else test "$?" -eq 1; fi
bash scripts/worktree-deps.sh "$HOME/apps/tooling/agentbrew"
unset VERIFY_PLAN LOCKED_INSTALL_OBSERVATION LOCKED_INSTALL_OBSERVATION_NPM_CLI CHECKUP_RUN_OBSERVATION CHECKUP_RUN_TEST_CLI HISTORY_SCANNER_CALIBRATION
if NO_CACHE=1 JOBS=1 CARGO_BUILD_JOBS=1 VITEST_MAX_WORKERS=1 LOCKFILE_SYNC_NPM=npm@10.9.2 heavy-run npm run verify >"$scratch/verify.log" 2>&1; then
  rg -q '^verify: passed; 0 of 22 steps from cache\.' "$scratch/verify.log"
else
  printf 'Full gate failed; inspect %s\n' "$scratch/verify.log"
  exit 1
fi
```

The commands and prediction require independent review and a commit before
conflict resolution. Anchor: Basili, Caldiera and Rombach (1994), Goal
Question Metric, and Munafò et al. (2017), preregistration.
