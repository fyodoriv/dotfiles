#!/usr/bin/env bats

setup() {
  TEST_DIR="$(mktemp -d)"
  mkdir -p "$TEST_DIR/bin" "$TEST_DIR/log"
  export PATH="$TEST_DIR/bin:$PATH"
  export HOME="$TEST_DIR"
  export DOTFILES_FOCUS_STEAL_LOG="$TEST_DIR/log/focus-steal.log"
  RESTORE_SCRIPT="$BATS_TEST_DIRNAME/../bin/dotfiles-restore-focus-after-chrome"
  chmod +x "$RESTORE_SCRIPT"

  cat > "$TEST_DIR/bin/osascript" <<'MOCK'
#!/bin/bash
case "$*" in
  *"get name of first application process whose frontmost is true"*)
    echo "${MOCK_FRONTMOST:-Cursor}"
    ;;
  *'to activate'*|*'set visible to false'*)
    echo "forbidden osascript: $*" >&2
    exit 1
    ;;
  *)
    echo "unexpected osascript: $*" >&2
    exit 1
    ;;
esac
MOCK
  chmod +x "$TEST_DIR/bin/osascript"
  export MOCK_FRONTMOST
  : > "$DOTFILES_FOCUS_STEAL_LOG"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "capture-frontmost prints current frontmost app name" {
  export MOCK_FRONTMOST="Cursor"
  run "$RESTORE_SCRIPT" --capture-frontmost
  [ "$status" -eq 0 ]
  [ "$output" = "Cursor" ]
}

@test "log-if-chrome-frontmost appends log when Chrome is frontmost (never hides)" {
  export MOCK_FRONTMOST="Google Chrome"
  run "$RESTORE_SCRIPT" --log-if-chrome-frontmost "Cursor"
  [ "$status" -eq 0 ]
  grep -q 'current=Google\\ Chrome' "$DOTFILES_FOCUS_STEAL_LOG"
  grep -q 'prev=Cursor' "$DOTFILES_FOCUS_STEAL_LOG"
}

@test "log-if-chrome-frontmost is a no-op when Chrome did not become frontmost" {
  export MOCK_FRONTMOST="Cursor"
  run "$RESTORE_SCRIPT" --log-if-chrome-frontmost "Cursor"
  [ "$status" -eq 0 ]
  [ ! -s "$DOTFILES_FOCUS_STEAL_LOG" ]
}

@test "log-if-chrome-frontmost is a no-op when AGENT_BROWSER_ALLOW_FOCUS is set" {
  export MOCK_FRONTMOST="Google Chrome"
  export AGENT_BROWSER_ALLOW_FOCUS=1
  run "$RESTORE_SCRIPT" --log-if-chrome-frontmost "Cursor"
  [ "$status" -eq 0 ]
  [ ! -s "$DOTFILES_FOCUS_STEAL_LOG" ]
}

@test "legacy positional arg logs only (no hide, no activate)" {
  export MOCK_FRONTMOST="Google Chrome"
  run "$RESTORE_SCRIPT" "Cursor"
  [ "$status" -eq 0 ]
  grep -q 'Google\\ Chrome' "$DOTFILES_FOCUS_STEAL_LOG"
}
