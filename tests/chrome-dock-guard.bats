#!/usr/bin/env bats
# Tests for the Chrome Dock guard: a hidden agent Chrome must never keep the
# user's Dock click.

load test_helper

GUARD_CMD="$BATS_TEST_DIRNAME/../bin/dotfiles-chrome-dock-guard"
PLIST_TMPL="$BATS_TEST_DIRNAME/../launchagents/com.dotfiles.chrome-dock-guard.plist.tmpl"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

setup() {
  TEST_DIR="$(mktemp -d)"
  export ORIG_HOME="$HOME"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME"
  export DOTFILES_CHROME_DOCK_GUARD_BIN="$TEST_DIR/chrome-dock-guard"
}

teardown() {
  export HOME="$ORIG_HOME"
  rm -rf "$TEST_DIR"
}

need_swiftc() {
  command -v swiftc >/dev/null 2>&1 || skip "swiftc not installed"
}

@test "LaunchAgent template runs the guard wrapper and restarts it on crash only" {
  [ -f "$PLIST_TMPL" ]
  grep -q '<string>com.dotfiles.chrome-dock-guard</string>' "$PLIST_TMPL"
  grep -q 'bin/dotfiles-chrome-dock-guard</string>' "$PLIST_TMPL"
  grep -q '<key>SuccessfulExit</key>' "$PLIST_TMPL"
  grep -q '<key>RunAtLoad</key>' "$PLIST_TMPL"
}

@test "wrapper skips cleanly with exit 0 when swiftc is missing" {
  DOTFILES_SWIFTC="$TEST_DIR/no-swiftc" run bash "$GUARD_CMD" --classify "$CHROME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skip"*"swiftc"* ]]
}

@test "classify: launchd agent Chromes are automation" {
  need_swiftc
  run bash "$GUARD_CMD" --classify "$CHROME" --remote-debugging-port=9223 --headless=new
  [ "$status" -eq 0 ]
  [ "$output" = "automation" ]
  run bash "$GUARD_CMD" --classify "$CHROME" --remote-debugging-pipe --user-data-dir=/tmp/x
  [ "$output" = "automation" ]
}

@test "classify: the user's own Chrome is user" {
  need_swiftc
  run bash "$GUARD_CMD" --classify "$CHROME"
  [ "$status" -eq 0 ]
  [ "$output" = "user" ]
  run bash "$GUARD_CMD" --classify "$CHROME" --profile-directory=Default
  [ "$output" = "user" ]
}

@test "wrapper caches the compiled binary and rebuilds when the source changes" {
  need_swiftc
  bash "$GUARD_CMD" --classify "$CHROME" >/dev/null
  [ -x "$DOTFILES_CHROME_DOCK_GUARD_BIN" ]
  first="$(stat -f %m "$DOTFILES_CHROME_DOCK_GUARD_BIN")"
  bash "$GUARD_CMD" --classify "$CHROME" >/dev/null
  [ "$(stat -f %m "$DOTFILES_CHROME_DOCK_GUARD_BIN")" = "$first" ]
  [ -f "$DOTFILES_CHROME_DOCK_GUARD_BIN.sha" ]
  echo stale > "$DOTFILES_CHROME_DOCK_GUARD_BIN.sha"
  bash "$GUARD_CMD" --classify "$CHROME" >/dev/null
  [ "$(cat "$DOTFILES_CHROME_DOCK_GUARD_BIN.sha")" != "stale" ]
}

@test "decide: a headless agent Chrome with no on-screen window hands focus off" {
  need_swiftc
  run bash "$GUARD_CMD" --decide 0 "$CHROME" --remote-debugging-port=9223 --headless=new
  [ "$status" -eq 0 ]
  [ "$output" = "hand-off" ]
}

@test "decide: a headed agent Chrome with a visible window keeps focus (#197)" {
  need_swiftc
  run bash "$GUARD_CMD" --decide 1 "$CHROME" --remote-debugging-port=9224
  [ "$status" -eq 0 ]
  [ "$output" = "keep" ]
}

@test "decide: the user's own Chrome always keeps focus" {
  need_swiftc
  run bash "$GUARD_CMD" --decide 0 "$CHROME"
  [ "$output" = "keep" ]
}
