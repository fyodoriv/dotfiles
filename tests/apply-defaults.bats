#!/usr/bin/env bats
# Tests for lib/apply-defaults.sh — macOS defaults application from JSON

load test_helper

REAL_DEFAULTS_JSON="$BATS_TEST_DIRNAME/../data/macos-defaults.json"

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_DOTFILES="$TEST_DIR/dotfiles"
  mkdir -p "$TEST_DOTFILES/data"
  mkdir -p "$TEST_DOTFILES/lib"

  export DOTFILES_DIR="$TEST_DOTFILES"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME"

  APPLY_DEFAULTS_LIB="$BATS_TEST_DIRNAME/../lib/apply-defaults.sh"
  cp "$APPLY_DEFAULTS_LIB" "$TEST_DOTFILES/lib/apply-defaults.sh"

  # Create a mock defaults command that logs calls
  MOCK_LOG="$TEST_DIR/defaults.log"
  export MOCK_LOG
  mkdir -p "$TEST_DIR/bin"
  cat > "$TEST_DIR/bin/defaults" << 'MOCK'
#!/bin/bash
echo "$@" >> "$MOCK_LOG"
MOCK
  chmod +x "$TEST_DIR/bin/defaults"
  export PATH="$TEST_DIR/bin:$PATH"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "apply-defaults.sh exists and is sourceable" {
  [ -f "$APPLY_DEFAULTS_LIB" ]
  source "$APPLY_DEFAULTS_LIB"
}

@test "apply_defaults function is defined after sourcing" {
  source "$TEST_DOTFILES/lib/apply-defaults.sh"
  declare -f apply_defaults >/dev/null
}

