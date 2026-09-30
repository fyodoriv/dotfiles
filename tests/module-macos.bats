#!/usr/bin/env bats
# Functional tests for modules/macos/doctor.sh

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"

  mkdir -p "$TEST_HOME"
  mkdir -p "$TEST_DOTFILES"

  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"

  # Doctor framework state
  OVERRIDES_FILE="$TEST_DOTFILES/.overrides"
  touch "$OVERRIDES_FILE"
  FIX_MODE=false
  LIST_MODE=false
  CI_MODE=false
  pass_count=0
  fail_count=0
  fix_count=0
  skip_count=0
  CHECK_DEFAULTS_LOG="$TEST_DIR/check_defaults.log"
  CHECK_LOG="$TEST_DIR/check.log"
  CHECK_FIX_LOG="$TEST_DIR/check_fix.log"
  export CHECK_DEFAULTS_LOG CHECK_LOG CHECK_FIX_LOG

  pass()    { pass_count=$((pass_count + 1)); }
  fail()    { fail_count=$((fail_count + 1)); }
  fixed()   { fix_count=$((fix_count + 1)); }
  skipped() { skip_count=$((skip_count + 1)); }

  is_overridden() { grep -qx "$1" "$OVERRIDES_FILE" 2>/dev/null; }

  # Mock defaults store (file-based)
  MOCK_DEFAULTS="$TEST_DIR/mock_defaults"
  mkdir -p "$MOCK_DEFAULTS"

  set_default() {
    local domain="$1" key="$2" value="$3"
    mkdir -p "$MOCK_DEFAULTS/$domain"
    printf '%s' "$value" > "$MOCK_DEFAULTS/$domain/$key"
  }

  check_defaults() {
    local id="$1" desc="$2" domain="$3" key="$4" expected="$5" type="$6"
    echo "$id" >> "$CHECK_DEFAULTS_LOG"
    if $LIST_MODE; then return; fi
    if $CI_MODE; then skipped "$desc (CI)"; return; fi
    if is_overridden "$id"; then skipped "$desc"; return; fi
    local current
    current=$(cat "$MOCK_DEFAULTS/$domain/$key" 2>/dev/null) || current=""
    if [ "$current" = "$expected" ]; then
      pass "$desc"
    elif $FIX_MODE; then
      mkdir -p "$MOCK_DEFAULTS/$domain"
      printf '%s' "$expected" > "$MOCK_DEFAULTS/$domain/$key"
      fixed "$desc"
    else
      fail "$desc"
    fi
  }

  check() {
    local id="$1" desc="$2" test_cmd="$3" fix_cmd="$4"
    echo "$id" >> "$CHECK_LOG"
    echo "$id|$fix_cmd" >> "$CHECK_FIX_LOG"
    if $LIST_MODE; then return; fi
    if is_overridden "$id"; then skipped "$desc"; return; fi
    if eval "$test_cmd" >/dev/null 2>&1; then
      pass "$desc"
    elif $FIX_MODE && [ -n "$fix_cmd" ]; then
      if eval "$fix_cmd" >/dev/null 2>&1; then fixed "$desc"; else fail "$desc"; fi
    else
      fail "$desc"
    fi
  }

  pmset() {
    if [ "$1" = "-g" ] && [ "$2" = "custom" ]; then
      cat <<'PMSET'
Battery Power:
 displaysleep         15
 sleep                15
 disksleep            15
AC Power:
 displaysleep         15
 sleep                1
 disksleep            10
PMSET
      return 0
    fi
    return 1
  }

  # Mock dockutil to return expected output
  dockutil() {
    if [ "$1" = "--find" ]; then
      echo "$2 was found in persistent-others"
      return 0
    fi
    return 0
  }
  # Mock defaults command for the dynamic dock_no_static_only check
  defaults() {
    if [ "$1" = "read" ]; then
      cat "$MOCK_DEFAULTS/$2/$3" 2>/dev/null || return 1
    elif [ "$1" = "write" ]; then
      mkdir -p "$MOCK_DEFAULTS/$2"
      printf '%s' "$5" > "$MOCK_DEFAULTS/$2/$3"
    elif [ "$1" = "delete" ]; then
      rm -f "$MOCK_DEFAULTS/$2/$3"
    fi
  }
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "macos: defaults pass when all values match" {
  # Set all expected defaults values
  set_default NSGlobalDomain NSAutomaticWindowAnimationsEnabled "0"
  set_default NSGlobalDomain NSScrollAnimationEnabled "0"
  set_default NSGlobalDomain NSWindowResizeTime "0.001"
  set_default NSGlobalDomain KeyRepeat "1"
  set_default NSGlobalDomain InitialKeyRepeat "15"
  set_default NSGlobalDomain ApplePressAndHoldEnabled "0"
  set_default NSGlobalDomain NSAutomaticSpellingCorrectionEnabled "0"
  set_default NSGlobalDomain NSAutomaticCapitalizationEnabled "0"
  set_default NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled "0"
  set_default NSGlobalDomain NSAutomaticDashSubstitutionEnabled "0"
  set_default NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled "0"
  set_default NSGlobalDomain NSAutomaticTextCompletionEnabled "0"
  set_default com.apple.dock autohide "1"
  set_default com.apple.dock autohide-delay "0"
  set_default com.apple.dock launchanim "0"
  set_default com.apple.dock minimize-to-application "1"
  set_default com.apple.dock mru-spaces "0"
  set_default com.apple.dock show-recents "0"
  set_default com.apple.dock expose-animation-duration "0.1"
  set_default NSGlobalDomain NSAppSleepDisabled "1"
  set_default com.apple.finder AppleShowAllFiles "1"
  set_default com.apple.finder ShowPathbar "1"
  set_default com.apple.finder ShowStatusBar "1"
  set_default com.apple.finder _FXSortFoldersFirst "1"
  set_default NSGlobalDomain AppleShowAllExtensions "1"
  set_default com.apple.finder DisableAllAnimations "1"
  set_default com.apple.finder FXEnableExtensionChangeWarning "0"
  set_default com.apple.finder FXDefaultSearchScope "SCcf"
  set_default com.apple.finder FXPreferredViewStyle "clmv"
  set_default com.apple.finder CreateDesktop "0"
  set_default com.apple.desktopservices DSDontWriteNetworkStores "1"
  set_default com.apple.desktopservices DSDontWriteUSBStores "1"
  set_default com.apple.CrashReporter DialogType "none"
  set_default NSGlobalDomain NSDocumentSaveNewDocumentsToCloud "0"
  set_default NSGlobalDomain NSNavPanelExpandedStateForSaveMode "1"
  set_default com.apple.LaunchServices LSQuarantine "0"
  set_default com.apple.screencapture type "png"
  set_default com.apple.screencapture disable-shadow "1"
  set_default NSGlobalDomain com.apple.mouse.scaling "3"
  set_default NSGlobalDomain com.apple.trackpad.scaling "3"
  set_default com.apple.AppleMultitouchTrackpad Clicking "1"
  set_default com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag "1"
  set_default com.apple.WindowManager EnableTilingByEdgeDrag "1"
  set_default com.apple.screensaver askForPassword "1"
  set_default com.apple.screensaver askForPasswordDelay "0"
  set_default com.apple.screensaver idleTime "900"
  # dock_no_static_only is a dynamic check that reads defaults directly
  set_default com.apple.dock static-only "0"
  source "$BATS_TEST_DIRNAME/../modules/macos/doctor.sh"
  [ "$pass_count" -ge 40 ]
  [ "$fail_count" -eq 0 ]
}

