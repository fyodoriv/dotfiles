#!/usr/bin/env bats
# Tests for macos.sh, macos-visual.sh, macos-apps.sh — macOS defaults scripts

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$BATS_TEST_DIRNAME/.."
  export HOME="$TEST_HOME"
  mkdir -p "$HOME"

  # Create mock bin directory
  MOCK_BIN="$TEST_DIR/bin"
  mkdir -p "$MOCK_BIN"

  # Mock defaults command — logs calls
  DEFAULTS_LOG="$TEST_DIR/defaults.log"
  export DEFAULTS_LOG
  cat > "$MOCK_BIN/defaults" << 'MOCK'
#!/bin/bash
echo "$@" >> "$DEFAULTS_LOG"
MOCK
  chmod +x "$MOCK_BIN/defaults"

  # Mock sudo — logs calls without actual privilege
  SUDO_LOG="$TEST_DIR/sudo.log"
  export SUDO_LOG
  cat > "$MOCK_BIN/sudo" << 'MOCK'
#!/bin/bash
echo "$@" >> "$SUDO_LOG"
MOCK
  chmod +x "$MOCK_BIN/sudo"

  cat > "$MOCK_BIN/id" << 'MOCK'
#!/bin/bash
if [ "$1" = "-Gn" ]; then
  echo "staff admin"
else
  /usr/bin/id "$@"
fi
MOCK
  chmod +x "$MOCK_BIN/id"

  # Mock killall — noop
  cat > "$MOCK_BIN/killall" << 'MOCK'
#!/bin/bash
true
MOCK
  chmod +x "$MOCK_BIN/killall"

  # Mock fd — noop
  cat > "$MOCK_BIN/fd" << 'MOCK'
#!/bin/bash
true
MOCK
  chmod +x "$MOCK_BIN/fd"

  # Mock touch — logs
  TOUCH_LOG="$TEST_DIR/touch.log"
  export TOUCH_LOG
  cat > "$MOCK_BIN/touch" << 'MOCK'
#!/bin/bash
echo "$@" >> "$TOUCH_LOG"
/usr/bin/touch "$@"
MOCK
  chmod +x "$MOCK_BIN/touch"

  export PATH="$MOCK_BIN:$PATH"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "macos.sh exists and is executable" {
  [ -x "$TEST_DOTFILES/macos.sh" ]
}

@test "macos-visual.sh exists" {
  [ -f "$TEST_DOTFILES/macos-visual.sh" ]
}

@test "macos-apps.sh exists" {
  [ -f "$TEST_DOTFILES/macos-apps.sh" ]
}

@test "macos.sh uses strict mode" {
  head -20 "$TEST_DOTFILES/macos.sh" | grep -q 'set -euo pipefail'
}

@test "macos.sh sources colors.sh" {
  grep -q 'source.*lib/colors.sh' "$TEST_DOTFILES/macos.sh"
}

@test "macos.sh sources apply-defaults.sh" {
  grep -q 'source.*lib/apply-defaults.sh' "$TEST_DOTFILES/macos.sh"
}

@test "macos.sh calls apply_defaults with core filter" {
  grep -q 'apply_defaults "core"' "$TEST_DOTFILES/macos.sh"
}

@test "macos-visual.sh calls apply_defaults with visual filter" {
  grep -q 'apply_defaults "visual"' "$TEST_DOTFILES/macos-visual.sh"
}

@test "macos-apps.sh calls apply_defaults with apps filter" {
  grep -q 'apply_defaults "apps"' "$TEST_DOTFILES/macos-apps.sh"
}

@test "macos.sh creates snapshot guard when run directly" {
  grep -q 'DOTFILES_SNAPSHOT_DONE' "$TEST_DOTFILES/macos.sh"
}

@test "macos.sh sets DOTFILES_SNAPSHOT_DONE after snapshot" {
  grep -q 'export DOTFILES_SNAPSHOT_DONE=1' "$TEST_DOTFILES/macos.sh"
}

@test "macos.sh skips snapshot when DOTFILES_SNAPSHOT_DONE is set" {
  # The script checks if DOTFILES_SNAPSHOT_DONE is empty
  grep -q '{ -z "\${DOTFILES_SNAPSHOT_DONE:-}"' "$TEST_DOTFILES/macos.sh" || \
  grep -q 'DOTFILES_SNAPSHOT_DONE:-' "$TEST_DOTFILES/macos.sh"
}

