#!/usr/bin/env bats
# dotfiles-glove80: asks before it pairs, opens Bluetooth settings, waits for
# the Glove80 (a BLE device) to connect,
# and tells the user which Bluetooth profile key to press.

load test_helper

SCRIPT="$BATS_TEST_DIRNAME/../bin/dotfiles-glove80"

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home" XDG_CONFIG_HOME="$TEST_DIR/home/.config" XDG_CACHE_HOME="$TEST_DIR/home/.cache" XDG_STATE_HOME="$TEST_DIR/home/.local/state"
  mkdir -p "$HOME" "$TEST_DIR/bin"
  unset GLOVE80_KEYMAP GLOVE80_WAIT_SECONDS GLOVE80_LOG GLOVE80_PROFILE_FILE GLOVE80_BT_PROFILE GLOVE80_DEBUG GLOVE80_PROBE_TIMEOUT_SECONDS
  export SP_STATE="$TEST_DIR/sp-state" OPEN_LOG="$TEST_DIR/open.log"
  : > "$SP_STATE"
  cat > "$TEST_DIR/bin/system_profiler" <<'MOCK'
#!/bin/bash
printf "Bluetooth:\n      State: On\n      Connected:\n      Not Connected:\n"
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
  export GLOVE80_KEYMAP="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/config/glove80/factory.keymap"
  export GLOVE80_WAIT_SECONDS=4
  export GLOVE80_LOG="$HOME/Library/Logs/dotfiles/glove80.log"
  mkdir -p "$XDG_CONFIG_HOME/chezmoi"
  printf 'data:\n  profile: core\n' > "$XDG_CONFIG_HOME/chezmoi/chezmoi.yaml"
  chmod 600 "$XDG_CONFIG_HOME/chezmoi/chezmoi.yaml"
  unset GLOVE80_BT_PROFILE
  export SCRIPT
}

confirm_pair() {
  export TEST_ANSWER="$1"
  expect <<'EXPECT'
set timeout 20
if {[info exists env(TEST_KEYMAP)]} {
  spawn -noecho $env(SCRIPT) pair --profile 2 --keymap $env(TEST_KEYMAP)
} else {
  spawn -noecho $env(SCRIPT) pair --profile 2
}
expect -re {Continue\? \[y/N\]}
send -- "$env(TEST_ANSWER)\r"
expect eof
set result [wait]
exit [lindex $result 3]
EXPECT
}

teardown() { rm -rf "$TEST_DIR"; }

@test "pair stops when the user says no" {
  run confirm_pair n
  [ "$status" -eq 1 ]
  [[ "$output" == *"Not confirmed"* ]]
  [ ! -s "$OPEN_LOG" ]
}

