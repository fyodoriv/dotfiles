# Sync binding: final integrated-head repeat

The nine synthetic controls passed before formatting and main integration. Knip
then passed after the test was declared as an explicit entry. Before the PR is
ready, repeat the nine controls on the exact final integrated head. No target
selection case is admitted. The exact head below is the integrated candidate. Commit this prediction
before running the repeat.

Predict nine exact named passes, successful privacy and discovery canaries,
and zero guarded process/network attempts during the binding controls. Any
missing control, unsafe call, false canary, discovery regression, changed
source or wrong binding rejects this repeat. A setup failure is inconclusive.
The controls still prove only synthetic builder wiring; CommonJS properties and
global fetch are canaried, while synchronized ESM aliases are not separately
canaried.

```sh
env -i HOME="$HOME" PATH="$HOME/apps/tooling/dotfiles/bin:/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR=/private/tmp LANG=C /bin/bash <<'BASH'
set -eu
umask 077
expected_head=f4c4ca2e5e8d6cc56b4f95e50c414755c2c1d8fe
[ "$(git rev-parse HEAD)" = "$expected_head" ]
work_status=$(git status --porcelain --untracked-files=all)
[ -z "$work_status" ]
printf '%s  %s\n' \
  4b2a3bf8bbac6e274a45a73018ba6764c7c125f29238ffd1969db1d38c28dc42 src/sync-selection-binding.prep.ts \
  062ce976d8c4a3249df341ade3aff4dab7edeb0d8ebc27b09f77da953b981099 vitest.sync-binding-prep.config.ts \
  16603f6fd53846b5dab1c328548d817335444b5c68da0cbf7b4f04d7e1821788 knip.json \
  562289924441cbdb80788049d13673da5419141f76f178b67a7da2993a5bd7b8 package-lock.json \
  298abdea594db3976570bc8dd4138442ba1e248cc4035640a6efda99aa117e4c src/core/agents.yaml \
  39db22f579acf5639bbb17a261408debbde03f4692c0c439e77e7f13aeba74d6 node_modules/vitest/vitest.mjs \
  260a0a7a96a35e1b657480014c0f3b592b70061e42099edefc8fe97972f05fd4 node_modules/vite/package.json | shasum -a 256 -c
nodebin="$HOME/.local/share/fnm/node-versions/v24.21.0/installation/bin/node"
[ -f "$nodebin" ] && [ ! -L "$nodebin" ]
[ "$(stat -f '%u %Lp %z' "$nodebin")" = '501 755 122129232' ]
[ "$(shasum -a 256 "$nodebin" | cut -d ' ' -f 1)" = e4b5a3af0e05c75de2eae013904145f40fe7fc2a6e6f17510128bf45cca4e79b ]
logs=$(mktemp -d /private/tmp/sync-binding-final.XXXXXX)
logs=$(cd "$logs" && pwd -P)
mkdir "$logs/home" "$logs/tmp"
printf 'Private logs: %s\n' "$logs"
repo=$(pwd -P)
realhome=$(cd "$HOME" && pwd -P)
node_dir=$(dirname "$nodebin")
case "$repo$realhome$node_dir$logs" in *\"*|*\\*) exit 2 ;; esac
printf '(version 1) (allow default) (deny network*) (deny file-read* (subpath "%s")) (allow file-read* (subpath "%s") (subpath "%s")) (deny file-write*) (allow file-write* (subpath "%s") (literal "/dev/null"))\n' "$realhome" "$repo" "$node_dir" "$logs" >"$logs/sandbox.sb"
for directory in "$repo" "$node_dir"; do
  while [ "$directory" != "$realhome" ]; do
    directory=$(dirname "$directory")
    case "$directory" in "$realhome"|"$realhome"/*) ;; *) exit 2 ;; esac
    printf '(allow file-read-metadata (literal "%s"))\n' "$directory" >>"$logs/sandbox.sb"
  done
done
mkdir -p "$realhome/.local/state/agentbrew/experiments"
canary=$(mktemp -d "$realhome/.local/state/agentbrew/experiments/sync-binding-final-canary.XXXXXX")
trap 'rm -rf "$canary"' EXIT
printf '%s\n' 'synthetic private-read canary' >"$canary/record"
printf '(allow file-read-metadata (literal "%s"))\n' "$canary" >>"$logs/sandbox.sb"
/usr/bin/sandbox-exec -f "$logs/sandbox.sb" /usr/bin/stat -f '%p' "$canary" >"$logs/metadata-canary.out" 2>"$logs/metadata-canary.err"
if /usr/bin/sandbox-exec -f "$logs/sandbox.sb" /bin/ls -1 "$canary" >"$logs/list-canary.out" 2>"$logs/list-canary.err"; then exit 1; fi
[ ! -s "$logs/list-canary.out" ]
grep -Fxq 'synthetic private-read canary' "$canary/record"
ln -s "$canary/record" "$logs/private-alias"
for target in "$canary/record" "$logs/private-alias"; do
  if /usr/bin/sandbox-exec -f "$logs/sandbox.sb" /bin/cat "$target" >"$logs/private-canary.out" 2>"$logs/private-canary.err"; then exit 1; fi
  [ ! -s "$logs/private-canary.out" ]
done
/usr/bin/sandbox-exec -f "$logs/sandbox.sb" /bin/cat "$repo/src/core/agents.yaml" >"$logs/repo-canary.out" 2>"$logs/repo-canary.err"
[ -s "$logs/repo-canary.out" ]
run_vitest() { JOBS=1 heavy-run /usr/bin/sandbox-exec -f "$logs/sandbox.sb" /usr/bin/env -i HOME="$logs/home" TMPDIR="$logs/tmp" PATH="$node_dir:/usr/bin:/bin" CI=1 "$nodebin" "$repo/node_modules/vitest/vitest.mjs" --configLoader runner "$@"; }
run_vitest list --config vitest.sync-binding-prep.config.ts --filesOnly --staticParse >"$logs/dedicated.list" 2>"$logs/dedicated.err"
[ "$(wc -l < "$logs/dedicated.list" | tr -d ' ')" -eq 1 ]
grep -Eq '(^|/)src/sync-selection-binding\.prep\.ts$' "$logs/dedicated.list"
run_vitest list --filesOnly --staticParse >"$logs/default.list" 2>"$logs/default.err"
[ -s "$logs/default.list" ]
result=0
grep -Eq '(^|/)src/sync-selection-binding\.prep\.ts$' "$logs/default.list" || result=$?
[ "$result" -eq 1 ]
run_vitest run --config vitest.sync-binding-prep.config.ts --maxWorkers=1 --reporter=json --outputFile="$logs/results.json" >"$logs/run.out" 2>"$logs/run.err"
env -i HOME="$logs/home" PATH=/usr/bin:/bin "$nodebin" - "$logs/results.json" <<'NODE'
const fs = require('node:fs');
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const cases = report.testResults.flatMap(file => file.assertionResults);
const names = ['mcp binding', 'rules binding', 'commands binding', 'agents binding', 'skills binding', 'hooks binding', 'models binding', 'instructions binding', 'mismatch and sentinels refuse'];
if (!report.success || cases.length !== 9 || cases.some(c => c.status !== 'passed') || new Set(cases.map(c => c.fullName)).size !== 9 || names.some(name => !cases.some(c => c.fullName === name))) process.exit(1);
console.log('sync binding final head: nine controls passed');
NODE
BASH
```

The read boundary has explicit repo and Node exceptions. The canaries do not
prove every alias or all third-party behavior. The full unfiltered gate and an
independent exact-head review are separate requirements. Anchor: the prior
committed red/green protocol and Basili, Caldiera and Rombach (1994), GQM.
