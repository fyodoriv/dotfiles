#!/usr/bin/env bats
# Tests for the process-scoped Cursor and Claude Code sleep manager.

KEEPAWAKE_BIN="$BATS_TEST_DIRNAME/../bin/dotfiles-agent-keepawake"
KEEPAWAKE_LIB="$BATS_TEST_DIRNAME/../lib/agent-keepawake.sh"
PLIST="$BATS_TEST_DIRNAME/../launchagents/com.dotfiles.agent-keepawake.plist.tmpl"

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  STUB_BIN="$TEST_DIR/bin"
  PS_COMMANDS_DIR="$TEST_DIR/ps-commands"
  PS_SNAPSHOT_FILE="$TEST_DIR/ps-snapshot"
  CAFFEINATE_CHILD_PIDS="$TEST_DIR/caffeinate-pids"
  AMPHETAMINE_STATE="$TEST_DIR/amphetamine-state"
  AMPHETAMINE_CLOSED_DISPLAY_STATE="$TEST_DIR/amphetamine-closed-display-state"
  OSASCRIPT_LOG="$TEST_DIR/osascript.log"
  OSASCRIPT_OPERATION_LOG="$TEST_DIR/osascript-operations.log"
  PMSET_OUTPUT_FILE="$TEST_DIR/pmset-output"
  CLAUDE_PATH="$TEST_DIR/claude-code"
  TARGET_PIDS="$TEST_DIR/target-pids"
  ORIGINAL_HOME="$HOME"

  mkdir -p "$TEST_HOME" "$STUB_BIN" "$PS_COMMANDS_DIR" "$TEST_DIR/Amphetamine.app/Contents"
  : > "$PS_SNAPSHOT_FILE"
  : > "$CAFFEINATE_CHILD_PIDS"
  : > "$TARGET_PIDS"
  printf 'false\n' > "$AMPHETAMINE_STATE"
  printf 'false\n' > "$AMPHETAMINE_CLOSED_DISPLAY_STATE"
  cat > "$TEST_DIR/Amphetamine.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleVersion</key><string>1</string></dict></plist>
PLIST
  printf "Now drawing from 'AC Power'\n" > "$PMSET_OUTPUT_FILE"

  cat > "$STUB_BIN/pmset" <<'STUB'
#!/bin/bash
cat "$PMSET_OUTPUT_FILE"
STUB

  cat > "$STUB_BIN/ps" <<'STUB'
#!/bin/bash
for arg in "$@"; do
  if [ "$arg" = "-axww" ]; then
    cat "$PS_SNAPSHOT_FILE"
    exit 0
  fi
done
pid=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-p" ]; then
    pid="$2"
    break
  fi
  shift
done
[ -n "$pid" ] && cat "$PS_COMMANDS_DIR/$pid" 2>/dev/null
STUB

  cat > "$STUB_BIN/caffeinate" <<'STUB'
#!/bin/bash
target_pid=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-w" ]; then
    target_pid="${2:-}"
    break
  fi
  shift
done
printf '%s -ims -w %s\n' "$0" "$target_pid" > "$PS_COMMANDS_DIR/$$"
printf '%s\n' "$$" >> "$CAFFEINATE_CHILD_PIDS"
trap 'rm -f "$PS_COMMANDS_DIR/$$"; exit 0' TERM INT
while kill -0 "$target_pid" 2>/dev/null; do
  sleep 1
done
rm -f "$PS_COMMANDS_DIR/$$"
STUB

  cat > "$STUB_BIN/osascript" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$OSASCRIPT_LOG"
script=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-e" ]; then
    script="${2:-}"
    break
  fi
  shift
done
operation=""
case "$script" in
  *"closed display mode enabled"*) operation="closed-display-state" ;;
  *"enable closed display mode"*) operation="enable-closed-display" ;;
  *"session is active"*) operation="session-state" ;;
  *"start new session"*) operation="start-session" ;;
  *"end session"*) operation="end-session" ;;
