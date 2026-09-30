#!/usr/bin/env bats
# Tests for lib/launchctl-timeout.sh

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR"
  LAUNCHCTL_LOG="$TEST_DIR/launchctl.log"
  LIB="$BATS_TEST_DIRNAME/../lib/launchctl-timeout.sh"
  mkdir -p "$TEST_DIR/bin"
  cat > "$TEST_DIR/bin/launchctl" <<'LAUNCHCTL'
#!/bin/bash
echo "launchctl $*" >> "$LAUNCHCTL_LOG"
case "$1" in
  kickstart)
    if [ "${LAUNCHCTL_HANG:-0}" = "1" ]; then
      sleep 60
    fi
    exit 0
    ;;
esac
exit 0
LAUNCHCTL
  chmod +x "$TEST_DIR/bin/launchctl"
  export PATH="$TEST_DIR/bin:$PATH"
  warn() { echo "WARN: $*"; }
  export -f warn
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "launchagent_program_path reads ProgramArguments" {
  mkdir -p "$TEST_DIR/agents"
  cat > "$TEST_DIR/agents/job.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>ProgramArguments</key><array><string>/opt/bin/foo</string></array>
</dict></plist>
EOF
  source "$LIB"
  run launchagent_program_path "$TEST_DIR/agents/job.plist"
  [ "$status" -eq 0 ]
  [ "$output" = "/opt/bin/foo" ]
}

@test "launchctl_kickstart_with_timeout returns before hang" {
  source "$LIB"
  export LAUNCHCTL_HANG=1
  export LAUNCHCTL_LOG
  run launchctl_kickstart_with_timeout "gui/501/com.example.job" 2
  [ "$status" -eq 124 ]
}
