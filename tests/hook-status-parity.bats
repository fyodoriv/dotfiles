#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  OLD_DIR="$BATS_TEST_TMPDIR/old"
  RUN_DIR="$BATS_TEST_TMPDIR/runner"
  mkdir -p "$OLD_DIR" "$RUN_DIR"
  git -C "$ROOT" show 2b531529bb9bc6b787363aa96afc689b8940ff4e:agent-hooks/block-dangerous-git.sh > "$OLD_DIR/block-dangerous-git.sh"
  cp "$ROOT/agent-hooks/bootstrap-endpoint-path.sh" "$ROOT/agent-hooks/plain-document-write.jq" "$ROOT/agent-hooks/literal-status-only.sh" "$RUN_DIR/"
  export DOTFILES_DIR="$ROOT"
}

@test "literal status cases bypass the cwd extraction" {
  [ -x /usr/bin/plutil ] || skip "requires macOS plutil"
  local command extracted
  for command in 'git status' 'git status --short' 'git status -s -b' 'git status --porcelain=v1' 'git status --long --branch'; do
    jq -n --arg c "$command" '{tool_input:{command:$c},cwd:"/tmp"}' > "$BATS_TEST_TMPDIR/input"
    extracted=$(/usr/bin/plutil -extract tool_input.command raw -o - -- "$BATS_TEST_TMPDIR/input" 2>/dev/null || true)
    [ "$extracted" = "$command" ] || skip "requires macOS plutil extraction"
    compare_payload "$BATS_TEST_TMPDIR/input"
    run /bin/bash -x "$ROOT/agent-hooks/block-dangerous-git.sh" < "$BATS_TEST_TMPDIR/input"
    [ "$status" -eq 0 ]
    [[ "$output" != *'+ hook_cwd='* ]]
  done
}

@test "hostile and unknown status syntax follows the old guard" {
  [ -x /usr/bin/plutil ] || skip "requires macOS plutil"
  local command extracted
  for command in 'git status --unknown' 'git status; git reset --hard' 'git status $(git reset --hard)' 'git status > /tmp/out' 'git status --short # comment' "git status '" 'git status --short*' 'git -C /tmp status' $'git status\t--short' $'git status\n--short'; do
    jq -n --arg c "$command" '{tool_input:{command:$c},cwd:"/tmp"}' > "$BATS_TEST_TMPDIR/input"
    extracted=$(/usr/bin/plutil -extract tool_input.command raw -o - -- "$BATS_TEST_TMPDIR/input" 2>/dev/null || true)
    [ "$extracted" = "$command" ] || skip "requires macOS plutil extraction"
    compare_payload "$BATS_TEST_TMPDIR/input"
    run /bin/bash -x "$ROOT/agent-hooks/block-dangerous-git.sh" < "$BATS_TEST_TMPDIR/input"
    [[ "$output" == *'+ hook_cwd='* ]]
  done
}

compare_payload() {
  local payload="$1" old_status new_status
  cp "$OLD_DIR/block-dangerous-git.sh" "$RUN_DIR/block-dangerous-git.sh"
  if /bin/bash "$RUN_DIR/block-dangerous-git.sh" < "$payload" > "$BATS_TEST_TMPDIR/old.out" 2> "$BATS_TEST_TMPDIR/old.err"; then old_status=0; else old_status=$?; fi
  cp "$ROOT/agent-hooks/block-dangerous-git.sh" "$RUN_DIR/block-dangerous-git.sh"
  if /bin/bash "$RUN_DIR/block-dangerous-git.sh" < "$payload" > "$BATS_TEST_TMPDIR/new.out" 2> "$BATS_TEST_TMPDIR/new.err"; then new_status=0; else new_status=$?; fi
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
  for input in '' '{' '{}' '{"tool_input":{}}' '{"tool_input":{"command":null}}' '{"tool_input":{"command":true}}' '{"tool_input":{"command":["git status"]}}'; do
    printf '%s' "$input" > "$BATS_TEST_TMPDIR/input"
    compare_payload "$BATS_TEST_TMPDIR/input"
  done
}