esac
printf '%s\n' "$operation" >> "$OSASCRIPT_OPERATION_LOG"
case ",${OSASCRIPT_HANG_FOR:-}," in
  *,"$operation",*) exec sleep 30 ;;
esac
if [ "${OSASCRIPT_HANG:-0}" = "1" ]; then
  exec sleep 30
fi
if [ "${OSASCRIPT_FAIL:-0}" = "1" ]; then
  printf 'not authorized to send Apple events to Amphetamine\n' >&2
  exit 1
fi
case ",${OSASCRIPT_FAIL_FOR:-}," in
  *,"$operation",*)
    failure_message="${OSASCRIPT_FAILURE_MESSAGE:-}"
    [ -n "$failure_message" ] \
      || failure_message="Amphetamine couldn't understand the message it received from script"
    printf '%s\n' "$failure_message" >&2
    exit 1
    ;;
esac
case "$operation" in
  session-state)
    cat "$AMPHETAMINE_STATE"
    ;;
  closed-display-state)
    cat "$AMPHETAMINE_CLOSED_DISPLAY_STATE"
    ;;
  start-session)
    if [ "${OSASCRIPT_START_NO_SESSION:-0}" != "1" ]; then
      printf 'true\n' > "$AMPHETAMINE_STATE"
    fi
    ;;
  enable-closed-display)
    if [ "${OSASCRIPT_ENABLE_NOOP:-0}" != "1" ]; then
      printf 'true\n' > "$AMPHETAMINE_CLOSED_DISPLAY_STATE"
    fi
    ;;
  end-session)
    printf 'false\n' > "$AMPHETAMINE_STATE"
    printf 'false\n' > "$AMPHETAMINE_CLOSED_DISPLAY_STATE"
    ;;
