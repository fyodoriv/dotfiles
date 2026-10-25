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

# --- #237: core option chrome.dock_guard ---

@test "chrome.dock_guard is a core boolean option that defaults to true" {
  run yq -r '.options["chrome.dock_guard"] | .type + " " + (.default | tostring)' \
    "$BATS_TEST_DIRNAME/../config/plugin-options.yaml"
  [ "$output" = "boolean true" ]
}

@test "chrome.dock_guard=false turns the guard off only with a headed purpose Chrome" {
  lib="$BATS_TEST_DIRNAME/../lib/chrome-purpose-options.sh"
  run bash -c "source '$lib'; chrome_dock_guard_enabled false true"
  [ "$status" -eq 1 ]
  run bash -c "source '$lib'; chrome_dock_guard_enabled false false"
  [ "$status" -eq 0 ]
  run bash -c "source '$lib'; chrome_dock_guard_enabled true true"
  [ "$status" -eq 0 ]
}

@test "apply skips (and removes) the guard LaunchAgent when the guard is off" {
  src="$BATS_TEST_DIRNAME/../.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
  run bash -c "eval \"\$(sed -n '/^should_skip_agent() {/,/^}/p' '$src')\"; CHROME_DOCK_GUARD=false should_skip_agent chrome-dock-guard"
  [ "$status" -eq 0 ]
  run bash -c "eval \"\$(sed -n '/^should_skip_agent() {/,/^}/p' '$src')\"; CHROME_DOCK_GUARD=true should_skip_agent chrome-dock-guard"
  [ "$status" -eq 1 ]
  grep -q 'CHROME_DOCK_GUARD=' "$src"
}

@test "doctor skips the guard check when the guard is off" {
  run env DOTFILES_CHROME_DOCK_GUARD=false DOTFILES_CHROME_PURPOSE_HEADED=true \
    "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor" --module agent-browser --list
  [[ "$output" != *agent-browser.chrome_dock_guard* ]]
  run env DOTFILES_CHROME_DOCK_GUARD=false DOTFILES_CHROME_PURPOSE_HEADED=false \
    "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor" --module agent-browser --list
  [[ "$output" == *agent-browser.chrome_dock_guard* ]]
}

# --- deaf watcher: started during login, it got no activation events for 2 days ---

@test "stale: the window owner or frontmost pid changed with no event means a dead event stream" {
  need_swiftc
  run bash "$GUARD_CMD" --stale 100 200 5 5 0
  [ "$status" -eq 0 ]
  [ "$output" = "stale" ]
  run bash "$GUARD_CMD" --stale 100 100 5 6 0
  [ "$output" = "stale" ]
}

@test "stale: a change with an event, no change, or an unknown pid (0) is healthy" {
  need_swiftc
  run bash "$GUARD_CMD" --stale 100 200 5 6 1
  [ "$output" = "ok" ]
  run bash "$GUARD_CMD" --stale 100 100 5 5 0
  [ "$output" = "ok" ]
  run bash "$GUARD_CMD" --stale 100 0 5 5 0
  [ "$output" = "ok" ]
  run bash "$GUARD_CMD" --stale 0 200 0 6 0
  [ "$output" = "ok" ]
}

@test "stale-run: only two stale samples in a row trigger the exit" {
  need_swiftc
  run bash "$GUARD_CMD" --stale-run s h s
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
  run bash "$GUARD_CMD" --stale-run h s s
  [ "$output" = "2 exit" ]
}

@test "stale and stale-run reject bad arguments with exit 2" {
  need_swiftc
  run bash "$GUARD_CMD" --stale 100 x 5 5 0
  [ "$status" -eq 2 ]
  run bash "$GUARD_CMD" --stale 100 200
  [ "$status" -eq 2 ]
  run bash "$GUARD_CMD" --stale-run s x
  [ "$status" -eq 2 ]
}
