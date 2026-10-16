#!/usr/bin/env bats
# Story e2e: one real install into a scratch HOME (hermetic-install.sh), then
# each user story's real command runs inside the same sandbox
# (hermetic-exec.sh). Every test name starts with its story ID, and
# tests/user-stories.bats fails when a story's Tests line names a test that
# does not exist here.
#
# US01 lives in dotfiles-install-e2e.bats. US07 and US09 use unit bats
# (accepted push back: their commands need GitHub or a local model).
#
# Run: make e2e

setup_file() {
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
  export REPO
  command -v sandbox-exec >/dev/null || skip "needs macOS sandbox-exec"
  # chezmoi resolves /var to /private/var, so use the physical path.
  SCRATCH="$(cd "$BATS_FILE_TMPDIR" && pwd -P)/scratch"
  export SCRATCH
  "$REPO/tests/e2e/hermetic-install.sh" "$SCRATCH" run --yes --profile core \
    --name "E2E User" --email e2e@example.com --no-agentbrew ||
    { tail -40 "$SCRATCH/run.log" >&3; return 1; }
}

# Run a command in the installed scratch HOME, inside the sandbox.
in_home() { "$REPO/tests/e2e/hermetic-exec.sh" "$SCRATCH" "$@"; }

# A git command for fixtures, with no global config and a fixed identity.
fixture_git() {
  GIT_CONFIG_GLOBAL=/dev/null git -c user.name=e2e -c user.email=e2e@example.com \
    -c init.defaultBranch=main "$@"
}

@test "US02 e2e: morning pulls a repo on main and ends ready to code" {
  local apps="$SCRATCH/home/apps"
  fixture_git init -q --bare "$apps/.remote.git"
  fixture_git clone -q "$apps/.remote.git" "$apps/proj" 2>/dev/null
  fixture_git -C "$apps/proj" commit -q --allow-empty -m one
  fixture_git -C "$apps/proj" push -q origin main
  fixture_git clone -q "$apps/.remote.git" "$SCRATCH/other"
  fixture_git -C "$SCRATCH/other" commit -q --allow-empty -m two
  fixture_git -C "$SCRATCH/other" push -q origin main
  run in_home bin/morning
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"✓ proj"* ]]
  [[ "$output" == *"Ready to code"* ]]
  [ "$(fixture_git -C "$apps/proj" log --oneline | wc -l | tr -d ' ')" -eq 2 ]
}

@test "US02 e2e: a repo with no commits and no process list do not stop morning" {
  fixture_git init -q "$SCRATCH/home/apps/empty"
  run in_home bin/morning
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"Ready to code"* ]]
}

@test "US03 e2e: dotfiles add puts a dotfile under management and apply links it" {
  printf 'e2e=1\n' > "$SCRATCH/home/.e2erc"
  run in_home bin/dotfiles add "$SCRATCH/home/.e2erc"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -f "$SCRATCH/home/apps/dotfiles/home/e2erc" ]
  grep -qF 'symlink._e2erc' "$SCRATCH/home/apps/dotfiles/modules/tools/doctor.sh"
  rm "$SCRATCH/home/.e2erc"
  run in_home chezmoi apply --source . "$SCRATCH/home/.e2erc"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -L "$SCRATCH/home/.e2erc" ]
  [ "$(cat "$SCRATCH/home/.e2erc")" = "e2e=1" ]
}

@test "US03 e2e: dotfiles add refuses a file that does not exist" {
  run in_home bin/dotfiles add "$SCRATCH/home/.no-such-file"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "US04 e2e: a personal override reaches the shell without changing the repo" {
  printf 'export E2E_LOCAL=from-override\n' > "$SCRATCH/home/.zshrc.local"
  # Like US01: the sandbox blocks brew, which zshrc runs by absolute path,
  # so the shell starts outside it, still with only the scratch HOME.
  # script(1) gives it a TTY; zshrc stops before the overrides without one.
  run env -i HOME="$SCRATCH/home" PATH="/opt/homebrew/bin:/usr/bin:/bin" TERM=xterm-256color \
    script -q /dev/null zsh -i -c 'print -r -- "v=$E2E_LOCAL"' </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"v=from-override"* ]]
  [ ! -e "$SCRATCH/home/apps/dotfiles/home/zshrc.local" ]
}

@test "US04 e2e: dotfiles profile refuses an unknown profile and keeps the current one" {
  run in_home bin/dotfiles profile bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be 'core' or 'full'"* ]]
  run in_home bin/dotfiles profile
  [[ "$output" == *"Current profile: core"* ]]
}

@test "US05 e2e: doctor --fix restores a deleted managed file" {
  rm -f "$SCRATCH/home/.gitconfig"
  run in_home bin/dotfiles-doctor --fix --module git
  [ -f "$SCRATCH/home/.gitconfig" ] || { echo "$output"; return 1; }
  [[ "$output" == *"fixed"* ]]
}

@test "US05 e2e: doctor without --fix reports the drift and exits non-zero" {
  rm -f "$SCRATCH/home/.gitconfig"
  run in_home bin/dotfiles-doctor --module git
  [ "$status" -ne 0 ]
  [[ "$output" == *"✗"*".gitconfig"* ]]
  [ ! -e "$SCRATCH/home/.gitconfig" ]
  in_home bin/dotfiles-doctor --fix --module git >/dev/null 2>&1 || true
}

@test "US06 e2e: git-safe blocks reset --hard in a multi-agent repo" {
  local repo="$SCRATCH/home/apps/shared"
  fixture_git init -q "$repo" && mkdir -p "$repo/.worktrees"
  run in_home bash -c "cd '$repo' && git-safe reset --hard"
  [ "$status" -eq 1 ]
  [[ "$output" == *"blocked destructive command"* ]]
}

@test "US06 e2e: git-safe lets a read-only command through" {
  local repo="$SCRATCH/home/apps/shared2"
  fixture_git init -q "$repo" && mkdir -p "$repo/.worktrees"
  run in_home bash -c "cd '$repo' && git-safe status --short"
  [ "$status" -eq 0 ]
}

@test "US08 e2e: dotfiles stats counts the runs that happened" {
  run in_home bin/dotfiles stats
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total runs:"* ]]
  [[ "$output" == *"doctor"* ]]
}

@test "US08 e2e: dotfiles stats with no history says so instead of failing" {
  run in_home env DOTFILES_STATS_FILE="$SCRATCH/none.jsonl" bin/dotfiles stats
  [ "$status" -eq 0 ]
  [[ "$output" == *"No runs recorded yet"* ]]
}

@test "US10 e2e: an overlay module's check runs in the doctor" {
  local overlay="$SCRATCH/home/apps/dotfiles-acme"
  mkdir -p "$overlay/modules/acme"
  printf '#!/bin/bash\ncheck "acme.marker" "acme overlay marker exists" "test -f \\"$HOME/.acme-marker\\""\n' \
    > "$overlay/modules/acme/doctor.sh"
  touch "$SCRATCH/home/.acme-marker"
  run in_home env EXTRA_OVERLAY_ROOT="$overlay" bin/dotfiles-doctor --module acme
  [[ "$output" == *"✓ acme overlay marker exists"* ]] || { echo "$output"; return 1; }
}

@test "US10 e2e: two overlay roots at once are refused" {
  local overlay="$SCRATCH/home/apps/dotfiles-acme"
  run in_home env EXTRA_OVERLAY_ROOT="$overlay:$overlay" bin/dotfiles-doctor --module acme
  [ "$status" -eq 1 ]
  [[ "$output" == *"One overlay at a time"* ]]
}