@test "macos.sh excludes expected directories from Spotlight" {
  # Check for known Spotlight exclusion directories
  grep -q '\.nvm' "$TEST_DOTFILES/macos.sh"
  grep -q '\.gradle' "$TEST_DOTFILES/macos.sh"
  grep -q '\.cache' "$TEST_DOTFILES/macos.sh"
  grep -q '\.npm' "$TEST_DOTFILES/macos.sh"
  grep -q 'node_modules' "$TEST_DOTFILES/macos.sh"
}

@test "macos.sh continues when a Spotlight marker cannot be written" {
  mkdir -p "$HOME/Library/Application Support/Google/Chrome"
  cat > "$MOCK_BIN/touch" << 'MOCK'
#!/bin/bash
echo "$@" >> "$TOUCH_LOG"
case "$*" in *Google/Chrome*) echo "touch: $*: Operation not permitted" >&2; exit 1 ;; esac
/usr/bin/touch "$@"
MOCK
  chmod +x "$MOCK_BIN/touch"

  DOTFILES_SNAPSHOT_DONE=1 run "$TEST_DOTFILES/macos.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Spotlight"*"Google/Chrome"* ]]
  [[ "$output" == *"Full Disk Access"* ]]
  [ "$(printf '%s\n' "$output" | grep -c 'Spotlight: cannot write marker')" -eq 1 ]
}

@test "macos.sh skips Spotlight markers that already exist" {
  mkdir -p "$HOME/.config"
  : > "$HOME/.config/.metadata_never_index"

  DOTFILES_SNAPSHOT_DONE=1 run "$TEST_DOTFILES/macos.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$TOUCH_LOG" ] || ! grep -qF "$HOME/.config/.metadata_never_index" "$TOUCH_LOG"
}

@test "macos.sh uses fd for node_modules Spotlight exclusion" {
  grep -q 'fd.*node_modules.*metadata_never_index' "$TEST_DOTFILES/macos.sh"
}

@test "macos.sh limits Spotlight results to files, contacts, and calendar" {
  DOTFILES_SNAPSHOT_DONE=1 run "$TEST_DOTFILES/macos.sh"
  [ "$status" -eq 0 ]

  spotlight_call=$(grep 'write com.apple.Spotlight orderedItems -array' "$DEFAULTS_LOG")
  for category in DIRECTORIES DOCUMENTS IMAGES PDF PRESENTATIONS SPREADSHEETS SOURCE MENU_OTHER CONTACT EVENT_TODO; do
    [[ "$spotlight_call" == *'"enabled" = 1;"name" = "'"$category"'";'* ]] || {
      echo "missing enabled Spotlight category: $category"
      return 1
    }
  done
  for category in APPLICATIONS SYSTEM_PREFS MENU_SPOTLIGHT_SUGGESTIONS MENU_CONVERSION MENU_EXPRESSION MENU_DEFINITION MESSAGES BOOKMARKS MUSIC MOVIES FONTS MENU_WEBSEARCH; do
    [[ "$spotlight_call" == *'"enabled" = 0;"name" = "'"$category"'";'* ]] || {
      echo "missing disabled Spotlight category: $category"
      return 1
    }
  done
}

@test "macos.sh restores normal idle timers outside agent work" {
  DOTFILES_SNAPSHOT_DONE=1 run "$TEST_DOTFILES/macos.sh"
  [ "$status" -eq 0 ]

  grep -Fxq -- "pmset -a displaysleep 15" "$SUDO_LOG"
  grep -Fxq -- "pmset -c sleep 1" "$SUDO_LOG"
  grep -Fxq -- "pmset -c disksleep 10" "$SUDO_LOG"
  grep -Fxq -- "pmset -b sleep 15" "$SUDO_LOG"
  grep -Fxq -- "pmset -b disksleep 15" "$SUDO_LOG"
  ! grep -Fxq -- "pmset -c sleep 0" "$SUDO_LOG"
  ! grep -Fxq -- "pmset -c disksleep 0" "$SUDO_LOG"
  ! grep -Fxq -- "pmset -b displaysleep 5" "$SUDO_LOG"
  ! grep -Fxq -- "pmset -b sleep 10" "$SUDO_LOG"
  ! grep -Fxq -- "pmset -b disksleep 10" "$SUDO_LOG"
}

@test "macos.sh applies sudo pmset commands with error suppression" {
  # All pmset calls should have 2>/dev/null || true
  while IFS= read -r line; do
    [[ "$line" == *"2>/dev/null || true"* ]] || {
      echo "pmset command without error suppression: $line"
      return 1
    }
  done < <(grep 'sudo pmset' "$TEST_DOTFILES/macos.sh")
}

