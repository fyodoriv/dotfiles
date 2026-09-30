#!/usr/bin/env bats
# Functional tests for cursor-priority — interactive/background scheduling

load test_helper

PRIORITY_CMD="$BATS_TEST_DIRNAME/../bin/cursor-priority"
REAL_DOTFILES="$BATS_TEST_DIRNAME/.."

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"
  TEST_BIN="$TEST_DIR/mockbin"

  mkdir -p "$TEST_HOME" "$TEST_DOTFILES" "$TEST_BIN"

  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"

  # Mock pgrep: logs calls, returns no processes by default
  cat > "$TEST_BIN/pgrep" <<'MOCK'
#!/bin/bash
echo "$@" >> "${PGREP_LOG:-/dev/null}"
exit 1
MOCK
  chmod +x "$TEST_BIN/pgrep"

  # Mock ps: no ancestry by default.
  cat > "$TEST_BIN/ps" <<'MOCK'
#!/bin/bash
case "$*" in
  *"comm="*) printf '%s\n' "${MOCK_PS_COMMAND:-}" ;;
  *"ppid="*) printf '%s\n' "${MOCK_PS_PPID:-}" ;;
esac
MOCK
  chmod +x "$TEST_BIN/ps"

  # Mock taskpolicy: logs calls
  cat > "$TEST_BIN/taskpolicy" <<'MOCK'
#!/bin/bash
echo "$@" >> "${TASKPOLICY_LOG:-/dev/null}"
MOCK
  chmod +x "$TEST_BIN/taskpolicy"

  # Mock renice: logs calls
  cat > "$TEST_BIN/renice" <<'MOCK'
#!/bin/bash
echo "$@" >> "${RENICE_LOG:-/dev/null}"
MOCK
  chmod +x "$TEST_BIN/renice"

  # Mock say (no-op)
  cat > "$TEST_BIN/say" <<'MOCK'
#!/bin/bash
exit 0
MOCK
  chmod +x "$TEST_BIN/say"

  export PGREP_LOG="$TEST_DIR/pgrep.log"
  export TASKPOLICY_LOG="$TEST_DIR/taskpolicy.log"
  export RENICE_LOG="$TEST_DIR/renice.log"
  touch "$PGREP_LOG" "$TASKPOLICY_LOG" "$RENICE_LOG"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── Script basics ────────────────────────────────────────────────

@test "cursor-priority script exists and is executable" {
  [ -f "$PRIORITY_CMD" ]
  [ -x "$PRIORITY_CMD" ]
}

@test "cursor-priority has correct shebang" {
  head -1 "$PRIORITY_CMD" | grep -q '#!/bin/bash'
}

# ── --help output ────────────────────────────────────────────────

@test "cursor-priority --help prints usage" {
  run "$PRIORITY_CMD" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"priority"* ]] || [[ "$output" == *"scheduling"* ]]
}

# ── Default process list (no config file) ────────────────────────

@test "cursor-priority runs without errors using defaults" {
  # Remove any config file, use mock bins so pgrep returns nothing
  rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/priority-apps.txt"
  run env PATH="$TEST_BIN:$PATH" "$PRIORITY_CMD"
  [ "$status" -eq 0 ]
}

@test "cursor-priority queries default processes via pgrep" {
  rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/priority-apps.txt"
  run env PATH="$TEST_BIN:$PATH" "$PRIORITY_CMD"
  [ "$status" -eq 0 ]
  # pgrep should have been called for Cursor, Slack, etc.
  grep -q "Cursor" "$PGREP_LOG"
  grep -q "Slack" "$PGREP_LOG"
}

@test "cursor-priority keeps Ghostty and WebStorm interactive by default" {
  rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/priority-apps.txt"
  run env PATH="$TEST_BIN:$PATH" "$PRIORITY_CMD"
  [ "$status" -eq 0 ]
  grep -q "ghostty" "$PGREP_LOG"
  grep -q "WebStorm" "$PGREP_LOG"
}

@test "cursor-priority queries minsky processes by pattern" {
  rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/priority-apps.txt"
  run env PATH="$TEST_BIN:$PATH" "$PRIORITY_CMD"
  [ "$status" -eq 0 ]
  grep -q "node.*minsky" "$PGREP_LOG"
}

# ── Config file support ──────────────────────────────────────────

@test "cursor-priority reads from config file" {
  local config_dir="$HOME/.config/dotfiles"
  mkdir -p "$config_dir"
  printf '%s\n' "Firefox" "kitty" > "$config_dir/priority-apps.txt"

  run env PATH="$TEST_BIN:$PATH" "$PRIORITY_CMD"
  [ "$status" -eq 0 ]
  grep -q "Firefox" "$PGREP_LOG"
  grep -q "kitty" "$PGREP_LOG"
}

@test "cursor-priority config file ignores comments and blank lines" {
  local config_dir="$HOME/.config/dotfiles"
  mkdir -p "$config_dir"
  printf '%s\n' "# comment" "" "Firefox" "  # another comment" "kitty" > "$config_dir/priority-apps.txt"

  run env PATH="$TEST_BIN:$PATH" "$PRIORITY_CMD"
  [ "$status" -eq 0 ]
  # Only Firefox and kitty should be queried, not "comment"
  ! grep -q "comment" "$PGREP_LOG"
  grep -q "Firefox" "$PGREP_LOG"
  grep -q "kitty" "$PGREP_LOG"
}

