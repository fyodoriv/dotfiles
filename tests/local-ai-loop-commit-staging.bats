#!/usr/bin/env bats
# Pin lib/local-ai-loop.py commit_if_dirty staging behavior. Surfaced
# after PRs #24-#26 where the agent's write_file output (the actual
# task deliverable — a new bats test file) stayed untracked while the
# loop committed only the TASKS.md edit. The PR descriptions claimed
# the test files shipped; they didn't. Discovered when reviewing
# main after merging.

REPO_ROOT="$BATS_TEST_DIRNAME/.."

_commit_dirty() {
  local cwd="$1"
  python3 - "$cwd" "$REPO_ROOT" <<'PY'
import importlib.util, sys, os
cwd, root = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location(
    "loop", os.path.join(root, "lib", "local-ai-loop.py"),
)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print("committed:", m.commit_if_dirty(cwd, "test-task"))
PY
}

setup() {
  TMP=$(mktemp -d)
  cd "$TMP"
  git init -q
  git config user.email "t@x.com"
  git config user.name "t"
  git config core.hooksPath /dev/null
  mkdir -p tests lib
  echo "seed" > seed.txt
  git add -A && git commit -q --no-verify -m "feat: seed"
}

teardown() { cd /; rm -rf "$TMP"; }

@test "commit_if_dirty: stages an untracked test file in tests/" {
  echo '@test "x" { [ 1 -eq 1 ]; }' > tests/new.bats
  run _commit_dirty "$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"committed: True"* ]]
  # Verify it actually got committed
  git ls-tree HEAD tests/new.bats | grep -q "new.bats"
}

@test "commit_if_dirty: stages tracked-modified files in lib/" {
  echo "original" > lib/foo.sh
  git add lib/foo.sh && git commit -q --no-verify -m "feat: add foo"
  echo "modified" > lib/foo.sh
  run _commit_dirty "$TMP"
  [[ "$output" == *"committed: True"* ]]
  git show HEAD:lib/foo.sh | grep -q "modified"
}

@test "commit_if_dirty: returns False on clean repo" {
  run _commit_dirty "$TMP"
  [[ "$output" == *"committed: False"* ]]
}

@test "commit_if_dirty: does NOT stage untracked files outside safe prefixes" {
  mkdir -p scratch
  echo "user notes" > scratch/notes.md
  run _commit_dirty "$TMP"
  [[ "$output" == *"committed: False"* ]]
  # The scratch file is still untracked / preserved
  [ -f scratch/notes.md ]
  ! git ls-files scratch/notes.md | grep -q .
}

@test "commit_if_dirty: PRESERVES docs/audits/local-ai-runs.csv (never auto-commits telemetry)" {
  mkdir -p docs/audits
  echo "ts,model,outcome" > docs/audits/local-ai-runs.csv
  echo "@test \"y\" { [ 1 -eq 1 ]; }" > tests/needs-commit.bats
  run _commit_dirty "$TMP"
  [[ "$output" == *"committed: True"* ]]
  # CSV stayed untracked
  ! git ls-files docs/audits/local-ai-runs.csv | grep -q .
  # but the bats test got committed
  git ls-files tests/needs-commit.bats | grep -q .
}

@test "commit_if_dirty: stages multiple files (the real-world dogfood shape)" {
  # Simulates: TASKS.md modified + tests/foo.bats new file
  echo "modified seed" > seed.txt
  git add seed.txt && git commit -q --no-verify -m "feat: tracked"
  echo "tasks-modified" > seed.txt
  echo "@test \"z\" { [ 1 -eq 1 ]; }" > tests/foo.bats
  run _commit_dirty "$TMP"
  [[ "$output" == *"committed: True"* ]]
  # Only ONE commit (atomically combining the two changes)
  [ "$(git log --oneline | wc -l | tr -d ' ')" = "3" ]
  git ls-tree HEAD tests/foo.bats | grep -q "foo.bats"
}