@test "macos.sh kills Dock, Finder, and SystemUIServer at end" {
  grep -q 'killall Dock' "$TEST_DOTFILES/macos.sh"
  grep -q 'killall Finder' "$TEST_DOTFILES/macos.sh"
  grep -q 'killall SystemUIServer' "$TEST_DOTFILES/macos.sh"
}

@test "macos.sh respects DOTFILES_REPOS_DIR override" {
  grep -q 'DOTFILES_REPOS_DIR' "$TEST_DOTFILES/macos.sh"
}

@test "data/macos-defaults.json exists and is valid JSON" {
  [ -f "$TEST_DOTFILES/data/macos-defaults.json" ]
  jq empty "$TEST_DOTFILES/data/macos-defaults.json"
}

@test "data/macos-defaults.json contains core, visual, and apps scripts" {
  scripts=$(jq -r '[.[].script] | unique | sort | .[]' "$TEST_DOTFILES/data/macos-defaults.json")
  echo "$scripts" | grep -q 'core'
  echo "$scripts" | grep -q 'visual'
  echo "$scripts" | grep -q 'apps'
}

@test "data/macos-defaults.json entries have required fields" {
  # Every entry must have domain, key, type, value, section, script
  missing=$(jq '[.[] | select(.domain == null or .key == null or .type == null or .section == null or .script == null)] | length' "$TEST_DOTFILES/data/macos-defaults.json")
  [ "$missing" -eq 0 ]
}

@test "data/macos-defaults.json type values are valid" {
  # types must be one of: bool, int, float, string
  invalid=$(jq '[.[] | select(.type != "bool" and .type != "int" and .type != "float" and .type != "string")] | length' "$TEST_DOTFILES/data/macos-defaults.json")
  [ "$invalid" -eq 0 ]
}

@test "macos.sh killall commands have error suppression" {
  while IFS= read -r line; do
    [[ "$line" == *"|| true"* ]] || {
      echo "killall command without error suppression: $line"
      return 1
    }
  done < <(grep '^killall' "$TEST_DOTFILES/macos.sh")
}

@test "macos-visual.sh uses strict mode" {
  head -20 "$TEST_DOTFILES/macos-visual.sh" | grep -q 'set -euo pipefail'
}

@test "macos-apps.sh uses strict mode" {
  head -20 "$TEST_DOTFILES/macos-apps.sh" | grep -q 'set -euo pipefail'
}

@test "macos-apps.sh clears managed app Rosetta overrides on Apple Silicon" {
  grep -q 'dotfiles_clear_managed_app_rosetta_overrides' "$TEST_DOTFILES/macos-apps.sh"
  ! grep -q 'LSArchitecturePriority -array x86_64' "$TEST_DOTFILES/macos-apps.sh"
}

@test "macos-apps.sh keeps WebStorm responsive when backgrounded" {
  grep -Fq 'set_app_responsiveness_defaults "WebStorm" "com.jetbrains.WebStorm"' \
    "$TEST_DOTFILES/macos-apps.sh"
}

@test "macos-apps.sh removes WebStorm login item and leaves Cursor to LaunchAgent" {
  ! grep -q 'WebStorm:/Applications/WebStorm.app' "$TEST_DOTFILES/macos-apps.sh"
  grep -q '_removed_login_apps=(' "$TEST_DOTFILES/macos-apps.sh"
  grep -q '"WebStorm"' "$TEST_DOTFILES/macos-apps.sh"
  [ -f "$TEST_DOTFILES/launchagents/com.dotfiles.cursor-at-login.plist.tmpl" ]
  grep -q 'bin/cursor-at-login</string>' "$TEST_DOTFILES/launchagents/com.dotfiles.cursor-at-login.plist.tmpl"
  grep -q 'CURSOR_LOGIN_WAIT_FOR_MEMORY' "$TEST_DOTFILES/launchagents/com.dotfiles.cursor-at-login.plist.tmpl"
  grep -q 'launchagent-path' "$TEST_DOTFILES/launchagents/com.dotfiles.cursor-at-login.plist.tmpl"
  grep -q 'memory fix' "$TEST_DOTFILES/bin/cursor-at-login"
  grep -q 'exec "$open_bin" -g -a Cursor' "$TEST_DOTFILES/bin/cursor-at-login"
}