@test "apply_defaults returns 1 when JSON file is missing" {
  rm -f "$TEST_DOTFILES/data/macos-defaults.json"
  source "$TEST_DOTFILES/lib/apply-defaults.sh"
  run apply_defaults "core"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "apply_defaults writes bool defaults correctly" {
  cat > "$TEST_DOTFILES/data/macos-defaults.json" << 'JSON'
[
  {
    "domain": "NSGlobalDomain",
    "key": "TestBool",
    "type": "bool",
    "value": true,
    "section": "Test",
    "script": "core"
  }
]
JSON

  source "$TEST_DOTFILES/lib/apply-defaults.sh"
  apply_defaults "core"

  [ -f "$MOCK_LOG" ]
  grep -q 'write NSGlobalDomain TestBool -bool true' "$MOCK_LOG"
}

@test "apply_defaults writes false bool correctly" {
  cat > "$TEST_DOTFILES/data/macos-defaults.json" << 'JSON'
[
  {
    "domain": "com.apple.dock",
    "key": "TestBoolFalse",
    "type": "bool",
    "value": false,
    "section": "Test",
    "script": "core"
  }
]
JSON

  source "$TEST_DOTFILES/lib/apply-defaults.sh"
  apply_defaults "core"

  [ -f "$MOCK_LOG" ]
  grep -q 'write com.apple.dock TestBoolFalse -bool false' "$MOCK_LOG"
}

@test "apply_defaults writes float defaults correctly" {
  cat > "$TEST_DOTFILES/data/macos-defaults.json" << 'JSON'
[
  {
    "domain": "NSGlobalDomain",
    "key": "TestFloat",
    "type": "float",
    "value": 0.001,
    "section": "Test",
    "script": "core"
  }
]
JSON

  source "$TEST_DOTFILES/lib/apply-defaults.sh"
  apply_defaults "core"

  [ -f "$MOCK_LOG" ]
  grep -q 'write NSGlobalDomain TestFloat -float 0.001' "$MOCK_LOG"
}

@test "apply_defaults writes int defaults correctly" {
  cat > "$TEST_DOTFILES/data/macos-defaults.json" << 'JSON'
[
  {
    "domain": "com.apple.dock",
    "key": "tilesize",
    "type": "int",
    "value": 48,
    "section": "Test",
    "script": "core"
  }
]
JSON

  source "$TEST_DOTFILES/lib/apply-defaults.sh"
  apply_defaults "core"

  [ -f "$MOCK_LOG" ]
  grep -q 'write com.apple.dock tilesize -int 48' "$MOCK_LOG"
}

@test "apply_defaults writes string defaults correctly" {
  cat > "$TEST_DOTFILES/data/macos-defaults.json" << 'JSON'
[
  {
    "domain": "com.apple.screencapture",
    "key": "location",
    "type": "string",
    "value": "~/Desktop",
    "section": "Test",
    "script": "core"
  }
]
JSON

  source "$TEST_DOTFILES/lib/apply-defaults.sh"
  apply_defaults "core"

  [ -f "$MOCK_LOG" ]
  grep -q 'write com.apple.screencapture location -string ~/Desktop' "$MOCK_LOG"
}

@test "apply_defaults filters by script name" {
  cat > "$TEST_DOTFILES/data/macos-defaults.json" << 'JSON'
[
  {
    "domain": "NSGlobalDomain",
    "key": "CoreSetting",
    "type": "bool",
    "value": true,
    "section": "Test",
    "script": "core"
  },
  {
    "domain": "NSGlobalDomain",
    "key": "VisualSetting",
    "type": "bool",
    "value": true,
    "section": "Test",
    "script": "visual"
  }
]
JSON

  source "$TEST_DOTFILES/lib/apply-defaults.sh"
  apply_defaults "core"

  [ -f "$MOCK_LOG" ]
  grep -q 'CoreSetting' "$MOCK_LOG"
  ! grep -q 'VisualSetting' "$MOCK_LOG"
}

@test "apply_defaults handles currenthost flag" {
  cat > "$TEST_DOTFILES/data/macos-defaults.json" << 'JSON'
[
  {
    "domain": "NSGlobalDomain",
    "key": "TestCurrentHost",
    "type": "bool",
    "value": true,
    "section": "Test",
    "script": "core",
    "currenthost": true
  }
]
JSON

  source "$TEST_DOTFILES/lib/apply-defaults.sh"
  apply_defaults "core"

  [ -f "$MOCK_LOG" ]
  grep -q '\-currentHost write NSGlobalDomain TestCurrentHost' "$MOCK_LOG"
}

@test "apply_defaults expands HOME when expand_vars is true" {
  cat > "$TEST_DOTFILES/data/macos-defaults.json" << 'JSON'
[
  {
    "domain": "com.apple.screencapture",
    "key": "location",
    "type": "string",
    "value": "$HOME/Desktop",
    "section": "Test",
    "script": "core",
    "expand_vars": true
  }
]
JSON

  source "$TEST_DOTFILES/lib/apply-defaults.sh"
  apply_defaults "core"

  [ -f "$MOCK_LOG" ]
  grep -q "$HOME/Desktop" "$MOCK_LOG"
  ! grep -q '\$HOME' "$MOCK_LOG"
}

@test "apply_defaults does not expand HOME when expand_vars is false" {
  cat > "$TEST_DOTFILES/data/macos-defaults.json" << 'JSON'
[
  {
    "domain": "com.apple.screencapture",
    "key": "location",
    "type": "string",
    "value": "$HOME/Desktop",
    "section": "Test",
    "script": "core",
    "expand_vars": false
  }
]
JSON

  source "$TEST_DOTFILES/lib/apply-defaults.sh"
  apply_defaults "core"

  [ -f "$MOCK_LOG" ]
  grep -q '\$HOME/Desktop' "$MOCK_LOG"
}

@test "apply_defaults handles empty JSON array" {
  echo '[]' > "$TEST_DOTFILES/data/macos-defaults.json"

  source "$TEST_DOTFILES/lib/apply-defaults.sh"
  apply_defaults "core"

  # No defaults should be written
  [ ! -f "$MOCK_LOG" ] || [ ! -s "$MOCK_LOG" ]
}

@test "apply_defaults handles no matching script filter" {
  cat > "$TEST_DOTFILES/data/macos-defaults.json" << 'JSON'
[
  {
    "domain": "NSGlobalDomain",
    "key": "OnlyCoreDefault",
    "type": "bool",
    "value": true,
    "section": "Test",
    "script": "core"
  }
]
JSON

  source "$TEST_DOTFILES/lib/apply-defaults.sh"
  apply_defaults "nonexistent"

  # No defaults should be written for non-matching filter
  [ ! -f "$MOCK_LOG" ] || [ ! -s "$MOCK_LOG" ]
}

@test "apply_defaults applies representative real rows from each script tier" {
  cp "$REAL_DEFAULTS_JSON" "$TEST_DOTFILES/data/macos-defaults.json"

  source "$TEST_DOTFILES/lib/apply-defaults.sh"
  apply_defaults "core"
  apply_defaults "visual"
  apply_defaults "apps"

  [ -f "$MOCK_LOG" ]
  grep -Fq 'write NSGlobalDomain KeyRepeat -int 1' "$MOCK_LOG"
  grep -Fq 'write NSGlobalDomain AppleShowScrollBars -string WhenScrolling' "$MOCK_LOG"
  grep -Fq 'write com.google.Chrome BackgroundModeEnabled -bool false' "$MOCK_LOG"
}

@test "apply_defaults rejects invalid row shapes with actionable output" {
  cat > "$TEST_DOTFILES/data/macos-defaults.json" << 'JSON'
[
  {
    "domain": "NSGlobalDomain",
    "type": "boolean",
    "value": true,
    "section": "Broken",
    "script": "core"
  }
]
JSON

  source "$TEST_DOTFILES/lib/apply-defaults.sh"
  run apply_defaults "core"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid macOS defaults data"* ]]
  [[ "$output" == *"row 0"* ]]
  [[ "$output" == *"type must be bool, int, float, or string"* ]]
}

@test "apply_defaults processes multiple entries" {
  cat > "$TEST_DOTFILES/data/macos-defaults.json" << 'JSON'
[
  {
    "domain": "NSGlobalDomain",
    "key": "First",
    "type": "bool",
    "value": true,
    "section": "Test",
    "script": "core"
  },
  {
    "domain": "com.apple.dock",
    "key": "Second",
    "type": "int",
    "value": 42,
    "section": "Test",
    "script": "core"
  },
  {
    "domain": "com.apple.finder",
    "key": "Third",
    "type": "string",
    "value": "hello",
    "section": "Test",
    "script": "core"
  }
]
JSON

  source "$TEST_DOTFILES/lib/apply-defaults.sh"
  apply_defaults "core"

  [ -f "$MOCK_LOG" ]
  count=$(wc -l < "$MOCK_LOG")
  [ "$count" -eq 3 ]
}

# ── Integration: real data/macos-defaults.json — extended coverage ──────
# Layered on top of the existing "applies representative real rows" test:
# the assertions below pin per-tier row counts (catching a typo'd `script`
# field that would silently drop or misroute rows) and exercise the
# `currenthost` and `expand_vars` flags against actual rows in the data file.
# Companion validation tests below cover invalid shapes that the existing
# "rejects invalid row shapes" test does not — missing domain, missing
# value, non-boolean `currenthost`, non-boolean `expand_vars`.

@test "real data: core tier emits one defaults call per core row" {
  cp "$REAL_DEFAULTS_JSON" "$TEST_DOTFILES/data/macos-defaults.json"
  source "$TEST_DOTFILES/lib/apply-defaults.sh"
  apply_defaults "core"

  expected=$(jq '[.[] | select(.script == "core")] | length' "$REAL_DEFAULTS_JSON")
  actual=$(wc -l < "$MOCK_LOG" | tr -d ' ')
  [ "$actual" -eq "$expected" ] || { echo "core: expected=$expected actual=$actual"; return 1; }
}

@test "real data: visual tier emits one defaults call per visual row" {
  cp "$REAL_DEFAULTS_JSON" "$TEST_DOTFILES/data/macos-defaults.json"
  source "$TEST_DOTFILES/lib/apply-defaults.sh"
  apply_defaults "visual"

  expected=$(jq '[.[] | select(.script == "visual")] | length' "$REAL_DEFAULTS_JSON")
  actual=$(wc -l < "$MOCK_LOG" | tr -d ' ')
  [ "$actual" -eq "$expected" ] || { echo "visual: expected=$expected actual=$actual"; return 1; }
}

@test "real data: apps tier emits one defaults call per apps row" {
  cp "$REAL_DEFAULTS_JSON" "$TEST_DOTFILES/data/macos-defaults.json"
  source "$TEST_DOTFILES/lib/apply-defaults.sh"
  apply_defaults "apps"

  expected=$(jq '[.[] | select(.script == "apps")] | length' "$REAL_DEFAULTS_JSON")
  actual=$(wc -l < "$MOCK_LOG" | tr -d ' ')
  [ "$actual" -eq "$expected" ] || { echo "apps: expected=$expected actual=$actual"; return 1; }
}

@test "real data: currenthost rows emit -currentHost flag" {
  cp "$REAL_DEFAULTS_JSON" "$TEST_DOTFILES/data/macos-defaults.json"
  source "$TEST_DOTFILES/lib/apply-defaults.sh"
  apply_defaults "core"

  # Every real currenthost:true row must produce a -currentHost defaults call.
  expected=$(jq '[.[] | select(.script == "core" and .currenthost == true)] | length' "$REAL_DEFAULTS_JSON")
  actual=$(grep -c -- '-currentHost write' "$MOCK_LOG" || true)
  [ "$actual" -eq "$expected" ] || { echo "currenthost: expected=$expected actual=$actual"; return 1; }
}

@test "real data: expand_vars rows have \$HOME expanded in defaults call" {
  cp "$REAL_DEFAULTS_JSON" "$TEST_DOTFILES/data/macos-defaults.json"
  source "$TEST_DOTFILES/lib/apply-defaults.sh"
  apply_defaults "core"

  # Pull the first expand_vars row and verify its expanded value lands in the log.
  domain=$(jq -r '[.[] | select(.script == "core" and .expand_vars == true)][0].domain' "$REAL_DEFAULTS_JSON")
  key=$(jq -r '[.[] | select(.script == "core" and .expand_vars == true)][0].key' "$REAL_DEFAULTS_JSON")
  raw_value=$(jq -r '[.[] | select(.script == "core" and .expand_vars == true)][0].value' "$REAL_DEFAULTS_JSON")
  expanded="${raw_value//\$HOME/$HOME}"

  grep -qF "write $domain $key -string $expanded" "$MOCK_LOG"
  ! grep -qF '$HOME' "$MOCK_LOG"
}

# ── Validation: additional malformed-row shapes ─────────────────────────

@test "apply_defaults rejects row missing domain field" {
  cat > "$TEST_DOTFILES/data/macos-defaults.json" << 'JSON'
[
  {
    "key": "MissingDomain",
    "type": "bool",
    "value": true,
    "section": "Test",
    "script": "core"
  }
]
JSON

  source "$TEST_DOTFILES/lib/apply-defaults.sh"
  run apply_defaults "core"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid macOS defaults data"* ]]
  [[ "$output" == *"row 0"* ]]
}

@test "apply_defaults rejects row missing value field" {
  cat > "$TEST_DOTFILES/data/macos-defaults.json" << 'JSON'
[
  {
    "domain": "NSGlobalDomain",
    "key": "MissingValue",
    "type": "bool",
    "section": "Test",
    "script": "core"
  }
]
JSON

  source "$TEST_DOTFILES/lib/apply-defaults.sh"
  run apply_defaults "core"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid macOS defaults data"* ]]
}

@test "apply_defaults rejects row with non-boolean currenthost" {
  cat > "$TEST_DOTFILES/data/macos-defaults.json" << 'JSON'
[
  {
    "domain": "com.apple.controlcenter",
    "key": "BadCurrentHost",
    "type": "int",
    "value": 0,
    "section": "Test",
    "script": "core",
    "currenthost": "yes"
  }
]
JSON

  source "$TEST_DOTFILES/lib/apply-defaults.sh"
  run apply_defaults "core"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid macOS defaults data"* ]]
}

@test "apply_defaults rejects row with non-boolean expand_vars" {
  cat > "$TEST_DOTFILES/data/macos-defaults.json" << 'JSON'
[
  {
    "domain": "com.apple.screencapture",
    "key": "location",
    "type": "string",
    "value": "$HOME/Desktop",
    "section": "Test",
    "script": "core",
    "expand_vars": 1
  }
]
JSON

  source "$TEST_DOTFILES/lib/apply-defaults.sh"
  run apply_defaults "core"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid macOS defaults data"* ]]
}