@test "macos: defaults fail when values differ" {
  # Set wrong values for a few key settings
  set_default NSGlobalDomain KeyRepeat "6"
  set_default com.apple.dock autohide "0"
  set_default com.apple.finder AppleShowAllFiles "0"
  # Leave all others unset — they'll also fail
  source "$BATS_TEST_DIRNAME/../modules/macos/doctor.sh"
  [ "$fail_count" -ge 30 ]
}

@test "macos: fix mode writes correct values" {
  FIX_MODE=true
  source "$BATS_TEST_DIRNAME/../modules/macos/doctor.sh"
  [ "$fix_count" -ge 30 ]
  # Verify some values were written
  [ "$(cat "$MOCK_DEFAULTS/NSGlobalDomain/KeyRepeat")" = "1" ]
  [ "$(cat "$MOCK_DEFAULTS/com.apple.dock/autohide")" = "1" ]
  [ "$(cat "$MOCK_DEFAULTS/com.apple.finder/AppleShowAllFiles")" = "1" ]
}

@test "macos: CI mode skips all defaults checks" {
  CI_MODE=true
  source "$BATS_TEST_DIRNAME/../modules/macos/doctor.sh"
  # All check_defaults calls are skipped in CI mode
  [ "$skip_count" -ge 40 ]
  [ "$fail_count" -eq 0 ]
  # Dynamic check() calls (dock_no_static_only, dockutil) still run — that's expected
}