@test "cursor-priority config uses pgrep -f for patterns with dots or wildcards" {
  local config_dir="$HOME/.config/dotfiles"
  mkdir -p "$config_dir"
  printf '%s\n' "node.*myapp" "Exact" > "$config_dir/priority-apps.txt"

  run env PATH="$TEST_BIN:$PATH" "$PRIORITY_CMD"
  [ "$status" -eq 0 ]
  # "node.*myapp" has a dot → pgrep -f
  grep -q -- "-f" "$PGREP_LOG"
  # "Exact" → pgrep -x
  grep -q -- "-x" "$PGREP_LOG"
}

@test "cursor-priority with config does not use defaults" {
  local config_dir="$HOME/.config/dotfiles"
  mkdir -p "$config_dir"
  printf '%s\n' "CustomApp" > "$config_dir/priority-apps.txt"

  run env PATH="$TEST_BIN:$PATH" "$PRIORITY_CMD"
  [ "$status" -eq 0 ]
  grep -q "CustomApp" "$PGREP_LOG"
  ! grep -q "Cursor" "$PGREP_LOG"
  ! grep -q "Slack" "$PGREP_LOG"
}

# ── taskpolicy invocation ────────────────────────────────────────

@test "cursor-priority calls taskpolicy when processes are found" {
  local config_dir="$HOME/.config/dotfiles"
  mkdir -p "$config_dir"
  printf '%s\n' "bats" > "$config_dir/priority-apps.txt"

  # Mock pgrep to return a PID for "bats"
  cat > "$TEST_BIN/pgrep" <<'MOCK'
#!/bin/bash
echo "$@" >> "${PGREP_LOG:-/dev/null}"
# Return a fake PID for any process
echo "12345"
MOCK
  chmod +x "$TEST_BIN/pgrep"

  run env PATH="$TEST_BIN:$PATH" "$PRIORITY_CMD"
  [ "$status" -eq 0 ]
  # taskpolicy should have been called with -B -t 0 -l 0 -p 12345
  grep -q "\-B" "$TASKPOLICY_LOG"
  grep -q "12345" "$TASKPOLICY_LOG"
}

@test "cursor-priority backgrounds agent workers by default" {
  rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/priority-apps.txt"
  cat > "$TEST_BIN/pgrep" <<'MOCK'
#!/bin/bash
echo "$@" >> "${PGREP_LOG:-/dev/null}"
echo "12345"
MOCK
  chmod +x "$TEST_BIN/pgrep"

  run env PATH="$TEST_BIN:$PATH" "$PRIORITY_CMD"
  [ "$status" -eq 0 ]
  grep -q -- "-b -p 12345" "$TASKPOLICY_LOG"
  grep -q -- "10 -p 12345" "$RENICE_LOG"
  grep -q "ollama" "$PGREP_LOG"
  grep -q "mlx_lm.server" "$PGREP_LOG"
}

@test "cursor-priority keeps WebStorm Claude interactive" {
  rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/priority-apps.txt"
  cat > "$TEST_BIN/pgrep" <<'MOCK'
#!/bin/bash
echo "$@" >> "${PGREP_LOG:-/dev/null}"
case "$*" in
  *claude*) echo "12345" ;;
esac
MOCK
  chmod +x "$TEST_BIN/pgrep"

  cat > "$TEST_BIN/ps" <<'MOCK'
#!/bin/bash
case "$*" in
  *"12345"*"comm="*) echo "/Users/test/.local/bin/claude" ;;
  *"12345"*"ppid="*) echo "23456" ;;
  *"23456"*"comm="*) echo "/bin/zsh" ;;
  *"23456"*"ppid="*) echo "34567" ;;
  *"34567"*"comm="*) echo "/Applications/WebStorm.app/Contents/MacOS/webstorm" ;;
  *"34567"*"ppid="*) echo "1" ;;
esac
MOCK
  chmod +x "$TEST_BIN/ps"

  run env PATH="$TEST_BIN:$PATH" "$PRIORITY_CMD"
  [ "$status" -eq 0 ]
  grep -q -- "-B -t 0 -l 0 -p 12345" "$TASKPOLICY_LOG"
  ! grep -q -- "-b -p 12345" "$TASKPOLICY_LOG"
  grep -q -- "0 -p 12345" "$RENICE_LOG"
  ! grep -q -- "10 -p 12345" "$RENICE_LOG"
}

# ── Stats logging ────────────────────────────────────────────────

@test "cursor-priority logs run to stats file" {
  run env PATH="$TEST_BIN:$PATH" "$PRIORITY_CMD"
  [ "$status" -eq 0 ]
  # Stats file should have an entry for cursor-priority
  [ -f "$HOME/.dotfiles-stats.jsonl" ]
  grep -q "cursor-priority" "$HOME/.dotfiles-stats.jsonl"
}

# ── XDG_CONFIG_HOME support ──────────────────────────────────────

@test "cursor-priority respects XDG_CONFIG_HOME for config file" {
  local xdg_dir="$TEST_DIR/xdg_config"
  mkdir -p "$xdg_dir/dotfiles"
  printf '%s\n' "XDGApp" > "$xdg_dir/dotfiles/priority-apps.txt"

  run env PATH="$TEST_BIN:$PATH" XDG_CONFIG_HOME="$xdg_dir" "$PRIORITY_CMD"
  [ "$status" -eq 0 ]
  grep -q "XDGApp" "$PGREP_LOG"
}
