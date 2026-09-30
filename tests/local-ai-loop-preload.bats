#!/usr/bin/env bats
# Pin the file-preload behaviour in lib/local-ai-loop.py's
# build_prompt(). Surfaced in run-5 that the agent was spending 5 of
# its 14 turns running `ls` / `cat` on files the task had already
# named. Preload puts those contents directly in the initial prompt.

REPO_ROOT="$BATS_TEST_DIRNAME/.."

_prompt() {
  local task_files="$1"
  local cwd="$2"
  python3 - "$task_files" "$cwd" "$REPO_ROOT" <<'PY'
import importlib.util, sys, os
files, cwd, root = sys.argv[1], sys.argv[2], sys.argv[3]
spec = importlib.util.spec_from_file_location(
    "loop", os.path.join(root, "lib", "local-ai-loop.py"),
)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
task = {
    "id": "test-task", "priority": "P2", "title": "Test",
    "details": "details here", "files": files, "acceptance": "passes",
}
p = m.build_prompt(task, cwd=cwd)
sys.stdout.write(p)
PY
}

setup() { TMP=$(mktemp -d); }
teardown() { rm -rf "$TMP"; }

@test "preload: named file is read into the prompt" {
  mkdir -p "$TMP/lib"
  echo "hello from the file" > "$TMP/lib/example.py"
  run _prompt "lib/example.py" "$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Pre-loaded file contents"* ]]
  [[ "$output" == *"===== lib/example.py"* ]]
  [[ "$output" == *"hello from the file"* ]]
}

@test "preload: missing file is silently skipped" {
  run _prompt "lib/nonexistent.py" "$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Pre-loaded file contents"* ]]
}

@test "preload: multiple files in a comma-separated list" {
  mkdir -p "$TMP/a" "$TMP/b"
  echo "content A" > "$TMP/a/1.txt"
  echo "content B" > "$TMP/b/2.txt"
  run _prompt "a/1.txt, b/2.txt" "$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"content A"* ]]
  [[ "$output" == *"content B"* ]]
}

@test "preload: large file is truncated" {
  mkdir -p "$TMP/docs"
  python3 -c "
with open('$TMP/docs/big.md', 'w') as f:
    f.write('X' * 20000)
"
  run _prompt "docs/big.md" "$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"truncated"* ]]
  # Total output length should not include all 20000 X's
  local size
  size=$(printf '%s' "$output" | wc -c | tr -d ' ')
  [ "$size" -lt 15000 ]
}

@test "preload: no files field means no preload" {
  run _prompt "" "$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Pre-loaded file contents"* ]]
}

@test "preload: picks up paths embedded in prose" {
  mkdir -p "$TMP/modules/foo"
  echo "doctor content" > "$TMP/modules/foo/doctor.sh"
  # The Files: metadata is prose like "modules/foo/doctor.sh and tests/foo.bats"
  run _prompt "modules/foo/doctor.sh and tests/foo.bats" "$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"doctor content"* ]]
}