@test "status parity holds with scratch and spoofed tools" {
  local tool
  mkdir -p "$BATS_TEST_TMPDIR/fakes" "$BATS_TEST_TMPDIR/home" "$BATS_TEST_TMPDIR/dotfiles/bin" "$BATS_TEST_TMPDIR/dotfiles/lib"
  cp "$ROOT/lib/dotfiles-endpoint-paths.sh" "$BATS_TEST_TMPDIR/dotfiles/lib/"
  jq -n '{tool_input:{command:"git status --short"},cwd:"/missing"}' > "$BATS_TEST_TMPDIR/input"
  export HOME="$BATS_TEST_TMPDIR/home"
  export DOTFILES_DIR="$BATS_TEST_TMPDIR/dotfiles"
  export PATH="/usr/bin:/bin"
  compare_payload "$BATS_TEST_TMPDIR/input"
  export HOOK_MARKER="$BATS_TEST_TMPDIR/unexpected-tool-call"
  for tool in git gh jq shfmt rg perl; do
    printf '#!/bin/sh\nprintf invoked >> "$HOOK_MARKER"\nexit 99\n' > "$BATS_TEST_TMPDIR/fakes/$tool"
    chmod +x "$BATS_TEST_TMPDIR/fakes/$tool"
  done
  export PATH="$BATS_TEST_TMPDIR/fakes:/usr/bin:/bin"
  for tool in git gh jq shfmt rg perl; do
    run /bin/bash -c 'source "$1"; command -v "$2"' _ "$ROOT/agent-hooks/bootstrap-endpoint-path.sh" "$tool"
    [ "$status" -eq 0 ]
    [ "$output" = "$BATS_TEST_TMPDIR/fakes/$tool" ]
  done
  compare_payload "$BATS_TEST_TMPDIR/input"
  [ ! -e "$HOOK_MARKER" ]
}

@test "a missing status helper falls back to the old guard" {
  jq -n '{tool_input:{command:"git status"},cwd:"/tmp"}' > "$BATS_TEST_TMPDIR/input"
  rm "$RUN_DIR/literal-status-only.sh"
  compare_payload "$BATS_TEST_TMPDIR/input"
}

@test "installed hook links its status helper and uses it" {
  [ -x /usr/bin/plutil ] || skip "requires macOS plutil"
  local repo="$BATS_TEST_TMPDIR/repo" home="$BATS_TEST_TMPDIR/home" hooks
  mkdir -p "$repo/agent-hooks" "$repo/lib" "$repo/bin" "$home"
  cp "$ROOT/agent-hooks/"* "$repo/agent-hooks/"
  cp "$ROOT/lib/dotfiles-endpoint-paths.sh" "$repo/lib/"
  run env HOME="$home" CHEZMOI_SOURCE_DIR="$repo" /bin/bash "$ROOT/.chezmoiscripts/run_after_agent-hooks.sh"
  [ "$status" -eq 0 ]
  hooks="$home/.config/dotfiles/hooks"
  [ -L "$hooks/literal-status-only.sh" ]
  jq -n '{tool_input:{command:"git status"},cwd:"/tmp"}' > "$BATS_TEST_TMPDIR/input"
  run env HOME="$home" DOTFILES_DIR="$repo" /bin/bash -x "$hooks/block-dangerous-git.sh" < "$BATS_TEST_TMPDIR/input"
  [ "$status" -eq 0 ]
  [[ "$output" != *'+ hook_cwd='* ]]
  jq -n '{tool_input:{command:"git status; git reset --hard"},cwd:"/tmp"}' > "$BATS_TEST_TMPDIR/input"
  run env HOME="$home" DOTFILES_DIR="$repo" /bin/bash -x "$hooks/block-dangerous-git.sh" < "$BATS_TEST_TMPDIR/input"
  [ "$status" -eq 2 ]
  [[ "$output" == *'+ hook_cwd='* ]]
}
