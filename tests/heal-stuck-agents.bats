#!/usr/bin/env bats
# Tests for dotfiles-heal-stuck-agents and lib/heal-stuck-agents.sh

HEAL_BIN="$BATS_TEST_DIRNAME/../bin/dotfiles-heal-stuck-agents"
HEAL_LIB="$BATS_TEST_DIRNAME/../lib/heal-stuck-agents.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  mkdir -p "$TEST_HOME/.local/share/dotfiles/logs" "$TEST_HOME/.ssh/sockets" \
    "$TEST_HOME/.local/share/dotfiles/state"
  export HOME="$TEST_HOME"
  export HEAL_SKIP_NETWORK=1
  export HEAL_SKIP_PS=1
  export HEAL_GIT_UPLOAD_PACK_MAX_AGE_SEC=60
  export HEAL_STALE_SHELL_MAX_AGE_SEC=60
  export HEAL_RUNAWAY_AGENT_MAX_CPU_PERCENT=90
  export HEAL_RUNAWAY_AGENT_MIN_AGE_SEC=60
  # shellcheck source=../lib/heal-stuck-agents.sh
  source "$HEAL_LIB"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "heal-stuck-agents exists and is executable" {
  [ -x "$HEAL_BIN" ]
}

@test "heal-stuck-agents supports --dry-run and --fix" {
  grep -q '\-\-dry-run' "$HEAL_BIN"
  grep -q '\-\-fix' "$HEAL_BIN"
  grep -q '\-\-quiet' "$HEAL_BIN"
}

@test "heal-stuck-agents documents Reload Window limit" {
  grep -q 'Reload Window' "$HEAL_BIN"
}

@test "lib: mux master is excluded from hung git session detection" {
  run dotfiles_heal_is_hung_git_session "ssh: git@ghe.example.com [mux]" 9999
  [ "$status" -eq 1 ]
}

@test "lib: young git-upload-pack is not hung" {
  run dotfiles_heal_is_hung_git_session "git-upload-pack git@ghe.example.com" 30
  [ "$status" -eq 1 ]
}

@test "lib: old git-upload-pack is hung" {
  run dotfiles_heal_is_hung_git_session "git-upload-pack git@ghe.example.com" 120
  [ "$status" -eq 0 ]
}

@test "lib: old ssh to configured GHE host is hung" {
  export DOTFILES_GHE_SSH_HOST=ghe.example.com
  run dotfiles_heal_is_hung_git_session "ssh git@ghe.example.com git-upload-pack" 120
  [ "$status" -eq 0 ]
}

@test "lib: etime parser converts hh:mm:ss to seconds" {
  run dotfiles_heal_etime_to_seconds "03:57:51"
  [ "$status" -eq 0 ]
  [ "$output" -eq $((3 * 3600 + 57 * 60 + 51)) ]
}

@test "lib: etime parser converts dd-hh:mm:ss to seconds" {
  run dotfiles_heal_etime_to_seconds "1-02:30:00"
  [ "$status" -eq 0 ]
  [ "$output" -eq $((86400 + 2 * 3600 + 30 * 60)) ]
}

@test "lib: etime parser converts mm:ss to seconds" {
  run dotfiles_heal_etime_to_seconds "05:23"
  [ "$status" -eq 0 ]
  [ "$output" -eq $((5 * 60 + 23)) ]
}

@test "lib: non-numeric age is not a hung git session" {
  run dotfiles_heal_is_hung_git_session "git-upload-pack git@ghe.example.com" "/sbin/launchd"
  [ "$status" -eq 1 ]
}

@test "lib: ps line parser uses etime not command path as age" {
  dotfiles_heal_parse_ps_line "  123 03:57:51 /sbin/launchd"
  [ "$REPLY_PID" = "123" ]
  [ "$REPLY_AGE" -eq $((3 * 3600 + 57 * 60 + 51)) ]
  [ "$REPLY_ARGS" = "/sbin/launchd" ]
}

@test "lib: CPU threshold allows 90 percent and rejects higher usage" {
  run dotfiles_heal_cpu_exceeds_limit "90.0" 90
  [ "$status" -eq 1 ]

  run dotfiles_heal_cpu_exceeds_limit "90.1" 90
  [ "$status" -eq 0 ]
}

@test "lib: old high-CPU Cursor ignore discovery is runaway" {
  dotfiles_heal_in_cursor_process_tree() { [ "$1" = "123" ]; }
  run dotfiles_heal_is_runaway_agent_helper \
    "/Applications/Cursor.app/ripgrep/bin/rg --files --hidden --follow --no-config" \
    120 701.2 123
  [ "$status" -eq 0 ]
}

@test "lib: young or non-Cursor high-CPU discovery is preserved" {
  dotfiles_heal_in_cursor_process_tree() { [ "$1" = "123" ]; }
  local args="/Applications/Cursor.app/ripgrep/bin/rg --files --hidden --follow --no-config"

  run dotfiles_heal_is_runaway_agent_helper "$args" 30 701.2 123
  [ "$status" -eq 1 ]

  run dotfiles_heal_is_runaway_agent_helper "$args" 120 701.2 999
  [ "$status" -eq 1 ]
}

@test "lib: user searches and tests are never treated as runaway helpers" {
  dotfiles_heal_in_cursor_process_tree() { return 0; }

  run dotfiles_heal_is_runaway_agent_helper \
    "/Applications/Cursor.app/ripgrep/bin/rg TODO --follow ." 120 701.2 123
  [ "$status" -eq 1 ]

  run dotfiles_heal_is_runaway_agent_helper "npm test" 120 701.2 123
  [ "$status" -eq 1 ]
}

@test "heal-stuck-agents --dry-run exits 0 when healthy" {
  run "$HEAL_BIN" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *hung_git=0* ]]
}

@test "heal-stuck-agents writes to log file" {
  "$HEAL_BIN" --quiet --dry-run
  [ -f "$TEST_HOME/.local/share/dotfiles/logs/heal-stuck-agents.log" ]
  grep -q 'heal-stuck-agents' "$TEST_HOME/.local/share/dotfiles/logs/heal-stuck-agents.log"
}

@test "network-watchdog checks Cursor agent API DNS" {
  WATCHDOG="$BATS_TEST_DIRNAME/../bin/network-watchdog"
  grep -q 'check_cursor_agent_dns' "$WATCHDOG"
  grep -q 'agentn.us.api5.cursor.sh' "$WATCHDOG"
}

@test "ssh config template has ConnectTimeout and optional GHE keepalive" {
  TMPL="$BATS_TEST_DIRNAME/../private_dot_ssh/private_config.tmpl"
  grep -q 'ConnectTimeout 15' "$TMPL"
  grep -q 'ghe_ssh_host' "$TMPL"
  grep -q 'ControlPersist 300' "$TMPL"
}

@test "heal-stuck-agents LaunchAgent exists" {
  PLIST="$BATS_TEST_DIRNAME/../launchagents/com.dotfiles.heal-stuck-agents.plist.tmpl"
  [ -f "$PLIST" ]
  grep -q 'dotfiles-heal-stuck-agents' "$PLIST"
  grep -q '<integer>30</integer>' "$PLIST"
  grep -q '<key>HEAL_SKIP_NETWORK</key>' "$PLIST"
}

@test "dotfiles-doctor runs heal before module checks on --fix" {
  DOCTOR="$BATS_TEST_DIRNAME/../bin/dotfiles-doctor"
  grep -q 'dotfiles-heal-stuck-agents' "$DOCTOR"
  grep -q 'Proactive heal for stuck Cursor agents' "$DOCTOR"
}
