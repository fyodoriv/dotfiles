#!/usr/bin/env bats
# Hard-to-undo dotfiles commands ask first (lib/confirm.sh): a y/N prompt at
# a terminal, or --yes. Without a terminal and without --yes they refuse and
# change nothing, so an agent has to ask the user first. --dry-run and --help
# need no yes. Covers `dotfiles contribute` (a public PR), `dotfiles init`, and
# `dotfiles update`.

load test_helper

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
  TEST_DIR="$(mktemp -d)"
  LOG="$TEST_DIR/calls.log"
  export LOG
  # A copy without .git, so bin/dotfiles skips its update check (no git fetch).
  mkdir -p "$TEST_DIR/repo/bin" "$TEST_DIR/repo/lib" "$TEST_DIR/stubs"
  cp "$REPO_ROOT/bin/dotfiles" "$REPO_ROOT/bin/dotfiles-contribute" "$TEST_DIR/repo/bin/"
  cp "$REPO_ROOT/lib/colors.sh" "$TEST_DIR/repo/lib/"
  [ ! -f "$REPO_ROOT/lib/confirm.sh" ] || cp "$REPO_ROOT/lib/confirm.sh" "$TEST_DIR/repo/lib/"
  for tool in chezmoi agentbrew; do
    printf '#!/bin/bash\necho "%s $*" >> "$LOG"\n' "$tool" > "$TEST_DIR/stubs/$tool"
    chmod +x "$TEST_DIR/stubs/$tool"
  done
  printf '#!/bin/bash\necho "dotfiles-update $*" >> "$LOG"\n' > "$TEST_DIR/repo/bin/dotfiles-update"
  export PATH="$TEST_DIR/stubs:$PATH" DOTFILES_AGENTBREW_BIN="$TEST_DIR/stubs/agentbrew"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "contribute without a terminal and without --yes refuses and opens no PR" {
  run bash "$TEST_DIR/repo/bin/dotfiles" contribute --draft < /dev/null
  [ "$status" -eq 2 ]
  [[ "$output" == *"public pull request"*"--yes"* ]] || { echo "$output"; return 1; }
  [ ! -e "$LOG" ] || { cat "$LOG"; return 1; }
}

@test "contribute --yes opens the PR and passes the other flags through, without --yes" {
  run bash "$TEST_DIR/repo/bin/dotfiles" contribute --yes --draft < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(cat "$LOG")" = "agentbrew contribute --draft" ]
}

@test "contribute --dry-run and --help need no yes" {
  run bash "$TEST_DIR/repo/bin/dotfiles" contribute --dry-run < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(cat "$LOG")" = "agentbrew contribute --dry-run" ]
  run bash "$TEST_DIR/repo/bin/dotfiles-contribute" --help < /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"--yes"* ]]
}

@test "init without a terminal and without --yes refuses and runs no chezmoi" {
  run bash "$TEST_DIR/repo/bin/dotfiles" init < /dev/null
  [ "$status" -eq 2 ]
  [[ "$output" == *"--yes"* ]] || { echo "$output"; return 1; }
  [ ! -e "$LOG" ] || { cat "$LOG"; return 1; }
}

@test "init --yes runs chezmoi init --apply without --yes" {
  run bash "$TEST_DIR/repo/bin/dotfiles" init --yes < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(cat "$LOG")" = "chezmoi init --source $TEST_DIR/repo --apply" ]
}

@test "update without a terminal and without --yes refuses; --dry-run and --yes run it" {
  run bash "$TEST_DIR/repo/bin/dotfiles" update --verbose < /dev/null
  [ "$status" -eq 2 ]
  [ ! -e "$LOG" ] || { cat "$LOG"; return 1; }
  run bash "$TEST_DIR/repo/bin/dotfiles" update --dry-run < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  run bash "$TEST_DIR/repo/bin/dotfiles" update --yes --verbose < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(cat "$LOG")" = "$(printf 'dotfiles-update --dry-run\ndotfiles-update --verbose')" ]
}