@test "macos: overrides skip individual checks" {
  echo "macos.key_repeat" >> "$OVERRIDES_FILE"
  echo "macos.dock_autohide" >> "$OVERRIDES_FILE"
  echo "macos.finder_hidden_files" >> "$OVERRIDES_FILE"
  source "$BATS_TEST_DIRNAME/../modules/macos/doctor.sh"
  [ "$skip_count" -ge 3 ]
}

@test "macos: idle lock defaults are checked" {
  source "$BATS_TEST_DIRNAME/../modules/macos/doctor.sh"

  grep -Fxq "macos.password_after_sleep" "$CHECK_DEFAULTS_LOG"
  grep -Fxq "macos.password_after_sleep_delay" "$CHECK_DEFAULTS_LOG"
  grep -Fxq "macos.screensaver_idle_time" "$CHECK_DEFAULTS_LOG"
}

@test "macos: pmset lock timing checks are registered" {
  source "$BATS_TEST_DIRNAME/../modules/macos/doctor.sh"

  grep -Fxq "macos.pmset_display_sleep_15" "$CHECK_LOG"
  grep -Fxq "macos.pmset_battery_sleep_15" "$CHECK_LOG"
  grep -Fxq "macos.pmset_battery_disk_sleep_15" "$CHECK_LOG"
  grep -Fxq "macos.pmset_ac_sleep_1" "$CHECK_LOG"
  grep -Fxq "macos.pmset_ac_disk_sleep_10" "$CHECK_LOG"
}

@test "macos: pmset fixes use non-interactive sudo" {
  source "$BATS_TEST_DIRNAME/../modules/macos/doctor.sh"

  grep -Fxq "macos.pmset_display_sleep_15|sudo -n pmset -a displaysleep 15" "$CHECK_FIX_LOG"
  grep -Fxq "macos.pmset_battery_sleep_15|sudo -n pmset -b sleep 15" "$CHECK_FIX_LOG"
  grep -Fxq "macos.pmset_battery_disk_sleep_15|sudo -n pmset -b disksleep 15" "$CHECK_FIX_LOG"
  grep -Fxq "macos.pmset_ac_sleep_1|sudo -n pmset -c sleep 1" "$CHECK_FIX_LOG"
  grep -Fxq "macos.pmset_ac_disk_sleep_10|sudo -n pmset -c disksleep 10" "$CHECK_FIX_LOG"
}

@test "macos: keyboard settings all checked" {
  # Set only keyboard-related defaults
  set_default NSGlobalDomain KeyRepeat "1"
  set_default NSGlobalDomain InitialKeyRepeat "15"
  set_default NSGlobalDomain ApplePressAndHoldEnabled "0"
  set_default NSGlobalDomain NSAutomaticSpellingCorrectionEnabled "0"
  set_default NSGlobalDomain NSAutomaticCapitalizationEnabled "0"
  set_default NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled "0"
  set_default NSGlobalDomain NSAutomaticDashSubstitutionEnabled "0"
  set_default NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled "0"
  set_default NSGlobalDomain NSAutomaticTextCompletionEnabled "0"
  source "$BATS_TEST_DIRNAME/../modules/macos/doctor.sh"
  # At least the 9 keyboard checks should pass
  [ "$pass_count" -ge 9 ]
}
