#!/usr/bin/env bats
# home/zshrc shell-start sample: one content-free stats line a day.

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export XDG_STATE_HOME="$TEST_DIR/state" DOTFILES_STATS_FILE="$TEST_DIR/stats.jsonl"
  unset DOTFILES_STATS_LOG
  SNIP="$TEST_DIR/snip.zsh"
  {
    echo 'zmodload zsh/datetime; typeset -g _dotfiles_zshrc_t0=$((EPOCHREALTIME - 0.25))'
    echo 'autoload -Uz add-zsh-hook'
    sed -n '/# shell-start-sample:begin/,/# shell-start-sample:end/p' "$BATS_TEST_DIRNAME/../home/zshrc"
    echo 'add-zsh-hook precmd _dotfiles_shell_start_sample'
    echo 'for f in $precmd_functions; do $f; done'
  } > "$SNIP"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "the first prompt logs one shell-start line with the start time in ms" {
  run zsh -f "$SNIP"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.task == "shell-start" and .ok == true and .duration_ms >= 250 and .duration_ms < 5000' "$DOTFILES_STATS_FILE"
  [ "$(jq -r 'keys | join(",")' "$DOTFILES_STATS_FILE")" = "duration_ms,ok,seconds_saved,task,timestamp,units" ]
}

@test "a second shell on the same day logs nothing more" {
  zsh -f "$SNIP"; zsh -f "$SNIP"
  [ "$(wc -l < "$DOTFILES_STATS_FILE" | tr -d ' ')" -eq 1 ]
}

@test "DOTFILES_STATS_LOG=0 logs nothing" {
  DOTFILES_STATS_LOG=0 zsh -f "$SNIP"
  [ ! -e "$DOTFILES_STATS_FILE" ]
}

@test "home/zshrc starts the clock first and registers the hook" {
  head -5 "$BATS_TEST_DIRNAME/../home/zshrc" | grep -q '_dotfiles_zshrc_t0=\$EPOCHREALTIME'
  grep -q '^add-zsh-hook precmd _dotfiles_shell_start_sample$' "$BATS_TEST_DIRNAME/../home/zshrc"
}