@test "pair names the profile key and waits for the connection after yes" {
  run confirm_pair y
  [ "$status" -eq 0 ]
  [[ "$output" == *"BT Profile 2"* ]]
  [[ "$output" == *"tap Left Shift (left thumb, upper row, key 1 from the left)"* ]]
  [[ "$output" == *"Magic + F1"* ]]
  grep -q "com.apple.BluetoothSettings" "$OPEN_LOG"
  [[ "$output" == *"Glove80: connected"* ]]
  [ "$(yq -r '.data.glove80_profile' "$XDG_CONFIG_HOME/chezmoi/chezmoi.yaml")" = "2" ]
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
  [[ "$output" == *"connection was not confirmed"* ]]
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
printf 'Bluetooth:\n      State: On\n      Connected:\n          my gloves:\n              Address: AA\n              Vendor ID: 0x16C0\n              Product ID: 0x27DB\n          mouse:\n              Vendor ID: 0x046D\n      Not Connected:\n'
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

@test "an existing connection does not save an unverified requested profile" {
  echo connected > "$SP_STATE"
  run "$SCRIPT" pair --profile 2 --yes
  [ "$(yq -r '.data.glove80_profile // "unset"' "$XDG_CONFIG_HOME/chezmoi/chezmoi.yaml")" = "unset" ]
  [[ "$output" == *"unverified"* ]]
}

@test "an unknown prior state allows settings but never saves a profile automatically" {
  export PROBE_COUNT="$TEST_DIR/probe-count" GLOVE80_WAIT_SECONDS=10
  cat > "$TEST_DIR/bin/system_profiler" <<'MOCK'
#!/bin/bash
if [ "$(cat "$SP_STATE")" = connected ]; then
  count=0
  [ ! -f "$PROBE_COUNT" ] || count="$(cat "$PROBE_COUNT")"
  count=$((count + 1))
  printf '%s\n' "$count" > "$PROBE_COUNT"
  if [ "$count" -ge 3 ]; then
    printf 'Bluetooth:\n      State: On\n      Connected:\n          Glove80:\n              Address: AA\n'
  else
    printf 'Bluetooth:\n      State: On\n      Not Connected:\n'
  fi
else
  printf 'Bluetooth:\n      State: On\n      Not Connected:\n'
fi
MOCK
  for method in unattended interactive; do
    : > "$SP_STATE"
    : > "$OPEN_LOG"
    rm -f "$PROBE_COUNT"
    printf 'data:\n  profile: core\n' > "$XDG_CONFIG_HOME/chezmoi/chezmoi.yaml"
    if [ "$method" = unattended ]; then
      run "$SCRIPT" pair --profile 2 --yes
    else
      run confirm_pair y
    fi
    [ "$status" -eq 0 ]
    [[ "$output" == *"prior Bluetooth state is unknown"* ]]
    [ "$(printf '%s\n' "$output" | grep -ic 'Bluetooth state is unknown')" = 1 ]
    [[ "$output" == *"unverified"* ]]
    [ "$(wc -l < "$OPEN_LOG" | tr -d ' ')" = 1 ]
    [ "$(yq -r '.data.glove80_profile // "unset"' "$XDG_CONFIG_HOME/chezmoi/chezmoi.yaml")" = unset ]
  done
}

@test "a failed Bluetooth probe is unknown, not unpaired" {
  printf '#!/bin/bash\nexit 1\n' > "$TEST_DIR/bin/system_profiler"
  run "$SCRIPT" status
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown"* ]]
}

@test "logs do not contain unrelated device names and are private" {
  cat > "$TEST_DIR/bin/system_profiler" <<'MOCK'
#!/bin/bash
printf 'Bluetooth:\n      State: On\n      Connected:\n          Glove80:\n              Address: AA\n          PrivateFixtureDevice:\n              Address: BB\n'
MOCK
  run "$SCRIPT" status --verbose
  [[ "$output" != *PrivateFixtureDevice* ]]
  [ -f "$GLOVE80_LOG" ]
  ! grep -q PrivateFixtureDevice "$GLOVE80_LOG"
  [ "$(stat -f '%Lp' "$GLOVE80_LOG")" = 600 ]
}

@test "unknown keymap never suggests clearing or opens Bluetooth" {
  printf 'invalid keymap\n' > "$TEST_DIR/unknown.keymap"
  run "$SCRIPT" pair --profile 2 --keymap "$TEST_DIR/unknown.keymap" --yes
  [ "$status" -ne 0 ]
  ! printf '%s\n' "$output" | grep -qiE 'clear|unpair|forget'
  [ ! -s "$OPEN_LOG" ]
  [ "$(yq -r '.data.glove80_profile // "unset"' "$XDG_CONFIG_HOME/chezmoi/chezmoi.yaml")" = "unset" ]
}

@test "hung Bluetooth probe is bounded and does not report unpaired" {
  command -v gtimeout >/dev/null
  export PROBE_PID="$TEST_DIR/probe.pid"
  printf '#!/bin/bash\necho $$ > "$PROBE_PID"\nexec sleep 11\n' > "$TEST_DIR/bin/system_profiler"
  export GLOVE80_PROBE_TIMEOUT_SECONDS=1
  start="$(perl -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC -e 'printf "%.0f", clock_gettime(CLOCK_MONOTONIC) * 1000')"
  run gtimeout --kill-after=1s 10s "$SCRIPT" status
  finish="$(perl -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC -e 'printf "%.0f", clock_gettime(CLOCK_MONOTONIC) * 1000')"
  if [ -f "$PROBE_PID" ] && kill -0 "$(cat "$PROBE_PID")" 2>/dev/null; then
    return 1
  fi
  [ "$status" -ne 124 ]
  [ "$status" -lt 128 ]
  [ "$status" -ne 0 ]
  [ "$((finish - start))" -lt 9000 ]
  [[ "$output" == *"unknown"* ]]
}

@test "Glove80 is discoverable in the shared actions registry" {
  run bash "$BATS_TEST_DIRNAME/../bin/dotfiles" actions --json
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '[.[] | select(.name == "glove80") | select(.agent and any(.subforms[]; (.usage | contains("pair")) and .needs_yes and .gated))] | length == 1'
  grep -q 'dotfiles glove80' "$BATS_TEST_DIRNAME/../commands/dotfiles.md"
  run bash "$BATS_TEST_DIRNAME/../bin/dotfiles" actions --check
  [ "$status" -eq 0 ]
  run bash "$BATS_TEST_DIRNAME/../bin/dotfiles" glove80 status
  [[ "$output" == *"not paired"* ]]
}

@test "malformed successful Bluetooth output is unknown" {
  printf '#!/bin/bash\nprintf garbage\n' > "$TEST_DIR/bin/system_profiler"
  run "$SCRIPT" status
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown"* ]]
  [[ "$output" != *"not paired"* ]]
}

@test "a symlink log never changes its target" {
  local target="$TEST_DIR/sentinel"
  printf 'unchanged\n' > "$target"
  chmod 644 "$target"
  mkdir -p "$(dirname "$GLOVE80_LOG")"
  ln -s "$target" "$GLOVE80_LOG"
  run "$SCRIPT" status
  [ "$(cat "$target")" = unchanged ]
  [ "$(stat -f '%Lp' "$target")" = 644 ]
}

@test "an invalid wait limit does not open Bluetooth" {
  export GLOVE80_WAIT_SECONDS=0
  run "$SCRIPT" pair --profile 2 --yes
  [ "$status" -ne 0 ]
  [ ! -s "$OPEN_LOG" ]
}

@test "an unreadable keymap cannot save a profile" {
  export GLOVE80_KEYMAP="$TEST_DIR/missing.keymap"
  run "$SCRIPT" profile 2
  [ "$status" -ne 0 ]
  [ "$(yq -r '.data.glove80_profile // "unset"' "$XDG_CONFIG_HOME/chezmoi/chezmoi.yaml")" = unset ]
}

@test "slow Bluetooth probes respect the total pairing deadline" {
  command -v gtimeout >/dev/null
  printf '#!/bin/bash\nsleep 4\nprintf "Bluetooth:\\n"\n' > "$TEST_DIR/bin/system_profiler"
  export GLOVE80_WAIT_SECONDS=2 GLOVE80_PROBE_TIMEOUT_SECONDS=5
  local start finish
  start="$(perl -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC -e 'printf "%.0f", clock_gettime(CLOCK_MONOTONIC) * 1000')"
  run gtimeout --kill-after=1s 8s "$SCRIPT" pair --profile 2 --yes
  finish="$(perl -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC -e 'printf "%.0f", clock_gettime(CLOCK_MONOTONIC) * 1000')"
  [ "$status" -ne 0 ]
  [ "$status" -ne 124 ]
  [ "$status" -lt 128 ]
  [ "$((finish - start))" -lt 6000 ]
}

@test "header-only and disabled Bluetooth reports are unknown" {
  for value in 'Bluetooth:' $'Bluetooth:\n      State: Off'; do
    printf '#!/bin/bash\nprintf "%%s\\n" %q\n' "$value" > "$TEST_DIR/bin/system_profiler"
    run "$SCRIPT" status
    [ "$status" -ne 0 ]
    [[ "$output" == *unknown* ]]
  done
}

@test "custom keymap survives interactive pairing and save" {
  export TEST_KEYMAP="$TEST_DIR/custom.keymap"
  sed 's/\&kp LSHFT/\&kp TAB/' "$GLOVE80_KEYMAP" > "$TEST_KEYMAP"
  run confirm_pair y
  [ "$status" -eq 0 ]
  [[ "$output" == *"Saved user-asserted BT Profile 2 (Magic + TAB"* ]]
}

@test "a saved custom layout never silently falls back to factory keys" {
  export TEST_KEYMAP="$TEST_DIR/custom.keymap"
  sed 's/\&kp LSHFT/\&kp TAB/' "$GLOVE80_KEYMAP" > "$TEST_KEYMAP"
  local custom="$TEST_KEYMAP"
  run confirm_pair y
  [ "$status" -eq 0 ]
  [ "$(yq -r '.data.glove80_profile' "$XDG_CONFIG_HOME/chezmoi/chezmoi.yaml")" = custom-2 ]
  unset GLOVE80_KEYMAP TEST_KEYMAP
  run "$SCRIPT" switch
  [ "$status" -ne 0 ]
  [[ "$output" == *"custom keymap"* ]]
  run "$SCRIPT" status
  [ "$status" -ne 0 ]
  [[ "$output" == *"custom keymap"* ]]
  run "$SCRIPT" switch --keymap "$custom"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tap TAB"* ]]
  run "$SCRIPT" status --keymap "$custom"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Magic + TAB"* ]]
}

@test "changing a profile cannot silently erase a saved custom layout" {
  export TEST_KEYMAP="$TEST_DIR/custom.keymap"
  sed 's/\&kp LSHFT/\&kp TAB/' "$GLOVE80_KEYMAP" > "$TEST_KEYMAP"
  run confirm_pair y
  [ "$status" -eq 0 ]
  unset GLOVE80_KEYMAP TEST_KEYMAP
  run "$SCRIPT" profile 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"custom keymap"* ]]
  [ "$(yq -r '.data.glove80_profile' "$XDG_CONFIG_HOME/chezmoi/chezmoi.yaml")" = custom-2 ]
  run "$SCRIPT" switch
  [ "$status" -ne 0 ]
  [[ "$output" == *"custom keymap"* ]]
}

