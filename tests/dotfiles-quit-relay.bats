#!/usr/bin/env bats
# bin/dotfiles-quit-relay runs a LaunchAgent Chrome so a macOS restart,
# shut down, or log out can quit it (issue #298). Chrome ignores the quit
# Apple Event; the relay starts a small accessory app (lib/quit-watcher.swift)
# that macOS does ask to quit, and that app sends SIGUSR1 to the relay. The
# relay then sends SIGTERM to Chrome and exits 0. Fakes stand in for Chrome
# and the watcher here; no real Chrome runs.

load test_helper

RELAY="$BATS_TEST_DIRNAME/../bin/dotfiles-quit-relay"

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME" "$TEST_DIR/bin"
  # A fake Chrome: records its args, waits, and logs the signal that stops it.
  cat > "$TEST_DIR/bin/fake-chrome" <<EOF2
#!/bin/bash
echo "\$*" > "$TEST_DIR/chrome.args"
echo \$\$ > "$TEST_DIR/chrome.pid"
trap 'echo TERM >> "$TEST_DIR/chrome.log"; exit 0' TERM
while :; do sleep 0.1; done
EOF2
  # A fake watcher: records the relay PID it was given, then waits.
  cat > "$TEST_DIR/bin/fake-watcher" <<EOF2
#!/bin/bash
echo "\$1" > "$TEST_DIR/watcher.relay"
echo \$\$ > "$TEST_DIR/watcher.pid"
while :; do sleep 0.1; done
EOF2
  chmod +x "$TEST_DIR/bin/fake-chrome" "$TEST_DIR/bin/fake-watcher"
  export DOTFILES_QUIT_WATCHER="$TEST_DIR/bin/fake-watcher"
}

teardown() {
  for f in chrome.pid watcher.pid relay.pid; do
    [ -f "$TEST_DIR/$f" ] && kill "$(cat "$TEST_DIR/$f")" 2>/dev/null || true
  done
  rm -rf "$TEST_DIR"
}

wait_for() { local i; for i in $(seq 50); do [ -e "$1" ] && return 0; sleep 0.1; done; return 1; }

start_relay() {
  "$RELAY" "$TEST_DIR/bin/fake-chrome" --remote-debugging-port=1 --headless=new &
  echo $! > "$TEST_DIR/relay.pid"
  wait_for "$TEST_DIR/chrome.pid"
  wait_for "$TEST_DIR/watcher.pid"
}

@test "the relay runs Chrome with its arguments and gives the watcher its own PID" {
  start_relay
  [ "$(cat "$TEST_DIR/chrome.args")" = "--remote-debugging-port=1 --headless=new" ]
  [ "$(cat "$TEST_DIR/watcher.relay")" = "$(cat "$TEST_DIR/relay.pid")" ]
}

@test "a quit request (SIGUSR1 from the watcher) sends SIGTERM to Chrome and the relay exits 0" {
  start_relay
  kill -USR1 "$(cat "$TEST_DIR/relay.pid")"
  rc=0; wait "$(cat "$TEST_DIR/relay.pid")" || rc=$?
  [ "$rc" -eq 0 ]
  [ "$(cat "$TEST_DIR/chrome.log")" = TERM ]
  ! kill -0 "$(cat "$TEST_DIR/chrome.pid")" 2>/dev/null
  ! kill -0 "$(cat "$TEST_DIR/watcher.pid")" 2>/dev/null
}

@test "SIGTERM to the relay (launchctl stop) stops Chrome too" {
  start_relay
  kill -TERM "$(cat "$TEST_DIR/relay.pid")"
  wait "$(cat "$TEST_DIR/relay.pid")" || true
  [ "$(cat "$TEST_DIR/chrome.log")" = TERM ]
  ! kill -0 "$(cat "$TEST_DIR/watcher.pid")" 2>/dev/null
}

@test "when Chrome exits on its own, the relay stops the watcher and exits with Chrome's status" {
  printf '#!/bin/bash\necho $$ > "%s/chrome.pid"\nsleep 0.5\nexit 7\n' "$TEST_DIR" > "$TEST_DIR/bin/fake-chrome"
  run "$RELAY" "$TEST_DIR/bin/fake-chrome"
  [ "$status" -eq 7 ]
  ! kill -0 "$(cat "$TEST_DIR/watcher.pid")" 2>/dev/null
}

@test "without a watcher (no swiftc), Chrome still runs, and the relay says why" {
  export DOTFILES_QUIT_WATCHER="" DOTFILES_SWIFTC=/nonexistent/swiftc
  printf '#!/bin/bash\nexit 0\n' > "$TEST_DIR/bin/fake-chrome"
  run "$RELAY" "$TEST_DIR/bin/fake-chrome"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"swiftc"* ]]
}

@test "the agent-browser Chrome LaunchAgent runs Chrome through the relay" {
  plist="$BATS_TEST_DIRNAME/../launchagents/com.dotfiles.agent-browser-chrome.plist.tmpl"
  args="$(awk '/<key>ProgramArguments<\/key>/,/<\/array>/' "$plist" | sed -n 's/.*<string>\(.*\)<\/string>.*/\1/p')"
  [ "$(sed -n 1p <<< "$args")" = /bin/bash ]
  [[ "$(sed -n 2p <<< "$args")" == */bin/dotfiles-quit-relay ]]
  [ "$(sed -n 3p <<< "$args")" = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ]
}

@test "the quit watcher Swift source type-checks" {
  command -v swiftc >/dev/null 2>&1 || skip "swiftc not installed"
  swiftc -typecheck "$BATS_TEST_DIRNAME/../lib/quit-watcher.swift"
}

@test "a Chrome that ignores SIGTERM is killed after the grace time, so it cannot block the restart" {
  printf '#!/bin/bash\necho $$ > "%s/chrome.pid"\ntrap "" TERM\nwhile :; do sleep 0.1; done\n' "$TEST_DIR" > "$TEST_DIR/bin/fake-chrome"
  DOTFILES_QUIT_GRACE=1 start_relay
  SECONDS=0
  kill -USR1 "$(cat "$TEST_DIR/relay.pid")"
  rc=0; wait "$(cat "$TEST_DIR/relay.pid")" || rc=$?
  [ "$rc" -eq 0 ]
  [ "$SECONDS" -lt 5 ]
  ! kill -0 "$(cat "$TEST_DIR/chrome.pid")" 2>/dev/null
}
