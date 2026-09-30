#!/usr/bin/env bats

REPO_ROOT="$BATS_TEST_DIRNAME/.."
WRAPPER="$REPO_ROOT/bin/cursor-at-login"

setup() {
  TEST_DIR="$(mktemp -d)"
  export MOCK_LOG="$TEST_DIR/actions.log"
  export MOCK_NC_COUNT="$TEST_DIR/nc-count"
  export MOCK_NC_FAILS=0
  touch "$MOCK_LOG"

  cat > "$TEST_DIR/nc" <<'EOF'
#!/bin/bash
count=0
[ ! -f "$MOCK_NC_COUNT" ] || count="$(< "$MOCK_NC_COUNT")"
count=$((count + 1))
printf '%s\n' "$count" > "$MOCK_NC_COUNT"
[ "$count" -gt "$MOCK_NC_FAILS" ]
EOF
  cat > "$TEST_DIR/agentbrew" <<'EOF'
#!/bin/bash
printf 'agentbrew %s\n' "$*" >> "$MOCK_LOG"
EOF
  cat > "$TEST_DIR/open" <<'EOF'
#!/bin/bash
printf 'open %s\n' "$*" >> "$MOCK_LOG"
EOF
  cat > "$TEST_DIR/sleep" <<'EOF'
#!/bin/bash
printf 'sleep %s\n' "$*" >> "$MOCK_LOG"
EOF
  chmod +x "$TEST_DIR/nc" "$TEST_DIR/agentbrew" \
    "$TEST_DIR/open" "$TEST_DIR/sleep"

  export CURSOR_LOGIN_NC_BIN="$TEST_DIR/nc"
  export CURSOR_LOGIN_AGENTBREW_BIN="$TEST_DIR/agentbrew"
  export CURSOR_LOGIN_OPEN_BIN="$TEST_DIR/open"
  export CURSOR_LOGIN_SLEEP_BIN="$TEST_DIR/sleep"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "launches Cursor in the background when memory is ready" {
  CURSOR_LOGIN_WAIT_FOR_MEMORY=true run "$WRAPPER"

  [ "$status" -eq 0 ]
  grep -qx 'open -g -a Cursor' "$MOCK_LOG"
  grep -qx 'agentbrew memory doctor --ready' "$MOCK_LOG"
  ! grep -q '^agentbrew memory fix$' "$MOCK_LOG"
}

@test "runs agentbrew memory fix and waits before launching Cursor" {
  export MOCK_NC_FAILS=2

  CURSOR_LOGIN_WAIT_FOR_MEMORY=true run "$WRAPPER"

  [ "$status" -eq 0 ]
  grep -qx 'agentbrew memory fix --json' "$MOCK_LOG"
  grep -qx 'agentbrew memory doctor --ready' "$MOCK_LOG"
  grep -q '^sleep 1$' "$MOCK_LOG"
  grep -qx 'open -g -a Cursor' "$MOCK_LOG"
}

@test "skips the memory wait when AI tools are disabled" {
  export MOCK_NC_FAILS=99

  CURSOR_LOGIN_WAIT_FOR_MEMORY=false run "$WRAPPER"

  [ "$status" -eq 0 ]
  [ ! -f "$MOCK_NC_COUNT" ]
  ! grep -q '^agentbrew ' "$MOCK_LOG"
  grep -qx 'open -g -a Cursor' "$MOCK_LOG"
}

@test "launches degraded after the bounded memory wait" {
  export MOCK_NC_FAILS=99

  CURSOR_LOGIN_WAIT_FOR_MEMORY=true \
    CURSOR_LOGIN_MEMORY_WAIT_SECONDS=0 \
    run "$WRAPPER"

  [ "$status" -eq 0 ]
  [[ "$output" == *"memory MCP did not become ready within 0s"* ]]
  grep -qx 'open -g -a Cursor' "$MOCK_LOG"
}
