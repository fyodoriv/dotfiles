# Register explicit one-job Bats pivot

The first [one-job approach](one-job-bats-fix.md) reached its rejection
threshold. Its 17-case scheduler run failed the existing multi-job-flag test
because the test inherited `JOBS=1` and the candidate omitted `--jobs`.
The real-Bats smoke also failed to start: its isolated PATH lacked the required
`greadlink`, so that case is setup evidence, not a Bats behavior result. Both
failures were reproduced separately. Preserve the rejected candidate and logs;
do not claim its gate passed.
The retained rejected diff has SHA-256
`6b6902f45301ce75c3c5fd03ddcc035e7525814b3d5796e3aa08fde695eea1b04`.

This distinct candidate keeps `--jobs 1` for Bats and cached-run and removes
only `--no-parallelize-within-files` at one job. Cached-run's `xargs -P 1`
remains serial; multi-job invocations keep both existing flags. This differs
from the rejected method, which removed all job flags. No caller or test
selection changes are proposed.

Predict the previously observed three rejected Make recipes become 3/3 passing
serial recipes, including the separate heavy-run and doctor ordering paths.
The three multi-job recipes keep their existing arguments and all selected
files. Predict two real one-job Bats smoke files each run exactly once; no
parallel-only option reaches Bats at one job. Preserve all existing scheduler
and no-GNU-parallel controls.

After this prediction is committed, run this exact one-shot preflight. It
pins the already inspected tool paths, creates a new private receipt, restricts
PATH to the resolved helpers and system tools, denies network, and runs only
one synthetic named test. A missing or changed executable, existing receipt,
failed command, skip, ambiguous output or missing receipt rejects admission.
Do not repeat this preflight to seek a pass.

```sh
/usr/bin/env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin JOBS=1 \
  "$HOME/apps/tooling/dotfiles/bin/heavy-run" /bin/bash -s <<'BASH'
set -euo pipefail
umask 077
receipt="$HOME/.local/state/dotfiles/experiments/bats-explicit-one-v1"
mkdir -p "$(dirname "$receipt")"
mkdir "$receipt"
runner=/opt/homebrew/Cellar/bats-core/1.14.0/bin/bats
readlink_cmd=/opt/homebrew/Cellar/coreutils/9.12_1/bin/greadlink
parallel_cmd=/opt/homebrew/Cellar/parallel/20261022/bin/parallel
for tool in "$runner" "$readlink_cmd" "$parallel_cmd"; do
  [ -x "$tool" ] || exit 2
done
cat > "$receipt/tools.sha" <<'SHA'
b036dd11d2d22ff82a191233429f9d3e33c62ec6d3e6769243e7dfa3e7ca9908  /opt/homebrew/Cellar/bats-core/1.14.0/bin/bats
ab8b53a4e61176a26f78130072ddae36a086bd5ed47a296902a9d0f5bee086ff  /opt/homebrew/Cellar/coreutils/9.12_1/bin/greadlink
eada0ea72ef23e82955c41f934fda87512b4b6ab0baf849884371dca123c19c0  /opt/homebrew/Cellar/parallel/20261022/bin/parallel
SHA
shasum -a 256 -c "$receipt/tools.sha"
runtime_hash() {
  /usr/bin/find /opt/homebrew/Cellar/bats-core/1.14.0/lib /opt/homebrew/Cellar/bats-core/1.14.0/libexec -type f -print |
    LC_ALL=C sort | xargs shasum -a 256 | shasum -a 256 | awk '{print $1}'
}
[ "$(runtime_hash)" = e7b4707267f9a793c3894cb5113a185a84ea40be34d34b1f537c169d7b30522c ]
mkdir -p "$receipt/bin" "$receipt/home/.config" "$receipt/tmp"
ln -s "$readlink_cmd" "$receipt/bin/greadlink"
ln -s "$parallel_cmd" "$receipt/bin/parallel"
printf '#!/usr/bin/env bats\n@test "explicit_one_job" { :; }\n' > "$receipt/smoke.bats"
case "$receipt" in *[!A-Za-z0-9/._-]*) exit 2 ;; esac
profile="(version 1)(allow default)(deny network*)(deny file-write*)(allow file-write* (subpath \"$receipt\") (literal \"/dev/null\"))"
safe_exec() {
  env -i HOME="$receipt/home" TMPDIR="$receipt/tmp" XDG_CONFIG_HOME="$receipt/home/.config" LANG=C \
    PATH="$receipt/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    /usr/bin/sandbox-exec -p "$profile" "$@"
}
safe_exec "$runner" --version > "$receipt/bats-version"
grep -Fxq 'Bats 1.14.0' "$receipt/bats-version"
safe_exec "$parallel_cmd" --version > "$receipt/parallel-version"
grep -Fq 'GNU parallel' "$receipt/parallel-version"
set +e
safe_exec "$runner" --jobs 1 "$receipt/smoke.bats" > "$receipt/output" 2>&1
result=$?
set -e
printf '%s\n' "$result" > "$receipt/status"
[ "$result" -eq 0 ]
printf '1..1\nok 1 explicit_one_job\n' > "$receipt/expected"
cmp -s "$receipt/expected" "$receipt/output"
shasum -a 256 -c "$receipt/tools.sha"
[ "$(runtime_hash)" = e7b4707267f9a793c3894cb5113a185a84ea40be34d34b1f537c169d7b30522c ]
printf 'Private preflight receipt: %s\n' "$receipt"
BASH
```