@test "profile accepts an explicit custom keymap and rejects malformed arguments" {
  export TEST_KEYMAP="$TEST_DIR/custom.keymap"
  sed 's/\&kp LSHFT/\&kp TAB/' "$GLOVE80_KEYMAP" > "$TEST_KEYMAP"
  local custom="$TEST_KEYMAP"
  run confirm_pair y
  [ "$status" -eq 0 ]
  unset GLOVE80_KEYMAP TEST_KEYMAP
  run "$SCRIPT" profile 1 --keymap "$custom"
  [ "$status" -eq 0 ]
  [ "$(yq -r '.data.glove80_profile' "$XDG_CONFIG_HOME/chezmoi/chezmoi.yaml")" = custom-1 ]
  run "$SCRIPT" profile 2 --keymap
  [ "$status" -ne 0 ]
  run "$SCRIPT" profile 2 --keymap "$custom" extra
  [ "$status" -ne 0 ]
  [ "$(yq -r '.data.glove80_profile' "$XDG_CONFIG_HOME/chezmoi/chezmoi.yaml")" = custom-1 ]
}

@test "a symlinked log parent never changes its target" {
  mkdir -p "$HOME/real"
  ln -s "$HOME/real" "$HOME/linked"
  export GLOVE80_LOG="$HOME/linked/log"
  run "$SCRIPT" status
  [ ! -e "$HOME/real/log" ]
}

