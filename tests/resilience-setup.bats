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
  # launchctl print is read-only; LAUNCHCTL_PRINT_STATUS=1 means "not loaded".
  printf '#!/bin/bash\nexit "${LAUNCHCTL_PRINT_STATUS:-0}"\n' > "$STUB_BIN/launchctl"
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

setup_unattended_wizard() {
  TEST_PYTHON="$(command -v python3)"
  setup_lid_close_stubs
  export DOTFILES_KEEP_AWAKE_TOOLS=false
  export AMPHETAMINE_APP_PATH="$TEST_DIR/amphetamine.app"
  export XDG_CONFIG_HOME="$TEST_HOME/.config" XDG_CACHE_HOME="$TEST_HOME/.cache" XDG_STATE_HOME="$TEST_HOME/.local/state"
  export PATH="$STUB_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
  for tool in tmux chezmoi defaults; do
    printf '#!/bin/sh\nexit 0\n' > "$STUB_BIN/$tool"
  done
  cat > "$STUB_BIN/mas" <<'STUB'
#!/bin/sh
[ "$1" = version ] && { echo test; exit 0; }
printf 'mas %s\n' "$*" >> "$CALL_LOG"
exit 1
STUB
  chmod +x "$STUB_BIN"/*
  cat > "$TEST_DIR/wizard-runner.py" <<'PY'
import os
import pty
import signal
import subprocess
import sys

master = slave = None
if sys.argv[1] == "tty":
    master, slave = pty.openpty()
child = subprocess.Popen(
    ["/bin/bash", sys.argv[2]],
    stdin=slave if slave is not None else subprocess.DEVNULL,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    start_new_session=True,
)
if slave is not None:
    os.close(slave)
try:
    output, _ = child.communicate(timeout=15)
    status = child.returncode
except subprocess.TimeoutExpired:
    try:
        os.killpg(child.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    output, _ = child.communicate()
    status = 124
finally:
    if master is not None:
        os.close(master)
sys.stdout.buffer.write(output)
sys.exit(status)
PY
}

@test "resilience-setup: unattended missing app never installs or opens a store" {
  setup_unattended_wizard
  run "$TEST_PYTHON" "$TEST_DIR/wizard-runner.py" no-tty "$BATS_TEST_DIRNAME/../bin/dotfiles-resilience-setup"
  [ "$status" -eq 0 ]
  local wizard_output="$output"
  run grep -E '^(mas install|brew install|open )' "$CALL_LOG"
  [ "$status" -eq 1 ]
  [[ "$wizard_output" == *"App Store"* ]]
  [[ "$wizard_output" == *"terminal"* ]]
}

@test "resilience-setup: unattended installed app never installs or opens a store" {
  setup_unattended_wizard
  mkdir -p "$AMPHETAMINE_APP_PATH"
  run "$TEST_PYTHON" "$TEST_DIR/wizard-runner.py" no-tty "$BATS_TEST_DIRNAME/../bin/dotfiles-resilience-setup"
  [ "$status" -eq 0 ]
  run grep -E '^(mas install|brew install|open )' "$CALL_LOG"
  [ "$status" -eq 1 ]
}

@test "resilience-setup: unattended missing mas never invokes brew or a store" {
  setup_unattended_wizard
  rm "$STUB_BIN/mas"
  run command -v mas
  [ "$status" -ne 0 ]
  run "$TEST_PYTHON" "$TEST_DIR/wizard-runner.py" no-tty "$BATS_TEST_DIRNAME/../bin/dotfiles-resilience-setup"
  [ "$status" -eq 0 ]
  local wizard_output="$output"
  run grep -E '^(brew install|open )' "$CALL_LOG"
  [ "$status" -eq 1 ]
  [[ "$wizard_output" == *"terminal"* ]]
}

@test "resilience-setup: terminal run retains the App Store install path" {
  setup_unattended_wizard
  run "$TEST_PYTHON" "$TEST_DIR/wizard-runner.py" tty "$BATS_TEST_DIRNAME/../bin/dotfiles-resilience-setup"
  [ "$status" -eq 0 ]
  grep -q '^mas install 937984704$' "$CALL_LOG"
  grep -q '^open macappstore://' "$CALL_LOG"
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

@test "resilience-setup: --lid-close says sessions are NOT covered when agent-keepawake is not loaded" {
  setup_lid_close_stubs
  mkdir -p "$AMPHETAMINE_APP_PATH"
  LAUNCHCTL_PRINT_STATUS=1 run bash "$BATS_TEST_DIRNAME/../bin/dotfiles-resilience-setup" --lid-close
  [ "$status" -eq 0 ]
  [[ "$output" == *"are NOT covered: the agent-keepawake LaunchAgent is not loaded"* ]]
  [[ "$output" != *"(CLI and desktop app) are covered"* ]]
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
