#!/usr/bin/env bats
# Hermetic end-to-end tests of bin/dotfiles-install (see hermetic-install.sh).
# Real chezmoi, real lifecycle scripts, real doctor, real verify, real zsh,
# real backup and restore, all inside a scratch HOME. OS-changing tools are
# shims, and sandbox-exec blocks the real ones.
#
# Run: make e2e            (runs only when installer paths changed: make e2e-if-needed)
# Not part of `make test-all`: bats does not descend into tests/e2e/.

setup_file() {
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
  export REPO
  command -v sandbox-exec >/dev/null || skip "needs macOS sandbox-exec"
}

setup() {
  SCRATCH="$(mktemp -d)"
}

teardown() { rm -rf "$SCRATCH"; }

@test "e2e: a fresh install applies, heals, verifies, and leaves a working shell" {
  run "$REPO/tests/e2e/hermetic-install.sh" "$SCRATCH" run --yes --profile core \
    --name "E2E User" --email e2e@example.com --no-agentbrew
  [ "$status" -eq 0 ] || { tail -40 "$SCRATCH/run.log"; return 1; }
  local home="$SCRATCH/home"
  grep -q '^== Done' "$SCRATCH/run.log"
  # Real chezmoi output: the shell config is now the dotfiles one.
  ! grep -q 'e2e original zshrc' "$home/.zshrc"
  git config --file "$home/.gitconfig" --bool dotfiles.agentPolicy | grep -qx false
  # The new shell starts cleanly in the new HOME.
  env -i HOME="$home" PATH="/opt/homebrew/bin:/usr/bin:/bin" TERM=dumb zsh -i -c 'exit 0'
  # Background jobs landed in the scratch HOME, never in the real one.
  ls "$home/Library/LaunchAgents"/com.dotfiles.*.plist >/dev/null
  # Settings changes went to the shim, not to the Mac.
  grep -q '^defaults write' "$SCRATCH/os-calls.log"
  # A backup with the original files exists.
  ls "$home/.local/state/dotfiles/install-backups"/*/files.tar.gz >/dev/null
  # It ends by pointing at the fork-PR path.
  grep -q 'dotfiles contribute' "$SCRATCH/run.log"
}

@test "e2e: a failure after files were written restores the Mac by itself" {
  E2E_BREAK=1 run "$REPO/tests/e2e/hermetic-install.sh" "$SCRATCH" run --yes --profile core \
    --name "E2E User" --email e2e@example.com --no-agentbrew
  [ "$status" -eq 1 ]
  local home="$SCRATCH/home"
  grep -q 'Critical error during chezmoi apply' "$SCRATCH/run.log"
  grep -q 'Restored files, LaunchAgents, chezmoi config, and macOS settings' "$SCRATCH/run.log"
  [ "$(cat "$home/.zshrc")" = "# e2e original zshrc" ]
  [ "$(cat "$home/.gitconfig")" = "$(printf '[user]\n\tname = Original')" ]
  [ ! -e "$home/.config/chezmoi/chezmoi.yaml" ]
  ! ls "$home/Library/LaunchAgents"/com.dotfiles.*.plist >/dev/null 2>&1
}