@test "a hardlinked log never changes its target" {
  local target="$TEST_DIR/hardlink-target"
  printf 'unchanged\n' > "$target"
  chmod 600 "$target"
  mkdir -p "$(dirname "$GLOVE80_LOG")"
  ln "$target" "$GLOVE80_LOG"
  run "$SCRIPT" status
  [ "$(cat "$target")" = unchanged ]
}

@test "log failure happens before saving a profile" {
  mkdir -p "$(dirname "$GLOVE80_LOG")"
  ln -s "$TEST_DIR/missing" "$GLOVE80_LOG"
  run "$SCRIPT" profile 2
  [ "$status" -ne 0 ]
  [ "$(yq -r '.data.glove80_profile // "unset"' "$XDG_CONFIG_HOME/chezmoi/chezmoi.yaml")" = unset ]
}

@test "a slow settings opener cannot exceed the total deadline" {
  printf '#!/bin/bash\nsleep 7\n' > "$TEST_DIR/bin/open"
  export GLOVE80_WAIT_SECONDS=2
  local start finish
  start="$(perl -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC -e 'printf "%.0f", clock_gettime(CLOCK_MONOTONIC) * 1000')"
  run gtimeout --kill-after=1s 9s "$SCRIPT" pair --profile 2 --yes
  finish="$(perl -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC -e 'printf "%.0f", clock_gettime(CLOCK_MONOTONIC) * 1000')"
  [ "$status" -ne 0 ]
  [ "$status" -ne 124 ]
  [ "$status" -lt 128 ]
  [ "$((finish - start))" -lt 6000 ]
}