Only after the preflight passes, adapt the preserved candidate to this new
method in a clean worktree at default-branch commit
`b25e8937520b6ec5e609262ec1fef53ec2f10f9f`. Preserve the
rejected uncommitted candidate in its original worktree and keep the original
red logs as baseline. Parameterize the existing
scheduler's one- and multi-job cases, preserve target-specific rejection and
heavy-run markers, and keep a real-Bats smoke bound to the actual Make recipe
arguments. The smoke must use a clean environment, scratch HOME/config/temp,
the same pinned `greadlink` and GNU parallel in its restricted PATH, and a
Darwin sandbox that denies network and writes outside the owned fixture (and
`/dev/null`). Recheck the pinned tool and Bats runtime hashes before and after.
It must prove real Bats receives `--jobs 1` without the incompatible flag,
executes two named tests with two `1..1` plans, and does not use the fake
runner. A fake cached-run wrapper may record arguments but must delegate to the
real copied cached-run. All three actual Make targets must complete selected
peers exactly once; `test` must also execute the isolated heavy-run file and
run doctor last. Multi-job controls must check both Bats and cached-run flags.

After the focused controls pass, remove the completed one-job task block in
the same change. Run the full scheduler suite and the real fresh repository gate:

```sh
JOBS=1 heavy-run bats tests/makefile-bats-jobs.bats
cache=$(mktemp -d)
env -u BATS_JOBS -u TEST_FILE_JOBS JOBS=1 CACHED_RUN_DIR="$cache" heavy-run make check
```

Require all scheduler cases to pass, 3/3 one-job and 3/3 multi-job targets,
real Bats smoke, exact selected-file/doctor/heavy-run coverage, and fresh
repository gate success. Save the exact selector and compare it to per-file
results; require a nonempty selection including the scheduler test, zero cache
hits, plugin results and stable hashes of every changed file. Existing platform
skips are disclosed, never counted as passes. Any semantic miss, invalid flag,
wrong binary, missing test, extra or skipped selected file, safety regression
or gate failure rejects this candidate. Preserve evidence and redesign; a
setup failure is not a pass. Independent review verifies the final commit.

Anchor: Bats parallel execution documentation
https://bats-core.readthedocs.io/en/stable/usage.html#parallel-execution;
Basili, Caldiera and Rombach (1994), Goal Question Metric; Munafò et al.
(2017), preregistration.

## One-shot preflight result

The registered preflight exited 1 before the named test passed. Bats
preprocessing and tracing reported `Operation not permitted` while creating
here-document temporary files; its TAP output reported `not ok 1
bats-gather-tests`. The private receipt contains the status, output, tool
hashes and version records. The post-run checks were not reached. The denied
path is unknown. This consumes the one-shot admission and rejects the
candidate; it does not establish whether one-job Bats works outside that
containment. Preserve the receipt and do not retry the method.
