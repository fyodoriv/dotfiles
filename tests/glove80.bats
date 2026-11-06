#!/usr/bin/env bats
# dotfiles-glove80: asks before it pairs, opens Bluetooth settings, waits for
# the Glove80 (a BLE device) to connect,
# and tells the user which Bluetooth profile key to press.

load test_helper

SCRIPT="$BATS_TEST_DIRNAME/../bin/dotfiles-glove80"

setup() {
  TEST_DIR="$(mktemp -d)"
  if [ ! -x "$SCRIPT" ]; then
    if [ "${GLOVE80_REQUIRE_IMPLEMENTATION:-0}" = 1 ]; then
      echo "Glove80 command is not implemented" >&2
      return 1
    fi
    skip "Glove80 command is not implemented yet"
  fi
  mkdir -p "$TEST_DIR/bin"
  export SP_STATE="$TEST_DIR/sp-state" OPEN_LOG="$TEST_DIR/open.log"
  : > "$SP_STATE"
  cat > "$TEST_DIR/bin/system_profiler" <<'MOCK'
#!/bin/bash
echo "Bluetooth:"
case "$(cat "$SP_STATE")" in
  connected) printf '      Connected:\n          Glove80:\n              Address: AA\n' ;;
  paired) printf '      Not Connected:\n          Glove80:\n              Address: AA\n' ;;
esac
MOCK
  cat > "$TEST_DIR/bin/open" <<'MOCK'
#!/bin/bash
echo "$*" >> "$OPEN_LOG"
echo connected > "$SP_STATE"
MOCK
  chmod +x "$TEST_DIR/bin/system_profiler" "$TEST_DIR/bin/open"
  PATH="$TEST_DIR/bin:$PATH"
  export GLOVE80_KEYMAP="$BATS_TEST_DIRNAME/fixtures/glove80-factory.keymap"
  export GLOVE80_WAIT_SECONDS=4
  export GLOVE80_LOG="$TEST_DIR/glove80.log"
  export GLOVE80_PROFILE_FILE="$TEST_DIR/glove80-profile"
  unset GLOVE80_BT_PROFILE
}

teardown() { rm -rf "$TEST_DIR"; }

@test "pair stops when the user says no" {
  run bash -c "echo n | '$SCRIPT' pair --profile 2"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Cancelled"* ]]
  [ ! -s "$OPEN_LOG" ]
}

@test "pair names the profile key and waits for the connection after yes" {
  run bash -c "echo y | '$SCRIPT' pair --profile 2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BT Profile 2"* ]]
  [[ "$output" == *"tap Left Shift (left thumb, upper row, key 1 from the left)"* ]]
  [[ "$output" == *"Magic + F1"* ]]
  grep -q "com.apple.BluetoothSettings" "$OPEN_LOG"
  [[ "$output" == *"Glove80: connected"* ]]
  [ "$(cat "$GLOVE80_PROFILE_FILE")" = "2" ]
}

@test "pair rejects a profile outside 0-3" {
  run "$SCRIPT" pair --profile 4 --yes
  [ "$status" -eq 2 ]
}

@test "status reports not paired" {
  run "$SCRIPT" status
  [ "$status" -eq 1 ]
  [[ "$output" == *"not paired"* ]]
}

@test "status reports connected" {
  echo connected > "$SP_STATE"
  run "$SCRIPT" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"connected"* ]]
}

@test "keys reads each profile key from the factory keymap" {
  run "$SCRIPT" keys
  [ "$status" -eq 0 ]
  [[ "$output" == *"BT Profile 0: Magic + Backspace (left thumb, lower row, key 1 from the left)"* ]]
  [[ "$output" == *"BT Profile 1: Magic + Delete"* ]]
  [[ "$output" == *"BT Profile 2: Magic + Left Shift (left thumb, upper row, key 1 from the left)"* ]]
  [[ "$output" == *"BT Profile 3: Magic + Left Ctrl"* ]]
  [[ "$output" == *"Clear current profile: Magic + F1"* ]]
}

@test "keys fails on a keymap without a Magic layer" {
  printf 'keymap {\n  base {\n    bindings = <\n &kp A\n >;\n  };\n};\n' > "$TEST_DIR/plain.keymap"
  run "$SCRIPT" keys --keymap "$TEST_DIR/plain.keymap"
  [ "$status" -eq 5 ]
}

@test "status reports paired but not connected" {
  echo paired > "$SP_STATE"
  run "$SCRIPT" status
  [ "$status" -eq 1 ]
  [[ "$output" == *'paired as "Glove80", not connected'* ]]
}

@test "pair times out when the Glove80 never connects" {
  printf '#!/bin/bash\necho "$*" >> "$OPEN_LOG"\n' > "$TEST_DIR/bin/open"
  run "$SCRIPT" pair --profile 2 --yes
  [ "$status" -eq 4 ]
  [[ "$output" == *"did not connect"* ]]
}

@test "pair --verbose logs Bluetooth snapshots to the log file" {
  printf '#!/bin/bash\necho "$*" >> "$OPEN_LOG"\n' > "$TEST_DIR/bin/open"
  GLOVE80_WAIT_SECONDS=10 run "$SCRIPT" pair --profile 2 --yes --verbose
  [ "$status" -eq 4 ]
  [[ "$output" == *"[debug]"* ]]
  grep -q "pair start profile=2" "$GLOVE80_LOG"
  grep -q "timeout after 10s: bt_state=" "$GLOVE80_LOG"
  [[ "$output" == *"Debug log: $GLOVE80_LOG"* ]]
}

@test "status finds a renamed Glove80 by MoErgo vendor and product IDs" {
  cat > "$TEST_DIR/bin/system_profiler" <<'MOCK'
#!/bin/bash
printf '      Connected:\n          my gloves:\n              Address: AA\n              Vendor ID: 0x16C0\n              Product ID: 0x27DB\n          mouse:\n              Vendor ID: 0x046D\n      Not Connected:\n'
MOCK
  run "$SCRIPT" status
  [ "$status" -eq 0 ]
  [[ "$output" == *'connected as "my gloves"'* ]]
}

@test "profile saves this Mac's profile and switch prints its key" {
  run "$SCRIPT" profile 2
  [ "$status" -eq 0 ]
  run "$SCRIPT" profile
  [ "$output" = "2" ]
  run "$SCRIPT" switch
  [[ "$output" == *"BT Profile 2"*"tap Left Shift"* ]]
  run "$SCRIPT" switch 0
  [[ "$output" == *"tap Backspace"* ]]
}

@test "profile rejects a value outside 0-3" {
  run "$SCRIPT" profile 7
  [ "$status" -eq 2 ]
}
