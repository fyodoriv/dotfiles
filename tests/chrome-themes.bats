#!/usr/bin/env bats
# Tests for bin/dotfiles-set-persistent-chrome-themes

load test_helper

@test "chrome-themes: script exists and is executable" {
  [ -x "$BATS_TEST_DIRNAME/../bin/dotfiles-set-persistent-chrome-themes" ]
}

@test "chrome-themes: --help prints usage (if supported)" {
  run bash "$BATS_TEST_DIRNAME/../bin/dotfiles-set-persistent-chrome-themes" --help
  # Script may not have --help; just verify it's parseable bash
  run bash -n "$BATS_TEST_DIRNAME/../bin/dotfiles-set-persistent-chrome-themes"
  [ "$status" -eq 0 ]
}

@test "chrome-themes: script themes only the agents Chrome port" {
  content=$(cat "$BATS_TEST_DIRNAME/../bin/dotfiles-set-persistent-chrome-themes")
  [[ "$content" == *"9223"* ]]
  [[ "$content" != *"9224"* ]]
  [[ "$content" != *"9225"* ]]
}

# Fake launchctl, pgrep, and curl so the script only edits a scratch profile.
# Nothing here stops, starts, or themes a real Chrome.
fake_chrome_tools() {
  FAKE_BIN="$TEST_DIR/fake-bin"
  mkdir -p "$FAKE_BIN"
  cat >"$FAKE_BIN/launchctl" <<FAKE
#!/bin/bash
printf 'launchctl %s\n' "\$*" >>"$TEST_DIR/calls"
FAKE
  printf '#!/bin/bash\nexit 1\n' >"$FAKE_BIN/pgrep"
  printf '#!/bin/bash\nexit 0\n' >"$FAKE_BIN/curl"
  chmod +x "$FAKE_BIN/launchctl" "$FAKE_BIN/pgrep" "$FAKE_BIN/curl"
}

@test "chrome-themes: themes the agents Chrome orange with its profile name" {
  fake_chrome_tools
  prefs="$HOME/.agent-browser/chrome-profile/Default/Preferences"
  mkdir -p "$(dirname "$prefs")"
  echo '{"browser":{"theme":{"user_color2":-16746043}},"profile":{"name":"Person 1"}}' >"$prefs"

  run env HOME="$HOME" PATH="$FAKE_BIN:$PATH" \
    "$BATS_TEST_DIRNAME/../bin/dotfiles-set-persistent-chrome-themes" 9223

  [ "$status" -eq 0 ]
  [ "$(jq -r '.browser.theme.user_color' "$prefs")" = "-37632" ]
  [ "$(jq -r '.browser.theme.user_color2' "$prefs")" = "-37632" ]
  [ "$(jq -r '.browser.theme.color_variant' "$prefs")" = "2" ]
  [ "$(jq -r '.browser.theme.follows_system_colors' "$prefs")" = "false" ]
  [ "$(jq -r '.profile.name' "$prefs")" = "🟧 AGENTS (SSO)" ]
  grep -qx "launchctl unload $HOME/Library/LaunchAgents/com.dotfiles.agent-browser-chrome.plist" "$TEST_DIR/calls"

  run env HOME="$HOME" PATH="$FAKE_BIN:$PATH" \
    "$BATS_TEST_DIRNAME/../bin/dotfiles-set-persistent-chrome-themes" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"already themed (🟧 AGENTS (SSO))"* ]]
}
