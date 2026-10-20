#!/usr/bin/env bats
# agent-browser-temp-route: isolated agent-browser calls go to temp-browser.
# Stubs replace temp-browser and agent-browser, so no real browser starts.

SCRIPT="$BATS_TEST_DIRNAME/../bin/agent-browser-temp-route"

setup() {
  TEST_DIR="$(mktemp -d)"
  mkdir -p "$TEST_DIR/bin"
  export TEST_DIR
  unset AGENT_ID AGENT_BROWSER_SESSION AGENT_BROWSER_TEMP_REASON AGENT_BROWSER_TEMP_OWNER
  cat > "$TEST_DIR/temp-browser" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$TEST_DIR/temp-browser.log"
if [ "$1" = acquire ] && [ -f "$TEST_DIR/busy" ]; then
  echo "temp-browser: busy, held by other-agent: bot sign-in (pid 42, lease expires x)" >&2
  exit 3
fi
[ "$1" = acquire ] && echo 9399
exit 0
STUB
  cat > "$TEST_DIR/bin/agent-browser" <<'STUB'
#!/bin/bash
printf 'agent-browser'
for arg in "$@"; do printf ' <%s>' "$arg"; done
printf '\n'
STUB
  chmod +x "$TEST_DIR/temp-browser" "$TEST_DIR/bin/agent-browser"
  export TEMP_BROWSER_BIN="$TEST_DIR/temp-browser"
  export PATH="$TEST_DIR/bin:$PATH"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "needs-isolation detects --session-name, --profile, --extension" {
  run "$SCRIPT" --needs-isolation open https://example.com
  [ "$status" -eq 1 ]
  for flag in --session-name --profile --extension; do
    run "$SCRIPT" --needs-isolation "$flag" x open https://example.com
    [ "$status" -eq 0 ]
  done
  run "$SCRIPT" --needs-isolation --session-name=x open https://example.com
  [ "$status" -eq 0 ]
}

@test "session name owns the lock and the call attaches to the temp port" {
  run "$SCRIPT" -- --session-name sso-bot open https://example.com
  [ "$status" -eq 0 ]
  grep -qx 'acquire --owner sso-bot --reason isolated agent-browser session' "$TEST_DIR/temp-browser.log"
  [[ "$output" == *"agent-browser <--cdp> <9399> <--session-name> <sso-bot> <open> <https://example.com>"* ]]
}

@test "AGENT_ID owns the lock when no session name; reason from env" {
  export AGENT_ID=worker-k AGENT_BROWSER_TEMP_REASON="bot sign-in"
  run "$SCRIPT" -- --profile /tmp/p open https://example.com
  [ "$status" -eq 0 ]
  grep -qx 'acquire --owner worker-k --reason bot sign-in' "$TEST_DIR/temp-browser.log"
  [[ "$output" != *"/tmp/p"* ]]
  [[ "$output" == *"<--cdp> <9399> <open>"* ]]
}

@test "busy lock fails loudly with holder and reason, agent-browser not run" {
  touch "$TEST_DIR/busy"
  run "$SCRIPT" -- --session-name mine open https://example.com
  [ "$status" -eq 3 ]
  [[ "$output" == *"held by other-agent: bot sign-in"* ]]
  [[ "$output" != *"agent-browser <"* ]]
}

@test "no owner fails loudly" {
  run "$SCRIPT" -- --extension /tmp/ext open https://example.com
  [ "$status" -eq 2 ]
  [[ "$output" == *"AGENT_ID"* ]]
}

@test "close releases the lock" {
  run "$SCRIPT" -- --session-name sso-bot close
  [ "$status" -eq 0 ]
  grep -qx 'release --owner sso-bot' "$TEST_DIR/temp-browser.log"
}

@test "router never raises or focuses windows" {
  ! grep -nE 'osascript|open -a|activate|--headed' "$SCRIPT"
}
