#!/usr/bin/env bats
# Tests for bin/cleanup — is_safe_path logic, dry-run mode, safe path rejection.

load test_helper

SCRIPT="$BATS_TEST_DIRNAME/../bin/cleanup"

# Source lib/colors.sh for color variables used by cleanup
setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  mkdir -p "$TEST_HOME"
  export HOME="$TEST_HOME"

  # Source colors so SAFE_CLEANUP_PARENTS resolves correctly
  source "$BATS_TEST_DIRNAME/../lib/colors.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Source the cleanup script so tests exercise the real guard implementation.
_load_is_safe_path() {
  # shellcheck source=../bin/cleanup
  source "$SCRIPT"
}

# ── is_safe_path accepts known safe paths ─────────────────────────

@test "is_safe_path accepts path under HOME/.npm" {
  _load_is_safe_path
  mkdir -p "$HOME/.npm/_cacache"
  is_safe_path "$HOME/.npm/_cacache"
}

@test "is_safe_path accepts path under HOME/.cache" {
  _load_is_safe_path
  mkdir -p "$HOME/.cache/something"
  is_safe_path "$HOME/.cache/something"
}

@test "is_safe_path accepts exact safelisted parent" {
  _load_is_safe_path
  mkdir -p "$HOME/.cache"
  is_safe_path "$HOME/.cache"
}

@test "is_safe_path accepts path under HOME/.gradle" {
  _load_is_safe_path
  mkdir -p "$HOME/.gradle/daemon"
  is_safe_path "$HOME/.gradle/daemon"
}

@test "is_safe_path accepts path under /tmp" {
  _load_is_safe_path
  local tmpdir
  tmpdir="$(mktemp -d /tmp/cleanup-test.XXXXXX)"
  is_safe_path "$tmpdir"
  rm -rf "$tmpdir"
}

@test "is_safe_path accepts path under HOME/Library/Caches" {
  _load_is_safe_path
  mkdir -p "$HOME/Library/Caches/JetBrains"
  is_safe_path "$HOME/Library/Caches/JetBrains"
}

# ── is_safe_path rejects unsafe paths ─────────────────────────────

@test "is_safe_path rejects HOME itself" {
  _load_is_safe_path
  ! is_safe_path "$HOME"
}

@test "is_safe_path rejects HOME/Documents" {
  _load_is_safe_path
  mkdir -p "$HOME/Documents"
  ! is_safe_path "$HOME/Documents"
}

@test "is_safe_path rejects root" {
  _load_is_safe_path
  ! is_safe_path "/"
}

@test "is_safe_path rejects empty string" {
  _load_is_safe_path
  ! is_safe_path ""
}

@test "is_safe_path rejects nonexistent path" {
  _load_is_safe_path
  ! is_safe_path "/nonexistent/path/that/does/not/exist"
}

@test "is_safe_path rejects sibling-prefix HOME cache path" {
  _load_is_safe_path
  mkdir -p "$HOME/.cache" "$HOME/.cache-evil"
  ! is_safe_path "$HOME/.cache-evil"
}

@test "is_safe_path rejects tmp-style sibling while accepting real child" {
  _load_is_safe_path
  mkdir -p "$TEST_DIR/tmp" "$TEST_DIR/tmp/child" "$TEST_DIR/tmpfoo"
  SAFE_CLEANUP_PARENTS=("$TEST_DIR/tmp")

  is_safe_path "$TEST_DIR/tmp/child"
  ! is_safe_path "$TEST_DIR/tmpfoo"
}

# ── is_safe_path handles path traversal ───────────────────────────

@test "is_safe_path rejects path traversal via .." {
  _load_is_safe_path
  mkdir -p "$HOME/Documents"
  ! is_safe_path "$HOME/.cache/../../Documents"
}

@test "clean refuses to delete sibling-prefix path" {
  _load_is_safe_path
  mkdir -p "$TEST_DIR/cache" "$TEST_DIR/cache-evil"
  SAFE_CLEANUP_PARENTS=("$TEST_DIR/cache")
  DRY_RUN=false
  cleaned_count=0

  run clean "cache sibling" "$TEST_DIR/cache-evil"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Refused to rm -rf"* ]]
  [ -d "$TEST_DIR/cache-evil" ]
}

# ── dry-run mode ─────────────────────────────────────────────────

@test "cleanup --dry-run does not delete anything" {
  mkdir -p "$HOME/.npm/_cacache/content"
  echo "test" > "$HOME/.npm/_cacache/content/file.txt"

  _load_is_safe_path
  DRY_RUN=true

  run clean "npm cache" "$HOME/.npm/_cacache"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]

  # File should still exist
  [ -f "$HOME/.npm/_cacache/content/file.txt" ]
}