esac
STUB
  chmod +x "$STUB_BIN"/*

  export HOME="$TEST_HOME"
  export XDG_STATE_HOME="$TEST_DIR/state"
  export DOTFILES_AGENT_PMSET_BIN="$STUB_BIN/pmset"
  export DOTFILES_AGENT_PS_BIN="$STUB_BIN/ps"
  export DOTFILES_AGENT_CAFFEINATE_BIN="$STUB_BIN/caffeinate"
  export DOTFILES_AGENT_OSASCRIPT_BIN="$STUB_BIN/osascript"
  export DOTFILES_AGENT_CLAUDE_PATHS="$CLAUDE_PATH"
  export AMPHETAMINE_APP_PATH="$TEST_DIR/Amphetamine.app"
  export PS_COMMANDS_DIR PS_SNAPSHOT_FILE CAFFEINATE_CHILD_PIDS
  export AMPHETAMINE_STATE AMPHETAMINE_CLOSED_DISPLAY_STATE
  export OSASCRIPT_LOG OSASCRIPT_OPERATION_LOG PMSET_OUTPUT_FILE

  # shellcheck source=../lib/agent-keepawake.sh
  source "$KEEPAWAKE_LIB"
}

teardown() {
  local pid
  if [ -f "$CAFFEINATE_CHILD_PIDS" ]; then
    while IFS= read -r pid; do
      kill "$pid" 2>/dev/null || true
    done < "$CAFFEINATE_CHILD_PIDS"
  fi
  if [ -f "$TARGET_PIDS" ]; then
    while IFS= read -r pid; do
      kill "$pid" 2>/dev/null || true
    done < "$TARGET_PIDS"
  fi
  export HOME="$ORIGINAL_HOME"
  rm -rf "$TEST_DIR"
}

start_tracked_process() {
  local executable="$1" arguments="${2:-}" target_pid
  sleep 600 </dev/null >/dev/null 2>&1 &
  target_pid="$!"
  printf '%s\n' "$target_pid" >> "$TARGET_PIDS"
  printf '%s %s%s\n' "$target_pid" "$executable" "$arguments" >> "$PS_SNAPSHOT_FILE"
  REPLY_TARGET_PID="$target_pid"
}

set_battery_percent() {
  local percent="$1"
  cat > "$PMSET_OUTPUT_FILE" <<EOF
Now drawing from 'Battery Power'
 -InternalBattery-0 (id=1234567)	${percent}%; discharging; 2:00 remaining present: true
EOF
}

manager_state_dir() {
  printf '%s/dotfiles\n' "$XDG_STATE_HOME"
}

write_fake_amphetamine_build() {
  local build="$1"
  cat > "$AMPHETAMINE_APP_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleVersion</key><string>${build}</string></dict></plist>
PLIST
}

osascript_operation_count() {
  awk -v operation="$1" '$0 == operation { count++ } END { print count + 0 }' "$OSASCRIPT_OPERATION_LOG"
}

@test "dotfiles-agent-keepawake exists and passes shell syntax" {
  [ -x "$KEEPAWAKE_BIN" ]
  run bash -n "$KEEPAWAKE_BIN"
  [ "$status" -eq 0 ]
}

@test "manager discovers every Cursor and Claude Code executable PID" {
  start_tracked_process "/Applications/Cursor.app/Contents/MacOS/Cursor"
  cursor_pid="$REPLY_TARGET_PID"
  start_tracked_process "$CLAUDE_PATH" " --resume"
  claude_pid="$REPLY_TARGET_PID"

  run dotfiles_agent_list_tracked_processes
  [ "$status" -eq 0 ]
  [[ "$output" == *"$cursor_pid"$'\t'/Applications/Cursor.app/Contents/MacOS/Cursor* ]]
  [[ "$output" == *"$claude_pid"$'\t'"$CLAUDE_PATH"* ]]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 2 ]
}

@test "manager discovers a PATH-installed Claude Code executable" {
  unset DOTFILES_AGENT_CLAUDE_PATHS
  cat > "$STUB_BIN/claude" <<'STUB'
#!/bin/bash
exit 0
STUB
  chmod +x "$STUB_BIN/claude"
  export PATH="$STUB_BIN:$PATH"

  start_tracked_process "$STUB_BIN/claude" " --resume"
  claude_pid="$REPLY_TARGET_PID"

  run dotfiles_agent_list_tracked_processes
  [ "$status" -eq 0 ]
  [[ "$output" == *"$claude_pid"$'\t'"$STUB_BIN/claude"* ]]
}

@test "battery policy qualifies at 20 percent and stops below it" {
  set_battery_percent 20
  run dotfiles_agent_power_qualifies
  [ "$status" -eq 0 ]

  set_battery_percent 19
  run dotfiles_agent_power_qualifies
  [ "$status" -ne 0 ]
}

@test "manager owns one caffeinate child per Cursor and Claude Code process" {
  start_tracked_process "/Applications/Cursor.app/Contents/MacOS/Cursor"
  cursor_pid="$REPLY_TARGET_PID"
  start_tracked_process "$CLAUDE_PATH" " --resume"
  claude_pid="$REPLY_TARGET_PID"

  run bash "$KEEPAWAKE_BIN"
  [ "$status" -eq 0 ]

  state_file="$(manager_state_dir)/agent-keepawake-caffeinate.tsv"
  [ "$(wc -l < "$state_file" | tr -d ' ')" -eq 2 ]
  grep -Fq "$cursor_pid" "$state_file"
  grep -Fq "$claude_pid" "$state_file"
  [ -f "$(manager_state_dir)/agent-keepawake-amphetamine-owner" ]
  [ "$(cat "$AMPHETAMINE_STATE")" = "true" ]
  grep -Fq "interval:0" "$OSASCRIPT_LOG"
  grep -Fq "enable closed display mode" "$OSASCRIPT_LOG"
  ! grep -Fq "disable closed display mode" "$OSASCRIPT_LOG"
  [ "$(cat "$AMPHETAMINE_CLOSED_DISPLAY_STATE")" = "true" ]
  grep -Fxq "closed_display=enabled" "$(manager_state_dir)/agent-keepawake-amphetamine-owner"
}

@test "manager releases only its owned protection below the battery threshold" {
  start_tracked_process "/Applications/Cursor.app/Contents/MacOS/Cursor"
  cursor_pid="$REPLY_TARGET_PID"
  start_tracked_process "$CLAUDE_PATH" " --resume"
  claude_pid="$REPLY_TARGET_PID"
  set_battery_percent 20

  run bash "$KEEPAWAKE_BIN"
  [ "$status" -eq 0 ]
  [ -f "$(manager_state_dir)/agent-keepawake-caffeinate.tsv" ]
  [ -f "$(manager_state_dir)/agent-keepawake-amphetamine-owner" ]

  set_battery_percent 19
  run bash "$KEEPAWAKE_BIN"
  [ "$status" -eq 0 ]
  [ ! -f "$(manager_state_dir)/agent-keepawake-caffeinate.tsv" ]
  [ ! -f "$(manager_state_dir)/agent-keepawake-amphetamine-owner" ]
  [ "$(cat "$AMPHETAMINE_STATE")" = "false" ]
  grep -Fq "end session" "$OSASCRIPT_LOG"
  grep -Fq "$cursor_pid" "$PS_SNAPSHOT_FILE"
  grep -Fq "$claude_pid" "$PS_SNAPSHOT_FILE"
}

@test "manager releases its own children as soon as the tracked process set is empty" {
  start_tracked_process "/Applications/Cursor.app/Contents/MacOS/Cursor"

  run bash "$KEEPAWAKE_BIN"
  [ "$status" -eq 0 ]
  [ -f "$(manager_state_dir)/agent-keepawake-caffeinate.tsv" ]
  [ -f "$(manager_state_dir)/agent-keepawake-amphetamine-owner" ]

  : > "$PS_SNAPSHOT_FILE"
  run bash "$KEEPAWAKE_BIN"
  [ "$status" -eq 0 ]
  [ ! -f "$(manager_state_dir)/agent-keepawake-caffeinate.tsv" ]
  [ ! -f "$(manager_state_dir)/agent-keepawake-amphetamine-owner" ]
  [ "$(cat "$AMPHETAMINE_STATE")" = "false" ]
}

@test "manager leaves a pre-existing user Amphetamine session untouched" {
  start_tracked_process "/Applications/Cursor.app/Contents/MacOS/Cursor"
  printf 'true\n' > "$AMPHETAMINE_STATE"

  run bash "$KEEPAWAKE_BIN"
  [ "$status" -eq 0 ]
  [ ! -f "$(manager_state_dir)/agent-keepawake-amphetamine-owner" ]
  ! grep -Fq "start new session" "$OSASCRIPT_LOG"

  : > "$PS_SNAPSHOT_FILE"
  run bash "$KEEPAWAKE_BIN"
  [ "$status" -eq 0 ]
  [ "$(cat "$AMPHETAMINE_STATE")" = "true" ]
  ! grep -Fq "end session" "$OSASCRIPT_LOG"
}

@test "Automation denial keeps caffeinate protection and records lid-close degradation" {
  start_tracked_process "/Applications/Cursor.app/Contents/MacOS/Cursor"
  export OSASCRIPT_FAIL=1

  run bash "$KEEPAWAKE_BIN"
  [ "$status" -eq 0 ]
  [ -f "$(manager_state_dir)/agent-keepawake-caffeinate.tsv" ]
  [ -s "$(manager_state_dir)/agent-keepawake-amphetamine-error" ]
  grep -Fq "not authorized" "$(manager_state_dir)/agent-keepawake-amphetamine-error"
  [ ! -f "$(manager_state_dir)/agent-keepawake-amphetamine-owner" ]
}

@test "Automation timeout keeps caffeinate protection and releases the manager lock" {
  start_tracked_process "/Applications/Cursor.app/Contents/MacOS/Cursor"
  export OSASCRIPT_HANG=1
  export DOTFILES_AGENT_OSASCRIPT_TIMEOUT_SECONDS=1
  SECONDS=0

  run bash "$KEEPAWAKE_BIN"
  elapsed="$SECONDS"

  [ "$status" -eq 0 ]
  [ "$elapsed" -lt 5 ]
  [ -f "$(manager_state_dir)/agent-keepawake-caffeinate.tsv" ]
  grep -Fq "timed out after 1 seconds" "$(manager_state_dir)/agent-keepawake-amphetamine-error"
  [ ! -d "$(manager_state_dir)/agent-keepawake.lock" ]
}

@test "protocol rejection of the session-state query is shown once and quarantined" {
  start_tracked_process "/Applications/Cursor.app/Contents/MacOS/Cursor"
  export OSASCRIPT_FAIL_FOR="session-state"

  run bash "$KEEPAWAKE_BIN"
  [ "$status" -eq 0 ]
  [ -f "$(manager_state_dir)/agent-keepawake-caffeinate.tsv" ]
  grep -Fq "session-state: Amphetamine couldn't understand the message" \
    "$(manager_state_dir)/agent-keepawake-amphetamine-error"
  [ "$(osascript_operation_count session-state)" -eq 1 ]

  run bash "$KEEPAWAKE_BIN"
  [ "$status" -eq 0 ]
  [ "$(osascript_operation_count session-state)" -eq 1 ]
}

@test "protocol rejection of session start is not retried every manager pass" {
  start_tracked_process "/Applications/Cursor.app/Contents/MacOS/Cursor"
  export OSASCRIPT_FAIL_FOR="start-session"

  run bash "$KEEPAWAKE_BIN"
  [ "$status" -eq 0 ]
  [ ! -f "$(manager_state_dir)/agent-keepawake-amphetamine-owner" ]
  [ "$(osascript_operation_count start-session)" -eq 1 ]

  run bash "$KEEPAWAKE_BIN"
  [ "$status" -eq 0 ]
  [ "$(osascript_operation_count start-session)" -eq 1 ]
}

@test "closed-display state rejection rolls back the new manager session" {
  start_tracked_process "/Applications/Cursor.app/Contents/MacOS/Cursor"
  export OSASCRIPT_FAIL_FOR="closed-display-state"

  run bash "$KEEPAWAKE_BIN"
  [ "$status" -eq 0 ]
  [ "$(cat "$AMPHETAMINE_STATE")" = "false" ]
  [ ! -f "$(manager_state_dir)/agent-keepawake-amphetamine-owner" ]
  [ "$(osascript_operation_count end-session)" -eq 1 ]

  run bash "$KEEPAWAKE_BIN"
  [ "$status" -eq 0 ]
  [ "$(osascript_operation_count start-session)" -eq 1 ]
}

@test "closed-display enable rejection rolls back the new manager session" {
  start_tracked_process "/Applications/Cursor.app/Contents/MacOS/Cursor"
  export OSASCRIPT_FAIL_FOR="enable-closed-display"

  run bash "$KEEPAWAKE_BIN"
  [ "$status" -eq 0 ]
  [ "$(cat "$AMPHETAMINE_STATE")" = "false" ]
  [ ! -f "$(manager_state_dir)/agent-keepawake-amphetamine-owner" ]
  grep -Fq "enable-closed-display: Amphetamine couldn't understand the message" \
    "$(manager_state_dir)/agent-keepawake-amphetamine-error"

  run bash "$KEEPAWAKE_BIN"
  [ "$status" -eq 0 ]
  [ "$(osascript_operation_count enable-closed-display)" -eq 1 ]
}

@test "failed rollback retains pending ownership until Amphetamine recovers" {
  start_tracked_process "/Applications/Cursor.app/Contents/MacOS/Cursor"
  export OSASCRIPT_FAIL_FOR="enable-closed-display,end-session"

  run bash "$KEEPAWAKE_BIN"
  [ "$status" -eq 0 ]
  [ "$(cat "$AMPHETAMINE_STATE")" = "true" ]
  [ -f "$(manager_state_dir)/agent-keepawake-amphetamine-owner" ]
  grep -Fxq "closed_display=pending" "$(manager_state_dir)/agent-keepawake-amphetamine-owner"
  [ "$(osascript_operation_count enable-closed-display)" -eq 1 ]
  [ "$(osascript_operation_count end-session)" -eq 1 ]

  run bash "$KEEPAWAKE_BIN"
  [ "$status" -eq 0 ]
  [ "$(osascript_operation_count enable-closed-display)" -eq 1 ]
  [ "$(osascript_operation_count end-session)" -eq 1 ]

  : > "$PS_SNAPSHOT_FILE"
  unset OSASCRIPT_FAIL_FOR
  write_fake_amphetamine_build 2
  run bash "$KEEPAWAKE_BIN"
  [ "$status" -eq 0 ]
  [ "$(cat "$AMPHETAMINE_STATE")" = "false" ]
  [ ! -f "$(manager_state_dir)/agent-keepawake-amphetamine-owner" ]
}

@test "a no-op closed-display enable is rolled back and reported" {
  start_tracked_process "/Applications/Cursor.app/Contents/MacOS/Cursor"
  export OSASCRIPT_ENABLE_NOOP=1

  run bash "$KEEPAWAKE_BIN"
  [ "$status" -eq 0 ]
  [ "$(cat "$AMPHETAMINE_STATE")" = "false" ]
  [ ! -f "$(manager_state_dir)/agent-keepawake-amphetamine-owner" ]
  grep -Fq "Amphetamine did not enable closed-display mode" \
    "$(manager_state_dir)/agent-keepawake-amphetamine-error"
}

@test "end-session rejection retains ownership and is not retried every pass" {
  start_tracked_process "/Applications/Cursor.app/Contents/MacOS/Cursor"
  run bash "$KEEPAWAKE_BIN"
  [ "$status" -eq 0 ]
  [ -f "$(manager_state_dir)/agent-keepawake-amphetamine-owner" ]

  : > "$PS_SNAPSHOT_FILE"
  export OSASCRIPT_FAIL_FOR="end-session"
  run bash "$KEEPAWAKE_BIN"
  [ "$status" -eq 0 ]
  [ -f "$(manager_state_dir)/agent-keepawake-amphetamine-owner" ]
  [ "$(osascript_operation_count end-session)" -eq 1 ]

  run bash "$KEEPAWAKE_BIN"
  [ "$status" -eq 0 ]
  [ "$(osascript_operation_count end-session)" -eq 1 ]
}

@test "a transient Amphetamine timeout waits for the bounded retry window" {
  start_tracked_process "/Applications/Cursor.app/Contents/MacOS/Cursor"
  export DOTFILES_AGENT_OSASCRIPT_TIMEOUT_SECONDS=1
  export DOTFILES_AGENT_AMPHETAMINE_RETRY_SECONDS=10
  export DOTFILES_AGENT_KEEPAWAKE_NOW_EPOCH=100
  export OSASCRIPT_HANG_FOR="start-session"

  run bash "$KEEPAWAKE_BIN"
  [ "$status" -eq 0 ]
  [ "$(osascript_operation_count start-session)" -eq 1 ]

  unset OSASCRIPT_HANG_FOR
  export DOTFILES_AGENT_KEEPAWAKE_NOW_EPOCH=109
  run bash "$KEEPAWAKE_BIN"
  [ "$status" -eq 0 ]
  [ "$(osascript_operation_count start-session)" -eq 1 ]

  export DOTFILES_AGENT_KEEPAWAKE_NOW_EPOCH=110
  run bash "$KEEPAWAKE_BIN"
  [ "$status" -eq 0 ]
  [ "$(osascript_operation_count start-session)" -eq 2 ]
  [ -f "$(manager_state_dir)/agent-keepawake-amphetamine-owner" ]
}

@test "an Amphetamine app update retries a quarantined protocol command" {
  start_tracked_process "/Applications/Cursor.app/Contents/MacOS/Cursor"
  export OSASCRIPT_FAIL_FOR="start-session"

  run bash "$KEEPAWAKE_BIN"
  [ "$status" -eq 0 ]
  [ "$(osascript_operation_count start-session)" -eq 1 ]

  unset OSASCRIPT_FAIL_FOR
  write_fake_amphetamine_build 2
  run bash "$KEEPAWAKE_BIN"
  [ "$status" -eq 0 ]
  [ "$(osascript_operation_count start-session)" -eq 2 ]
  [ -f "$(manager_state_dir)/agent-keepawake-amphetamine-owner" ]
}

@test "dry-run reports the process-scoped decision without creating state" {
  start_tracked_process "/Applications/Cursor.app/Contents/MacOS/Cursor"

  run bash "$KEEPAWAKE_BIN" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would protect 1 tracked process"* ]]
  [[ "$output" == *"manager-owned caffeinate -ims -w"* ]]
  [ ! -e "$(manager_state_dir)/agent-keepawake-caffeinate.tsv" ]
  [ ! -e "$(manager_state_dir)/agent-keepawake-amphetamine-owner" ]
}

@test "dry-run reports cleanup when no Cursor or Claude Code process exists" {
  run bash "$KEEPAWAKE_BIN" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would release manager-owned sleep protection"* ]]
}

@test "library defaults to battery protection at the 20 percent threshold" {
  unset DOTFILES_AGENT_KEEPAWAKE_BATTERY
  unset DOTFILES_AGENT_KEEPAWAKE_BATTERY_MIN_PERCENT
  run dotfiles_agent_battery_keepawake_enabled
  [ "$status" -eq 0 ]
  run dotfiles_agent_battery_min_percent
  [ "$status" -eq 0 ]
  [ "$output" = "20" ]
}

@test "agent-keepawake plist preserves managed children between five-second runs" {
  [ -f "$PLIST" ]
  grep -q 'com.dotfiles.agent-keepawake' "$PLIST"
  grep -q 'dotfiles-agent-keepawake' "$PLIST"
  grep -A1 '<key>StartInterval</key>' "$PLIST" | grep -q '<integer>5</integer>'
  grep -A1 '<key>AbandonProcessGroup</key>' "$PLIST" | grep -q '<true/>'
  grep -q 'DOTFILES_AGENT_KEEPAWAKE_BATTERY' "$PLIST"
  grep -q 'DOTFILES_AGENT_KEEPAWAKE_BATTERY_MIN_PERCENT' "$PLIST"
  grep -q '<string>20</string>' "$PLIST"
}

@test "LaunchAgent deployment gate accepts an installed Claude Code executable" {
  local launchagent_setup="$BATS_TEST_DIRNAME/../.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
  awk '/agent-keepawake\)/,/;;/' "$launchagent_setup" | grep -q '\.local/bin/claude'
  awk '/agent-keepawake\)/,/;;/' "$launchagent_setup" | grep -q 'command -v claude'
}

@test "managed Amphetamine preferences disable generic triggers" {
  local preferences="$BATS_TEST_DIRNAME/../data/amphetamine-prefs.json"
  [ "$(jq -r '."Enable Triggers"' "$preferences")" = "0" ]
  [ "$(jq -r '."Trigger Data" | length' "$preferences")" = "0" ]
}

@test "dotfiles-agent-keepawake preserves display sleep and documents true sleep" {
  grep -q 'caffeinate -ims' "$KEEPAWAKE_BIN"
  ! grep -q 'caffeinate -dims' "$KEEPAWAKE_BIN"
  grep -q 'truly asleep' "$KEEPAWAKE_BIN"
}

@test "cascade-caffeinate delegates to dotfiles-agent-keepawake" {
  grep -q 'dotfiles-agent-keepawake' "$BATS_TEST_DIRNAME/../bin/cascade-caffeinate"
}
