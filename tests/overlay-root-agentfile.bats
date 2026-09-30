#!/usr/bin/env bats
# Pins the contract that EXTRA_OVERLAY_ROOT=<path>/Agentfile.yaml is merged
# into the canonical global Agentfile before the post-sync chezmoiscript syncs.
# User story #10, sub-bullet (d/e) under "What dotfiles does with your
# overlay".
#
# Regression coverage for the canonical Agentfile source-of-truth lifecycle.

load test_helper

# bats `run` does not preserve setup's isolated PATH (Makefile prepends dotfiles/bin).
# Use env -i so command -v agentbrew resolves to the stub, not dotfiles/bin/agentbrew.
_run_agentbrew_sync() {
  run env -i \
    PATH="$TEST_BIN:/usr/bin:/bin" \
    HOME="$TEST_HOME" \
    DOTFILES_DIR="$TEST_DOTFILES" \
    CHEZMOI_SOURCE_DIR="$TEST_DOTFILES" \
    CHEZMOI_WORKING_TREE="$TEST_DOTFILES" \
    DOTFILES_CI=true \
    TEST_DIR="$TEST_DIR" \
    "$@" \
    bash "$TEST_DOTFILES/.chezmoiscripts/run_after_agentbrew-sync.sh"
}

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"
  TEST_OVERLAY="$TEST_DIR/dotfiles-acme"
  TEST_BIN="$TEST_DIR/bin"

  mkdir -p "$TEST_HOME" "$TEST_DOTFILES/.chezmoiscripts" "$TEST_DOTFILES/lib" "$TEST_OVERLAY" "$TEST_BIN"

  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"
  export DOTFILES_CI=true
  export CHEZMOI_SOURCE_DIR="$TEST_DOTFILES"
  export CHEZMOI_WORKING_TREE="$TEST_DOTFILES"

  # Stub agentbrew binary that records calls and writes a synthetic merged
  # Agentfile for lifecycle tests that exercise the canonical global path.
  cat > "$TEST_BIN/agentbrew" <<'STUBEOF'
#!/usr/bin/env bash
echo "agentbrew called with: $*" >> "$TEST_DIR/agentbrew-argv.log"
if [ "$1" = "agentfile" ] && [ "$2" = "merge" ]; then
  if [ "$3" = "--help" ]; then
    echo "Usage: agentbrew agentfile merge [options] <agentfiles...>"
    exit 0
  fi
  output=""
  previous=""
  for arg in "$@"; do
    if [ "$previous" = "--output" ]; then
      output="$arg"
      break
    fi
    previous="$arg"
  done
  mkdir -p "$(dirname "$output")"
  cat > "$output" <<MERGED
mcp:
  - context7
  - acme-internal-mcp
MERGED
fi
exit 0
STUBEOF
  chmod +x "$TEST_BIN/agentbrew"
  cat > "$TEST_DOTFILES/lib/agentbrew-locate.sh" <<'LOCEOF'
agentbrew_locate() {
  return 1
}
LOCEOF
  export PATH="$TEST_BIN:/usr/bin:/bin"
  export TEST_DIR
  unset DOTFILES_REPOS_DIR

  cp "$BATS_TEST_DIRNAME/../.chezmoiscripts/run_after_agentbrew-sync.sh" \
     "$TEST_DOTFILES/.chezmoiscripts/run_after_agentbrew-sync.sh" 2>/dev/null || true
  cp "$BATS_TEST_DIRNAME/fixtures/overlay-locate-stub.sh" \
     "$TEST_DOTFILES/lib/overlay-locate.sh"

  cat > "$TEST_OVERLAY/Agentfile.yaml" <<'AFEOF'
name: Acme Engineering
mcp:
  - acme-internal-mcp
AFEOF
  cat > "$TEST_DOTFILES/Agentfile.yaml" <<'AFEOF'
mcp:
  - context7
AFEOF
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "EXTRA_OVERLAY_ROOT/Agentfile.yaml is merged into the canonical global Agentfile before one sync" {
  _run_agentbrew_sync EXTRA_OVERLAY_ROOT="$TEST_OVERLAY"
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/agentbrew-argv.log" ] || { echo "agentbrew stub was not invoked"; return 1; }
  [ -f "$TEST_HOME/.config/agentbrew/Agentfile.yaml" ] || { echo "global Agentfile was not generated"; return 1; }

  calls="$(cat "$TEST_DIR/agentbrew-argv.log")"
  merge_call="$(printf '%s\n' "$calls" | grep '^agentbrew called with: agentfile merge ' || true)"
  sync_calls="$(printf '%s\n' "$calls" | grep -c '^agentbrew called with: sync ' | tr -d ' ')"

  [ -n "$merge_call" ] || { echo "Expected agentfile merge call; got: $calls"; return 1; }
  [[ "$merge_call" == *"--output $TEST_HOME/.config/agentbrew/Agentfile.yaml"* ]] || { echo "Expected global output path; got: $merge_call"; return 1; }
  [[ "$merge_call" == *"$TEST_DOTFILES/Agentfile.yaml"* ]] || { echo "Expected base Agentfile path; got: $merge_call"; return 1; }
  [[ "$merge_call" == *"$TEST_OVERLAY/Agentfile.yaml"* ]] || { echo "Expected overlay Agentfile path; got: $merge_call"; return 1; }
  [ "$sync_calls" -eq 1 ] || { echo "Expected one sync call; got: $calls"; return 1; }
  [[ "$calls" == *"sync --no-recommended --agentfile $TEST_HOME/.config/agentbrew/Agentfile.yaml"* ]] || { echo "Expected explicit sync from generated global Agentfile; got: $calls"; return 1; }
  [[ "$calls" != *"sync --agentfile $TEST_OVERLAY/Agentfile.yaml"* ]] || { echo "Overlay Agentfile should not be synced separately; got: $calls"; return 1; }
}

