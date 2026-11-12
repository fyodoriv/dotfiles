#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  OLD_DIR="$BATS_TEST_TMPDIR/old"
  mkdir -p "$OLD_DIR"
  git -C "$ROOT" show e0e470cbf8809a55d5d2f0db89ba5a4211b0f4b4:agent-hooks/block-dangerous-git.sh > "$OLD_DIR/block-dangerous-git.sh"
  cp "$ROOT/agent-hooks/bootstrap-endpoint-path.sh" "$ROOT/agent-hooks/plain-document-write.jq" "$OLD_DIR/"
  export DOTFILES_DIR="$ROOT"
}

compare_payload() {
  local payload="$1" old_status new_status
  if bash "$OLD_DIR/block-dangerous-git.sh" < "$payload" > "$BATS_TEST_TMPDIR/old.out" 2> "$BATS_TEST_TMPDIR/old.err"; then old_status=0; else old_status=$?; fi
  if bash "$ROOT/agent-hooks/block-dangerous-git.sh" < "$payload" > "$BATS_TEST_TMPDIR/new.out" 2> "$BATS_TEST_TMPDIR/new.err"; then new_status=0; else new_status=$?; fi
  [ "$old_status" -eq "$new_status" ]
  cmp "$BATS_TEST_TMPDIR/old.out" "$BATS_TEST_TMPDIR/new.out"
  cmp "$BATS_TEST_TMPDIR/old.err" "$BATS_TEST_TMPDIR/new.err"
}

@test "status family keeps old hook decisions and output" {
  local command
  for command in 'git status' 'git status --short' 'git status -s -b' 'git status --porcelain=v1' 'git status --unknown'; do
    jq -n --arg c "$command" '{tool_input:{command:$c},cwd:"/tmp"}' > "$BATS_TEST_TMPDIR/input"
    compare_payload "$BATS_TEST_TMPDIR/input"
  done
}

@test "missing and malformed hook input keep old decisions and output" {
  local input
  for input in '' '{' '{}' '{"tool_input":{}}' '{"tool_input":{"command":null}}'; do
    printf '%s' "$input" > "$BATS_TEST_TMPDIR/input"
    compare_payload "$BATS_TEST_TMPDIR/input"
  done
}
