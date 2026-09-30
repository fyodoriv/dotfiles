#!/usr/bin/env bats
# Pin lib/local-ai-loop.py's pre-merge reviewer gate. Surfaced in PRs
# #24-#26: the loop closed tasks whose commit didn't contain the
# declared deliverable (agent wrote nothing / wrong path), so PR
# descriptions claimed files shipped that never existed on main. The
# reviewer pass compares the close commit's paths against the task's
# `**Files**:` field and refuses the close when a declared path is
# missing (see docs/plans/local-ai-loop-pre-merge-reviewer.md).

REPO_ROOT="$BATS_TEST_DIRNAME/.."

# Print the JSON list returned by reviewer_missing_files for a task
# whose Files field is $2, against the fixture repo $1.
# $3 is "True"/"False" for the committed flag.
_missing() {
  local cwd="$1" files_field="$2" committed="$3"
  python3 - "$cwd" "$REPO_ROOT" "$files_field" "$committed" <<'PY'
import importlib.util, json, sys, os
cwd, root, files_field, committed = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
spec = importlib.util.spec_from_file_location(
    "loop", os.path.join(root, "lib", "local-ai-loop.py"),
)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
task = {"id": "test-task", "files": files_field}
print("missing:", json.dumps(m.reviewer_missing_files(cwd, task, committed == "True")))
PY
}

_reject_close() {
  local cwd="$1" committed="$2"
  python3 - "$cwd" "$REPO_ROOT" "$committed" <<'PY'
import importlib.util, sys, os
cwd, root, committed = sys.argv[1], sys.argv[2], sys.argv[3]
spec = importlib.util.spec_from_file_location(
    "loop", os.path.join(root, "lib", "local-ai-loop.py"),
)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.reviewer_reject_close(cwd, "test-task", committed == "True")
print("rejected: ok")
PY
}

setup() {
  TMP=$(mktemp -d)
  cd "$TMP"
  git init -q
  git config user.email "t@x.com"
  git config user.name "t"
  git config core.hooksPath /dev/null
  # The host's global excludes file may ignore TASKS.md (real queues are
  # repo-tracked; some hosts ignore stray copies). The fixture needs it
  # tracked, so disable global excludes inside the tmp repo.
  git config core.excludesFile /dev/null
  mkdir -p tests lib
  printf '%s\n' "# Tasks" "" "## P0" "" \
    "- [ ] Test task" \
    "  - **ID**: test-task" \
    "  - **Files**: tests/foo.bats" > TASKS.md
  echo "original" > lib/foo.sh
  git add -- TASKS.md lib/foo.sh && git commit -q --no-verify -m "feat: seed"
}

teardown() { cd /; rm -rf "$TMP"; }

_commit_paths() {
  # Commit the given paths (creating files as needed) as one close commit.
  for p in "$@"; do
    mkdir -p "$(dirname "$p")"
    echo "content" > "$p"
    git add -- "$p"
  done
  git commit -q --no-verify -m "chore(local-ai-loop): test-task"
}

@test "reviewer: green path — declared exact path present in HEAD" {
  _commit_paths tests/foo.bats
  run _missing "$TMP" "tests/foo.bats" True
  [ "$status" -eq 0 ]
  [[ "$output" == *'missing: []'* ]]
}

@test "reviewer: annotation prose around the path is ignored" {
  _commit_paths tests/foo.bats
  run _missing "$TMP" "tests/foo.bats (new)" True
  [[ "$output" == *'missing: []'* ]]
}

@test "reviewer: glob entry satisfied by matching committed file" {
  _commit_paths tests/local-ai-loop-reviewer.bats
  run _missing "$TMP" "tests/local-ai-loop-*.bats" True
  [[ "$output" == *'missing: []'* ]]
}

@test "reviewer: glob does not cross directory separators" {
  _commit_paths tests/subdir/foo.bats
  run _missing "$TMP" "tests/*.bats" True
  [[ "$output" == *'missing: ["tests/*.bats"]'* ]]
}

@test "reviewer: directory entry satisfied one-way by contained file" {
  _commit_paths tests/foo.bats
  run _missing "$TMP" "tests/" True
  [[ "$output" == *'missing: []'* ]]
}

@test "reviewer: declared file not satisfied by sibling in same directory" {
  _commit_paths tests/bar.bats
  run _missing "$TMP" "tests/foo.bats" True
  [[ "$output" == *'missing: ["tests/foo.bats"]'* ]]
}

@test "reviewer: missing declared file is reported" {
  _commit_paths lib/other.sh
  run _missing "$TMP" "tests/foo.bats" True
  [[ "$output" == *'missing: ["tests/foo.bats"]'* ]]
}

@test "reviewer: empty, absent, and prose-only Files fields all pass" {
  _commit_paths lib/other.sh
  run _missing "$TMP" "" True
  [[ "$output" == *'missing: []'* ]]
  # Absent field: read_tasks-style dict without files key
  run python3 - "$TMP" "$REPO_ROOT" <<'PY'
import importlib.util, json, sys, os
cwd, root = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location(
    "loop", os.path.join(root, "lib", "local-ai-loop.py"),
)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print("missing:", json.dumps(m.reviewer_missing_files(cwd, {"id": "t"}, True)))
PY
  [[ "$output" == *'missing: []'* ]]
  run _missing "$TMP" "wire the gate into the loop after commit" True
  [[ "$output" == *'missing: []'* ]]
}

@test "reviewer: declared TASKS.md is auto-satisfied" {
  echo "tweak" >> TASKS.md
  git add -- TASKS.md
  git commit -q --no-verify -m "chore(local-ai-loop): test-task"
  run _missing "$TMP" "TASKS.md, tests/foo.bats" True
  [[ "$output" == *'missing: ["tests/foo.bats"]'* ]]
}

@test "reviewer: committed=False with declared files reports all missing" {
  run _missing "$TMP" "tests/foo.bats, lib/foo.sh" False
  [[ "$output" == *'missing: ["tests/foo.bats", "lib/foo.sh"]'* ]]
}

@test "reviewer: reject_close rolls back the close commit safely" {
  seed_sha=$(git rev-parse HEAD)
  block_line='  - **ID**: test-task'
  # Simulate the loop's close: remove the task block, modify a tracked
  # file, leave an untracked agent artifact, commit TASKS.md + lib only.
  printf '%s\n' "# Tasks" "" "## P0" > TASKS.md
  echo "modified" > lib/foo.sh
  echo '@test "x" { [ 1 -eq 1 ]; }' > tests/new-task.bats
  git add -- TASKS.md lib/foo.sh
  git commit -q --no-verify -m "chore(local-ai-loop): test-task"

  run _reject_close "$TMP" True
  [ "$status" -eq 0 ]
  [[ "$output" == *"rejected: ok"* ]]
  # (a) HEAD rewound to the pre-close commit
  [ "$(git rev-parse HEAD)" = "$seed_sha" ]
  # (b) TASKS.md block restored
  grep -qF "$block_line" TASKS.md
  # (c) untracked agent artifact deleted
  [ ! -f tests/new-task.bats ]
  # (d) tracked modification reverted
  grep -qx "original" lib/foo.sh
  # (e) index empty
  git diff --cached --quiet
}