@test "EXTRA_OVERLAY_ROOT unset: agentbrew sync runs without --agentfile (or with the base one)" {
  _run_agentbrew_sync
  [ "$status" -eq 0 ]
  if [ -f "$TEST_DIR/agentbrew-argv.log" ]; then
    argv="$(cat "$TEST_DIR/agentbrew-argv.log")"
    [[ "$argv" != *"$TEST_OVERLAY/Agentfile.yaml"* ]]
  fi
}

@test "EXTRA_OVERLAY_ROOT with missing Agentfile.yaml: gracefully ignored" {
  rm -f "$TEST_OVERLAY/Agentfile.yaml"
  _run_agentbrew_sync EXTRA_OVERLAY_ROOT="$TEST_OVERLAY"
  [ "$status" -eq 0 ]
}

@test "EXTRA_AGENTFILE backwards-compat: still works when EXTRA_OVERLAY_ROOT unset" {
  _run_agentbrew_sync EXTRA_AGENTFILE="$TEST_OVERLAY/Agentfile.yaml"
  [ "$status" -eq 0 ]
  argv="$(cat "$TEST_DIR/agentbrew-argv.log" 2>/dev/null || echo '')"
  [[ "$argv" == *"$TEST_OVERLAY/Agentfile.yaml"* ]]
}

@test "auto-discovers dotfiles overlay when EXTRA_OVERLAY_ROOT unset" {
  local discover_root="$TEST_HOME/apps/tooling/dotfiles-acme"
  mkdir -p "$discover_root"
  cp "$TEST_OVERLAY/Agentfile.yaml" "$discover_root/Agentfile.yaml"

  _run_agentbrew_sync
  [ "$status" -eq 0 ]
  calls="$(cat "$TEST_DIR/agentbrew-argv.log")"
  [[ "$calls" == *"$discover_root/Agentfile.yaml"* ]] || { echo "Expected auto-discovered overlay in merge; got: $calls"; return 1; }
}

@test "legacy agentbrew without agentfile merge falls back to base sync plus overlay no-prune" {
  cat > "$TEST_BIN/agentbrew" <<'STUBEOF'
#!/usr/bin/env bash
echo "agentbrew called with: $*" >> "$TEST_DIR/agentbrew-argv.log"
if [ "$1" = "agentfile" ] && [ "$2" = "merge" ] && [ "$3" = "--help" ]; then
  echo "Usage: agentbrew [options] [command]"
fi
exit 0
STUBEOF
  chmod +x "$TEST_BIN/agentbrew"

  _run_agentbrew_sync EXTRA_OVERLAY_ROOT="$TEST_OVERLAY"
  [ "$status" -eq 0 ]
  calls="$(cat "$TEST_DIR/agentbrew-argv.log")"

  [[ "$calls" == *"sync --no-recommended --agentfile $TEST_DOTFILES/Agentfile.yaml"* ]] || { echo "Expected explicit base sync; got: $calls"; return 1; }
  [[ "$calls" == *"sync --no-recommended --agentfile $TEST_OVERLAY/Agentfile.yaml --no-prune"* ]] || { echo "Expected explicit overlay no-prune sync; got: $calls"; return 1; }
  [[ "$calls" != *"agentfile merge $TEST_DOTFILES/Agentfile.yaml"* ]] || { echo "Expected no merge attempt with legacy agentbrew; got: $calls"; return 1; }
}

@test "use_cursor=false merges the no-cursor fragment so agentbrew excludes Cursor" {
  mkdir -p "$TEST_DOTFILES/config"
  cp "$BATS_TEST_DIRNAME/../config/agentfile-no-cursor.yaml" "$TEST_DOTFILES/config/"
  grep -q '^excludeAgents:' "$TEST_DOTFILES/config/agentfile-no-cursor.yaml"
  grep -qx '  - cursor' "$TEST_DOTFILES/config/agentfile-no-cursor.yaml"

  _run_agentbrew_sync DOTFILES_USE_CURSOR=false
  [ "$status" -eq 0 ]
  merge_call="$(grep '^agentbrew called with: agentfile merge ' "$TEST_DIR/agentbrew-argv.log" || true)"
  [[ "$merge_call" == *"$TEST_DOTFILES/config/agentfile-no-cursor.yaml"* ]] || { echo "Expected no-cursor fragment in merge; got: $merge_call"; return 1; }
}

@test "use_cursor default leaves the no-cursor fragment out of the merge" {
  mkdir -p "$TEST_DOTFILES/config"
  cp "$BATS_TEST_DIRNAME/../config/agentfile-no-cursor.yaml" "$TEST_DOTFILES/config/"

  _run_agentbrew_sync
  [ "$status" -eq 0 ]
  merge_call="$(grep '^agentbrew called with: agentfile merge ' "$TEST_DIR/agentbrew-argv.log" || true)"
  [[ "$merge_call" != *"agentfile-no-cursor.yaml"* ]] || { echo "Fragment merged without use_cursor=false: $merge_call"; return 1; }
}
