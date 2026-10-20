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

@test "ssh config template has ConnectTimeout and optional GHE keepalive" {
  TMPL="$BATS_TEST_DIRNAME/../private_dot_ssh/private_config.tmpl"
  grep -q 'ConnectTimeout 15' "$TMPL"
  grep -q 'ghe_ssh_host' "$TMPL"
  grep -q 'ControlPersist 300' "$TMPL"
}

@test "heal-stuck-agents has no LaunchAgent of its own" {
  [ ! -e "$BATS_TEST_DIRNAME/../launchagents/com.dotfiles.heal-stuck-agents.plist.tmpl" ]
}

@test "dotfiles-doctor runs heal before module checks on --fix" {
  DOCTOR="$BATS_TEST_DIRNAME/../bin/dotfiles-doctor"
  grep -q 'dotfiles-heal-stuck-agents' "$DOCTOR"
  grep -q 'Proactive heal for stuck agent git sessions' "$DOCTOR"
}
