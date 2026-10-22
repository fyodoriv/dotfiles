#!/usr/bin/env bats
# Lines that installers append to ~/.zshrc (a symlink to the tracked
# home/zshrc) must move to ~/.zshrc.local and never reach the public repo.

load test_helper

REPO_ROOT="$BATS_TEST_DIRNAME/.."

setup() {
  # The global core.hooksPath would run the live hook, not the copy under test.
  export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=.git/hooks
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME" "$TEST_DIR/fakebin"
  git config --global user.email "test@test.com"
  git config --global user.name "Test"
  export DOTFILES_STATS_FILE="$TEST_DIR/stats.jsonl"

  # chezmoi must never touch the scratch HOME from these tests.
  printf '#!/bin/bash\nexit 0\n' > "$TEST_DIR/fakebin/chezmoi"
  chmod +x "$TEST_DIR/fakebin/chezmoi"
  export PATH="$TEST_DIR/fakebin:$PATH"

  REPO="$TEST_DIR/dotfiles"
  git init --bare --quiet "$TEST_DIR/remote.git"
  git init --quiet "$REPO"
  mkdir -p "$REPO/bin" "$REPO/lib" "$REPO/home"
  cp "$REPO_ROOT/bin/dotfiles-sync" "$REPO/bin/"
  for f in colors stats errors-log lock self-reload push-error-classify agentbrew-locate zshrc-appends apply-state; do
    cp "$REPO_ROOT/lib/$f.sh" "$REPO/lib/"
  done
  printf '# zshrc\n[ -f ~/.zshrc.local ] && source ~/.zshrc.local\n' > "$REPO/home/zshrc"
  git -C "$REPO" add -A
  git -C "$REPO" commit --no-verify -m "chore: initial" --quiet
  git -C "$REPO" remote add origin "$TEST_DIR/remote.git"
  git -C "$REPO" push --quiet -u origin "$(git -C "$REPO" branch --show-current)" 2>/dev/null
  git -C "$REPO" remote set-head origin "$(git -C "$REPO" branch --show-current)"
  ln -s "$REPO/home/zshrc" "$HOME/.zshrc"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "dotfiles-sync moves an installer append from home/zshrc to ~/.zshrc.local" {
  echo 'export X=$HOME/bin' >> "$HOME/.zshrc"
  before="$(git -C "$REPO" rev-parse HEAD)"

  run "$REPO/bin/dotfiles-sync"
  [ "$status" -eq 0 ]

  [ "$(git -C "$REPO" rev-parse HEAD)" = "$before" ]
  [ -z "$(git -C "$REPO" status --porcelain -- home/zshrc)" ]
  grep -qxF 'export X=$HOME/bin' "$HOME/.zshrc.local"
  [ -L "$HOME/.zshrc" ]
  [[ "$output" == *"Moved 1 line"* ]]
}

@test "dotfiles-sync --dry-run reports the append but moves nothing" {
  echo 'export X=$HOME/bin' >> "$HOME/.zshrc"
  run "$REPO/bin/dotfiles-sync" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Would move 1 line"* ]]
  [ ! -e "$HOME/.zshrc.local" ]
  grep -qxF 'export X=$HOME/bin' "$REPO/home/zshrc"
}

@test "an edit inside home/zshrc is not a pure append and stays in place" {
  printf '# edited\n[ -f ~/.zshrc.local ] && source ~/.zshrc.local\nalias y=1\n' > "$REPO/home/zshrc"
  source "$REPO/lib/zshrc-appends.sh"
  run zshrc_move_appends "$REPO" "$HOME/.zshrc.local"
  [ "$status" -ne 0 ]
  [ ! -e "$HOME/.zshrc.local" ]
  grep -qxF 'alias y=1' "$REPO/home/zshrc"
}

@test "zshrc_move_appends keeps lines that are already in ~/.zshrc.local" {
  echo 'alias keep=1' > "$HOME/.zshrc.local"
  printf 'export A=1\nexport B=2\n' >> "$REPO/home/zshrc"
  source "$REPO/lib/zshrc-appends.sh"
  run zshrc_move_appends "$REPO" "$HOME/.zshrc.local"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
  grep -qxF 'alias keep=1' "$HOME/.zshrc.local"
  grep -qxF 'export B=2' "$HOME/.zshrc.local"
  cmp -s "$REPO/home/zshrc" <(git -C "$REPO" show HEAD:home/zshrc)
}

@test "pre-commit blocks a staged home/ line with a /Users/<name> path" {
  touch "$REPO/bin/dotfiles-doctor"
  cp "$REPO_ROOT/git-hooks/pre-commit" "$REPO/.git/hooks/pre-commit"
  chmod +x "$REPO/.git/hooks/pre-commit"
  echo 'export PATH=/Users/alice/.opencode/bin:$PATH' >> "$REPO/home/zshrc"
  git -C "$REPO" add home/zshrc
  run git -C "$REPO" commit -m "chore: add path"
  [ "$status" -ne 0 ]
  [[ "$output" == *"home path"* ]]
  [[ "$output" == *"home/zshrc"* ]]
}

@test "pre-commit allows a home/ line that uses \$HOME" {
  touch "$REPO/bin/dotfiles-doctor"
  cp "$REPO_ROOT/git-hooks/pre-commit" "$REPO/.git/hooks/pre-commit"
  chmod +x "$REPO/.git/hooks/pre-commit"
  echo 'export PATH=$HOME/.opencode/bin:$PATH' >> "$REPO/home/zshrc"
  git -C "$REPO" add home/zshrc
  run git -C "$REPO" commit -m "chore: add path"
  [ "$status" -eq 0 ]
}

@test "shell doctor flags lines appended to home/zshrc" {
  grep -q 'shell.zshrc_no_appends' "$REPO_ROOT/modules/shell/doctor.sh"
  grep -q 'zshrc_move_appends' "$REPO_ROOT/modules/shell/doctor.sh"
}