@test "a slow post-open probe cannot exceed the total deadline" {
  cat > "$TEST_DIR/bin/system_profiler" <<'MOCK'
#!/bin/bash
[ -s "$OPEN_LOG" ] && sleep 7
printf 'Bluetooth:\n      State: On\n      Connected:\n      Not Connected:\n'
MOCK
  printf '#!/bin/bash\necho open >> "$OPEN_LOG"\n' > "$TEST_DIR/bin/open"
  export GLOVE80_WAIT_SECONDS=2 GLOVE80_PROBE_TIMEOUT_SECONDS=10
  local start finish
  start="$(perl -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC -e 'printf "%.0f", clock_gettime(CLOCK_MONOTONIC) * 1000')"
  run gtimeout --kill-after=1s 9s "$SCRIPT" pair --profile 2 --yes
  finish="$(perl -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC -e 'printf "%.0f", clock_gettime(CLOCK_MONOTONIC) * 1000')"
  [ "$status" -ne 0 ]
  [ "$status" -ne 124 ]
  [ "$status" -lt 128 ]
  [ "$((finish - start))" -lt 6000 ]
}

@test "a slow config save is bounded and reports an uncertain outcome" {
  export REAL_YQ="$(command -v yq)"
  cat > "$TEST_DIR/bin/yq" <<'MOCK'
#!/bin/bash
case "$*" in *'strenv(DOTFILES_CONFIG_KEY)'*) sleep 7 ;; esac
exec "$REAL_YQ" "$@"
MOCK
  chmod +x "$TEST_DIR/bin/yq"
  export GLOVE80_WAIT_SECONDS=2
  export -f confirm_pair
  local start finish
  start="$(perl -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC -e 'printf "%.0f", clock_gettime(CLOCK_MONOTONIC) * 1000')"
  run gtimeout --kill-after=1s 9s bash -c 'confirm_pair y'
  finish="$(perl -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC -e 'printf "%.0f", clock_gettime(CLOCK_MONOTONIC) * 1000')"
  [ "$status" -ne 0 ]
  [ "$status" -ne 124 ]
  [ "$status" -lt 128 ]
  [ "$((finish - start))" -lt 6000 ]
  [[ "$output" == *"may have completed"* ]]
}

@test "truncated enabled Bluetooth report is unknown" {
  printf '#!/bin/bash\nprintf "Bluetooth:\\n      State: On\\n"\n' > "$TEST_DIR/bin/system_profiler"
  run "$SCRIPT" status
  [ "$status" -ne 0 ]
  [[ "$output" == *unknown* ]]
}

@test "a FIFO keymap is rejected without waiting for a writer" {
  mkfifo "$TEST_DIR/map.fifo"
  run gtimeout --kill-after=1s 5s "$SCRIPT" pair --profile 2 --keymap "$TEST_DIR/map.fifo" --yes
  [ "$status" -ne 0 ]
  [ "$status" -ne 124 ]
  [ "$status" -lt 128 ]
  [ ! -s "$OPEN_LOG" ]
  [[ "$output" == *"Unknown keymap"* ]]
}

@test "a symlink in a log ancestor is refused" {
  mkdir -p "$HOME/real/child"
  ln -s "$HOME/real" "$HOME/alias"
  export GLOVE80_LOG="$HOME/alias/child/log"
  run "$SCRIPT" status
  [ ! -e "$HOME/real/child/log" ]
}

@test "a writable log directory is refused" {
  mkdir -p "$HOME/writable"
  chmod 777 "$HOME/writable"
  export GLOVE80_LOG="$HOME/writable/log"
  run "$SCRIPT" status
  [ ! -e "$GLOVE80_LOG" ]
}

@test "a report with only one device section cannot establish absence" {
  cat > "$TEST_DIR/bin/system_profiler" <<'MOCK'
#!/bin/bash
printf 'Bluetooth:\n      State: On\n      %s:\n' "$FIXTURE_SECTION"
MOCK
  for FIXTURE_SECTION in Connected 'Not Connected'; do
    export FIXTURE_SECTION
    run "$SCRIPT" status
    [ "$status" -ne 0 ]
    [[ "$output" == *unknown* ]]
    [[ "$output" != *"not paired"* ]]
  done
}
