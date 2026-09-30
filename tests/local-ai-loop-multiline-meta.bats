#!/usr/bin/env bats
# Pin the multi-line metadata parser in lib/local-ai-loop.py. Surfaced
# in P0 attempts 1-8 that the original parser read only the first line
# of each **Details**: / **Acceptance**: field, dropping the crucial
# "3 @test cases" sentence that lived on line 3. This made the
# critic's count-check a no-op on real tasks.

REPO_ROOT="$BATS_TEST_DIRNAME/.."

_parse_p0() {
  local tasks_md="$1"
  python3 - "$tasks_md" "$REPO_ROOT" <<'PY'
import importlib.util, sys, os
tasks_md, root = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location(
    "loop", os.path.join(root, "lib", "local-ai-loop.py"),
)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
tasks = m.read_tasks(tasks_md)
found = False
for t in tasks:
    if t["priority"] == "P0":
        print("ID:", t["id"])
        print("DETAILS:", t["details"])
        print("ACCEPTANCE:", t["acceptance"])
        found = True
        break
if not found:
    print("NO P0")
PY
}

setup() { TMP=$(mktemp -d); }
teardown() { rm -rf "$TMP"; }

@test "parser: multi-line Details field concatenates continuation lines" {
  cat > "$TMP/TASKS.md" <<'EOF'
# Tasks

## P0

- [ ] Example task
  - **ID**: example-id
  - **Tags**: tests
  - **Details**: First line of details.
    Second line should be concatenated.
    Third line too, including the literal "3 @test cases".
  - **Files**: tests/foo.bats
  - **Acceptance**: passes.

## P1
EOF
  run _parse_p0 "$TMP/TASKS.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"First line"* ]]
  [[ "$output" == *"Second line should be concatenated"* ]]
  [[ "$output" == *"Third line too"* ]]
  [[ "$output" == *"3 @test cases"* ]]
}

@test "parser: multi-line Acceptance field concatenates too" {
  cat > "$TMP/TASKS.md" <<'EOF'
# Tasks

## P0

- [ ] Example task
  - **ID**: example-id
  - **Tags**: tests
  - **Details**: short.
  - **Files**: foo.bats
  - **Acceptance**: First condition:
    passes make check AND
    runs 3 bats tests without skips.

## P1
EOF
  run _parse_p0 "$TMP/TASKS.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"passes make check"* ]]
  [[ "$output" == *"runs 3 bats tests"* ]]
}

@test "parser: next meta bullet terminates the previous field" {
  cat > "$TMP/TASKS.md" <<'EOF'
# Tasks

## P0

- [ ] Ex
  - **ID**: ex
  - **Details**: A
    B
  - **Files**: f.py
  - **Acceptance**: OK
EOF
  run _parse_p0 "$TMP/TASKS.md"
  [[ "$output" == *"DETAILS: A B"* ]]
  [[ "$output" == *"ACCEPTANCE: OK"* ]]
}

@test "parser: blank line terminates the continuation" {
  cat > "$TMP/TASKS.md" <<'EOF'
# Tasks

## P0

- [ ] Ex
  - **ID**: ex
  - **Details**: Only
    one
    block

    (new paragraph, should not be part of Details)
  - **Acceptance**: ok
EOF
  run _parse_p0 "$TMP/TASKS.md"
  [[ "$output" == *"DETAILS: Only one block"* ]]
  # The "new paragraph" is NOT part of details.
  [[ "$output" != *"new paragraph"* ]]
}
