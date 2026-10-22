#!/usr/bin/env bats
# Tests for bin/dotfiles-resilience-setup

load test_helper

@test "resilience-setup: script exists and is executable" {
  [ -x "$BATS_TEST_DIRNAME/../bin/dotfiles-resilience-setup" ]
}

@test "resilience-setup: --help prints usage" {
  run bash "$BATS_TEST_DIRNAME/../bin/dotfiles-resilience-setup" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"resilience"* ]] || [[ "$output" == *"sleep"* ]] || [[ "$output" == *"tmux"* ]]
}

# The lid-close report must be read-only, so these stubs log any call to a
# tool that could change power settings or drive another app.
setup_lid_close_stubs() {
  STUB_BIN="$TEST_DIR/bin"
  CALL_LOG="$TEST_DIR/calls.log"
  PMSET_OUTPUT_FILE="$TEST_DIR/pmset-g"
  mkdir -p "$STUB_BIN" "$HOME/Library/LaunchAgents"
  : > "$CALL_LOG"
  printf 'System-wide power settings:\nCurrently in use:\n sleep                1\n' > "$PMSET_OUTPUT_FILE"
  cat > "$STUB_BIN/pmset" <<'STUB'
#!/bin/bash
printf 'pmset %s\n' "$*" >> "$CALL_LOG"
cat "$PMSET_OUTPUT_FILE"
STUB
  for tool in sudo osascript open brew mas; do
    printf '#!/bin/bash\nprintf "%s %%s\\n" "$*" >> "$CALL_LOG"\n' "$tool" > "$STUB_BIN/$tool"
  done
  chmod +x "$STUB_BIN"/*
  export PATH="$STUB_BIN:$PATH" CALL_LOG PMSET_OUTPUT_FILE
  export DOTFILES_AGENT_PMSET_BIN="$STUB_BIN/pmset"
  export XDG_STATE_HOME="$TEST_DIR/state"
  export AMPHETAMINE_APP_PATH="$TEST_DIR/no-amphetamine.app"
}

write_launchagent() {
  local label="$1" extra="$2"
  cat > "$HOME/Library/LaunchAgents/$label.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>$label</string>$extra</dict></plist>
PLIST
}

@test "resilience-setup: --help names the lid-close report" {
  run bash "$BATS_TEST_DIRNAME/../bin/dotfiles-resilience-setup" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--lid-close"* ]]
}

@test "resilience-setup: --lid-close says lid close sleeps the Mac and names both fixes" {
  setup_lid_close_stubs
  run bash "$BATS_TEST_DIRNAME/../bin/dotfiles-resilience-setup" --lid-close
  [ "$status" -eq 0 ]
  [[ "$output" == *"Lid close will sleep this Mac. pmset sleep 0 does not stop lid-close sleep."* ]]
  [[ "$output" == *"Fix 1, on the charger: start an Amphetamine session"* ]]
  [[ "$output" == *"Fix 2, no app: sudo pmset -a disablesleep 1"* ]]
  [[ "$output" == *"drains the battery and heats a closed bag"* ]]
  [[ "$output" == *"Install Amphetamine"* ]]
  # Read-only: only `pmset -g` ran; no sudo, AppleScript, installer, or open.
  [ "$(cat "$CALL_LOG")" = "pmset -g" ]
}

@test "resilience-setup: --lid-close reports pmset disablesleep and its cost" {
  setup_lid_close_stubs
  printf 'System-wide power settings:\n SleepDisabled\t\t1\nCurrently in use:\n sleep 1\n' > "$PMSET_OUTPUT_FILE"
  run bash "$BATS_TEST_DIRNAME/../bin/dotfiles-resilience-setup" --lid-close
  [ "$status" -eq 0 ]
  [[ "$output" == *"Lid close will not sleep this Mac: pmset disablesleep is on"* ]]
  [[ "$output" == *"also never sleeps on battery"* ]]
  [[ "$output" == *"undo: sudo pmset -a disablesleep 0"* ]]
  [ "$(cat "$CALL_LOG")" = "pmset -g" ]
}

@test "resilience-setup: --lid-close reports a manager-held Amphetamine session" {
  setup_lid_close_stubs
  mkdir -p "$XDG_STATE_HOME/dotfiles" "$AMPHETAMINE_APP_PATH"
  printf 'owner=dotfiles-agent-keepawake\nclosed_display=enabled\n' \
    > "$XDG_STATE_HOME/dotfiles/agent-keepawake-amphetamine-owner"
  run bash "$BATS_TEST_DIRNAME/../bin/dotfiles-resilience-setup" --lid-close
  [ "$status" -eq 0 ]
  [[ "$output" == *"Lid close will not sleep this Mac now"* ]]
  [[ "$output" == *"(CLI and desktop app) are covered"* ]]
  [[ "$output" != *"Lid close will sleep this Mac."* ]]
}

@test "resilience-setup: --lid-close lists enabled scheduled LaunchAgents only" {
  setup_lid_close_stubs
  write_launchagent com.example.morning-plan \
    '<key>StartCalendarInterval</key><dict><key>Hour</key><integer>6</integer></dict>'
  write_launchagent com.example.nightly-log \
    '<key>StartCalendarInterval</key><array><dict><key>Hour</key><integer>23</integer><key>Minute</key><integer>30</integer></dict></array>'
  write_launchagent com.example.disabled-job \
    '<key>Disabled</key><true/><key>StartCalendarInterval</key><dict><key>Hour</key><integer>2</integer></dict>'
  write_launchagent com.example.interval-job \
    '<key>StartInterval</key><integer>300</integer>'

  run bash "$BATS_TEST_DIRNAME/../bin/dotfiles-resilience-setup" --lid-close
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 scheduled LaunchAgent(s) run late, at the next wake"* ]]
  [[ "$output" == *"com.example.morning-plan"* ]]
  [[ "$output" == *"com.example.nightly-log"* ]]
  [[ "$output" != *"com.example.disabled-job"* ]]
  [[ "$output" != *"com.example.interval-job"* ]]
}