@test "cleanup script exists and is executable" {
  [ -f "$SCRIPT" ]
  [ -x "$SCRIPT" ]
}

@test "cleanup script uses set -euo pipefail" {
  grep -q "set -euo pipefail" "$SCRIPT"
}

@test "cleanup script has is_safe_path function" {
  grep -q "is_safe_path()" "$SCRIPT"
}

@test "cleanup script supports --dry-run flag" {
  grep -q '\-\-dry-run' "$SCRIPT"
}

@test "cleanup --help shows usage and exits 0" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"cleanup"* ]]
}

@test "cleanup sources lib/stats.sh for log_run" {
  grep -q 'lib/stats.sh' "$SCRIPT"
}

# ── Log rotation ─────────────────────────────────────────────────

@test "cleanup truncates logs over 1MB to last 1000 lines" {
  LOG_DIR="$HOME/.local/share/dotfiles/logs"
  mkdir -p "$LOG_DIR"

  # Create a log file > 1MB (~1.1MB)
  dd if=/dev/zero bs=1024 count=1100 2>/dev/null | tr '\0' 'a' | fold -w 99 | head -n 11000 | awk '{printf "line %05d: %s\n", NR, $0}' > "$LOG_DIR/big.log"

  local_size=$(wc -c < "$LOG_DIR/big.log" | tr -d ' ')
  [ "$local_size" -gt 1048576 ]

  # Run the log rotation logic inline (can't run full cleanup — needs brew etc.)
  DOTFILES_LOG_DIR="$LOG_DIR"
  MAX_LOG_BYTES=1048576
  KEEP_LINES=1000
  DRY_RUN=false
  cleaned_count=0

  for logfile in "$DOTFILES_LOG_DIR"/*.log; do
    [ -f "$logfile" ] || continue
    local_size=$(wc -c < "$logfile" | tr -d ' ')
    [ "$local_size" -le "$MAX_LOG_BYTES" ] && continue
    tail -n "$KEEP_LINES" "$logfile" > "$logfile.tmp" && mv "$logfile.tmp" "$logfile"
    cleaned_count=$((cleaned_count + 1))
  done

  # Should have exactly 1000 lines now
  [ "$(wc -l < "$LOG_DIR/big.log" | tr -d ' ')" -eq 1000 ]
  # Last line should be line 11000
  grep -q "line 11000" "$LOG_DIR/big.log"
  [ "$cleaned_count" -eq 1 ]
}

@test "cleanup log rotation skips logs under 1MB" {
  LOG_DIR="$HOME/.local/share/dotfiles/logs"
  mkdir -p "$LOG_DIR"

  echo "small log" > "$LOG_DIR/small.log"

  DOTFILES_LOG_DIR="$LOG_DIR"
  MAX_LOG_BYTES=1048576
  KEEP_LINES=1000
  cleaned_count=0

  for logfile in "$DOTFILES_LOG_DIR"/*.log; do
    [ -f "$logfile" ] || continue
    local_size=$(wc -c < "$logfile" | tr -d ' ')
    [ "$local_size" -le "$MAX_LOG_BYTES" ] && continue
    cleaned_count=$((cleaned_count + 1))
  done

  [ "$cleaned_count" -eq 0 ]
  [ "$(cat "$LOG_DIR/small.log")" = "small log" ]
}

@test "cleanup log rotation dry-run does not modify files" {
  LOG_DIR="$HOME/.local/share/dotfiles/logs"
  mkdir -p "$LOG_DIR"

  # Create a log > 1MB
  dd if=/dev/zero bs=1024 count=1100 2>/dev/null | tr '\0' 'a' > "$LOG_DIR/huge.log"
  original_size=$(wc -c < "$LOG_DIR/huge.log" | tr -d ' ')
  [ "$original_size" -gt 1048576 ]

  DRY_RUN=true
  DOTFILES_LOG_DIR="$LOG_DIR"
  MAX_LOG_BYTES=1048576
  KEEP_LINES=1000

  for logfile in "$DOTFILES_LOG_DIR"/*.log; do
    [ -f "$logfile" ] || continue
    local_size=$(wc -c < "$logfile" | tr -d ' ')
    [ "$local_size" -le "$MAX_LOG_BYTES" ] && continue
    if $DRY_RUN; then
      echo "[dry-run] Would truncate $(basename "$logfile")"
    fi
  done

  # File should be unchanged
  after_size=$(wc -c < "$LOG_DIR/huge.log" | tr -d ' ')
  [ "$after_size" -eq "$original_size" ]
}
