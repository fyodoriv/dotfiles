#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../bin/agent-browser-singleton-preflight"

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME/.agent-browser/chrome-profile" "$HOME/.agent-browser/debug-profile" "$HOME/.agent-browser/tooling-profile"
  STUB_BIN="$TEST_DIR/bin"
  mkdir -p "$STUB_BIN"
  : > "$TEST_DIR/responsive-ports"
  cat > "$STUB_BIN/curl" <<'EOF'
#!/bin/bash
url=""
for arg in "$@"; do
  case "$arg" in http://*) url="$arg" ;;
  esac
done
port="$(printf '%s\n' "$url" | sed -n 's#.*127\.0\.0\.1:\([0-9][0-9]*\)/.*#\1#p')"
if grep -qx "$port" "$TEST_DIR/responsive-ports"; then
  printf '{"Browser":"fake"}\n'
  exit 0
fi
exit 7
EOF
  cat > "$STUB_BIN/agent-browser" <<'EOF'
#!/bin/bash
printf 'agent-browser'
for arg in "$@"; do printf ' <%s>' "$arg"; done
printf '\nprofile=%s\n' "${AGENT_BROWSER_PROFILE-__unset__}"
EOF
  chmod +x "$STUB_BIN/curl" "$STUB_BIN/agent-browser"
  export TEST_DIR
  export PATH="$STUB_BIN:$PATH"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "preflight attaches managed chrome-profile to port 9223 and clears profile env" {
  echo 9223 > "$TEST_DIR/responsive-ports"
  export AGENT_BROWSER_PROFILE="$HOME/.agent-browser/chrome-profile"

  run "$SCRIPT" --profile "$HOME/.agent-browser/chrome-profile" -- open https://example.com

  [ "$status" -eq 0 ]
  [[ "$output" == *"agent-browser <--cdp> <9223> <open> <https://example.com>"* ]]
  [[ "$output" == *"profile=__unset__"* ]]
}

@test "preflight maps every launchd-owned profile to its managed CDP port" {
  printf '9223\n9224\n9225\n' > "$TEST_DIR/responsive-ports"

  run "$SCRIPT" --print-cdp "$HOME/.agent-browser/chrome-profile/"
  [ "$status" -eq 0 ]
  [ "$output" = "9223" ]

  run "$SCRIPT" --print-cdp "$HOME/.agent-browser/debug-profile"
  [ "$status" -eq 0 ]
  [ "$output" = "9224" ]

  run "$SCRIPT" --print-cdp "~/.agent-browser/tooling-profile"
  [ "$status" -eq 0 ]
  [ "$output" = "9225" ]
}

@test "preflight refuses managed profile launch when singleton lock exists but CDP is down" {
  touch "$HOME/.agent-browser/debug-profile/SingletonLock"

  run "$SCRIPT" --profile "$HOME/.agent-browser/debug-profile" -- open https://example.com

  [ "$status" -eq 2 ]
  [[ "$output" == *"Refusing to launch Chrome against launchd-owned profile"* ]]
  [[ "$output" == *"9224"* ]]
  [[ "$output" != *"agent-browser <"* ]]
}

@test "preflight passes non-managed profiles through without CDP rewriting" {
  custom_profile="$TEST_DIR/custom-profile"
  mkdir -p "$custom_profile"

  run "$SCRIPT" --profile "$custom_profile" -- open https://example.com

  [ "$status" -eq 0 ]
  [[ "$output" == *"agent-browser <open> <https://example.com>"* ]]
  [[ "$output" != *"<--cdp>"* ]]
  [[ "$output" == *"profile=$custom_profile"* ]]
}
