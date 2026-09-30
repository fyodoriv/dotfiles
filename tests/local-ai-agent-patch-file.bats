#!/usr/bin/env bats
# Pin the patch_file tool added to lib/local-ai-agent.py. Surfaced
# after run-5 where the agent destroyed git-hooks/pre-commit by
# writing a 345-byte stub over a 7089-byte file. The write_file guard
# now refuses such overwrites, but the agent still needs a way to
# EXTEND existing files — that's patch_file.

REPO_ROOT="$BATS_TEST_DIRNAME/.."

_patch() {
  local p="$1" mode="$2" old="$3" new="$4"
  python3 - "$p" "$mode" "$old" "$new" "$REPO_ROOT" <<'PY'
import importlib.util, sys, os
p, mode, old, new, root = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
spec = importlib.util.spec_from_file_location(
    "agent", os.path.join(root, "lib", "local-ai-agent.py"),
)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
r = m.run_patch_file(p, mode, old or None, new, os.path.dirname(p) or ".")
sys.stdout.write(r["stdout"])
sys.stderr.write(r["stderr"])
sys.exit(r["exit_code"])
PY
}

setup() { TMP=$(mktemp -d); }
teardown() { rm -rf "$TMP"; }

@test "patch_file replace: exact single-match substitution" {
  cat > "$TMP/hello.txt" <<'EOF'
hello world
this is a file
with multiple lines
EOF
  run _patch "$TMP/hello.txt" "replace" "hello world" "goodbye world"
  [ "$status" -eq 0 ]
  [[ "$(head -1 "$TMP/hello.txt")" = "goodbye world" ]]
  # Other lines unchanged
  grep -q "with multiple lines" "$TMP/hello.txt"
}

@test "patch_file replace: errors on no match" {
  cat > "$TMP/hello.txt" <<'EOF'
hello world
EOF
  run _patch "$TMP/hello.txt" "replace" "notthere" "something"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "patch_file replace: errors on multi-match (ambiguous)" {
  cat > "$TMP/hello.txt" <<'EOF'
foo
foo
foo
EOF
  run _patch "$TMP/hello.txt" "replace" "foo" "bar"
  [ "$status" -eq 1 ]
  [[ "$output" == *"matched 3 times"* ]]
}

@test "patch_file insert_after: inserts a new line after the anchor" {
  cat > "$TMP/script.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

main() {
  echo "hello"
}
EOF
  run _patch "$TMP/script.sh" "insert_after" "set -euo pipefail" "echo \"new line added\""
  [ "$status" -eq 0 ]
  # Verify the new line is on line 3 (after the anchor on line 2).
  [ "$(sed -n '3p' "$TMP/script.sh")" = 'echo "new line added"' ]
}

@test "patch_file append: adds content to EOF without losing existing" {
  cat > "$TMP/log.txt" <<'EOF'
original line 1
original line 2
EOF
  # Use $'...' ANSI-C quoting so \n becomes a real newline when passed
  # to the python harness (bash's "..." leaves \n as literal backslash-n).
  run _patch "$TMP/log.txt" "append" "" $'appended line\n'
  [ "$status" -eq 0 ]
  local lines
  lines=$(wc -l < "$TMP/log.txt" | tr -d ' ')
  [ "$lines" = "3" ]
  [ "$(tail -1 "$TMP/log.txt")" = "appended line" ]
}

@test "patch_file: errors on nonexistent file" {
  run _patch "$TMP/nonexistent.txt" "replace" "a" "b"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "patch_file: errors on unknown mode" {
  echo "hi" > "$TMP/x.txt"
  run _patch "$TMP/x.txt" "bogus" "a" "b"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown mode"* ]]
}

@test "patch_file: preserves a large file when doing a small patch" {
  # Mirror the run-5 scenario: existing 7089-byte-like file, need to
  # change ONE line. patch_file is the right tool.
  python3 -c "
with open('$TMP/big.sh', 'w') as f:
    for i in range(200):
        f.write(f'# comment line {i}\n')
    f.write('echo \"old line\"\n')
    for i in range(200, 400):
        f.write(f'# comment line {i}\n')
"
  local size_before
  size_before=$(wc -c < "$TMP/big.sh" | tr -d ' ')
  run _patch "$TMP/big.sh" "replace" "old line" "new line"
  [ "$status" -eq 0 ]
  local size_after
  size_after=$(wc -c < "$TMP/big.sh" | tr -d ' ')
  # File size should be about the same (±1 byte).
  [ "$((size_after - size_before))" -le 1 ]
  [ "$((size_before - size_after))" -le 1 ]
  # Old line is gone; new line is in.
  ! grep -q 'echo "old line"' "$TMP/big.sh"
  grep -q 'echo "new line"' "$TMP/big.sh"
  # ALL the surrounding context is still there.
  grep -q "comment line 0" "$TMP/big.sh"
  grep -q "comment line 399" "$TMP/big.sh"
}
