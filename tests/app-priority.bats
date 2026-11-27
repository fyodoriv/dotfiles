#!/usr/bin/env bats
# Native App Priority dispatcher, configuration environment and timing.

load test_helper
export DOTFILES_STATS_LOG=1

PRIORITY_CMD="$BATS_TEST_DIRNAME/../bin/app-priority"
REAL_DOTFILES="$BATS_TEST_DIRNAME/.."

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_BIN="$TEST_DIR/mockbin"
  export HOME="$TEST_DIR/home"
  export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$TEST_DIR/data"
  export PRIORITY_ARGS="$TEST_DIR/native-args" PRIORITY_CONFIG="$TEST_DIR/native-config"
  native_dir="$XDG_DATA_HOME/dotfiles/native/app-priority"
  mkdir -p "$HOME" "$TEST_BIN" "$native_dir"
  cat > "$TEST_DIR/native-fixture" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" > "$PRIORITY_ARGS"
config="$XDG_CONFIG_HOME/dotfiles/priority-apps.txt"
if [ -f "$config" ]; then cat "$config" > "$PRIORITY_CONFIG"; fi
MOCK
  chmod +x "$TEST_DIR/native-fixture"
  digest="$(shasum -a 256 "$TEST_DIR/native-fixture")"
  artifact="app-priority-${digest%% *}"
  mv "$TEST_DIR/native-fixture" "$native_dir/$artifact"
  ln -s "$artifact" "$native_dir/current"
}

teardown() { rm -rf "$TEST_DIR"; }

# ── Script basics ────────────────────────────────────────────────

@test "app-priority script exists and is executable" {
  [ -f "$PRIORITY_CMD" ]
  [ -x "$PRIORITY_CMD" ]
}

@test "app-priority has correct shebang" {
  head -1 "$PRIORITY_CMD" | grep -q '#!/bin/bash'
}

# ── --help output ────────────────────────────────────────────────

@test "app-priority --help prints usage" {
  run "$PRIORITY_CMD" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"priority"* ]] || [[ "$output" == *"scheduling"* ]]
}

# ── Stats logging ────────────────────────────────────────────────

@test "app-priority records elapsed milliseconds from the clock" {
  cat > "$TEST_BIN/perl" <<'MOCK'
#!/bin/bash
if [ ! -e "$CLOCK_MARKER" ]; then
  touch "$CLOCK_MARKER"
  echo 100000
else
  echo 100125
fi
MOCK
  chmod +x "$TEST_BIN/perl"
  export CLOCK_MARKER="$TEST_DIR/clock-started"
  run env PATH="$TEST_BIN:$PATH" "$PRIORITY_CMD"
  [ "$status" -eq 0 ]
  jq -e '.duration_ms == 125 and .timing_source == "monotonic-ms"' "$HOME/.dotfiles-stats.jsonl"
}

@test "app-priority records a run without claiming a valid clock sample" {
  printf '#!/bin/bash\nexit 1\n' > "$TEST_BIN/perl"
  chmod +x "$TEST_BIN/perl"
  run env PATH="$TEST_BIN:$PATH" "$PRIORITY_CMD"
  [ "$status" -eq 0 ]
  jq -e '.task == "app-priority" and (has("timing_source") | not)' "$HOME/.dotfiles-stats.jsonl"
}

@test "migration window excludes legacy and failed clock samples" {
  local now query
  now=$(jq -nr 'now - 60 | todate')
  printf '%s\n' \
    "{\"task\":\"app-priority\",\"timestamp\":\"$now\",\"duration_ms\":1000}" \
    "{\"task\":\"app-priority\",\"timestamp\":\"$now\",\"duration_ms\":125,\"timing_source\":\"monotonic-ms\"}" \
    "{\"task\":\"other\",\"timestamp\":\"$now\",\"duration_ms\":1,\"timing_source\":\"monotonic-ms\"}" > "$HOME/.dotfiles-stats.jsonl"
  query=$(grep '^jq -c -s --argjson to 0 ' "$REAL_DOTFILES/docs/plans/rust-migration.md")
  [ -n "$query" ]
  run bash -c "$query"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.mean')" = 125 ]
  [ "$(printf '%s' "$output" | jq -r '.runs')" = 1 ]
}

@test "app-priority logs run to stats file" {
  run env PATH="$TEST_BIN:$PATH" "$PRIORITY_CMD"
  [ "$status" -eq 0 ]
  # Stats file should have an entry for app-priority
  [ -f "$HOME/.dotfiles-stats.jsonl" ]
  grep -q "app-priority" "$HOME/.dotfiles-stats.jsonl"
}

@test "app-priority passes the config environment to the verified executable" {
  xdg_dir="$TEST_DIR/xdg-config"
  mkdir -p "$xdg_dir/dotfiles"
  printf '%s\n' "XDGApp" > "$xdg_dir/dotfiles/priority-apps.txt"
  run env XDG_CONFIG_HOME="$xdg_dir" "$PRIORITY_CMD"
  [ "$status" -eq 0 ]
  [ "$(cat "$PRIORITY_ARGS")" = --apply ]
  [ "$(cat "$PRIORITY_CONFIG")" = XDGApp ]
}
