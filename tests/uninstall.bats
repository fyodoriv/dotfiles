#!/usr/bin/env bats
# Tests for dotfiles-uninstall — clean removal of dotfiles

UNINSTALL_CMD="$BATS_TEST_DIRNAME/../bin/dotfiles-uninstall"
REAL_DOTFILES="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  STUB_DIR="$TEST_DIR/stubs"
  mkdir -p "$TEST_HOME/Library/LaunchAgents" "$STUB_DIR"

  # Stub chezmoi to output symlink targets relative to HOME
  cat > "$STUB_DIR/chezmoi" << 'STUB'
#!/bin/bash
# Output fake managed paths (relative to HOME)
echo ".zshrc"
echo ".zshenv"
echo ".gitconfig"
STUB
  chmod +x "$STUB_DIR/chezmoi"

  # Stub launchctl to record calls
  cat > "$STUB_DIR/launchctl" << STUB
#!/bin/bash
echo "launchctl \$*" >> "$TEST_DIR/launchctl.log"
STUB
  chmod +x "$STUB_DIR/launchctl"

  export PATH="$STUB_DIR:$PATH"
  export ORIG_HOME="$HOME"
  export HOME="$TEST_HOME"
}

teardown() {
  export HOME="$ORIG_HOME"
  rm -rf "$TEST_DIR"
}

# ── Static analysis ──

@test "dotfiles-uninstall exists and is executable" {
  [ -x "$UNINSTALL_CMD" ]
}

@test "dotfiles-uninstall has correct shebang" {
  head -1 "$UNINSTALL_CMD" | grep -q '#!/bin/bash'
}

@test "dotfiles-uninstall uses strict mode" {
  grep -q 'set -euo pipefail' "$UNINSTALL_CMD"
}

@test "--help shows usage and exits 0" {
  run bash "$UNINSTALL_CMD" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"uninstall"* ]]
}

@test "script references DRY_RUN and --dry-run flag" {
  grep -q 'DRY_RUN' "$UNINSTALL_CMD"
  grep -q '\-\-dry-run' "$UNINSTALL_CMD"
}

@test "script references preserved local config files" {
  grep -q '.zshrc.local' "$UNINSTALL_CMD"
  grep -q '.gitconfig.local' "$UNINSTALL_CMD"
  grep -q '.zshenv.secrets' "$UNINSTALL_CMD"
}

@test "script only targets symlinks pointing to dotfiles repo" {
  grep -q 'DOTFILES_DIR' "$UNINSTALL_CMD"
  grep -q 'apps/dotfiles' "$UNINSTALL_CMD"
}

# ── Functional: dry-run mode ──

@test "dry-run lists actions without removing symlinks" {
  # Create symlinks pointing into the dotfiles repo
  ln -s "$REAL_DOTFILES/home/zshrc" "$TEST_HOME/.zshrc"
  ln -s "$REAL_DOTFILES/home/zshenv" "$TEST_HOME/.zshenv"

  run bash "$UNINSTALL_CMD" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]

  # Symlinks must still exist after dry-run
  [ -L "$TEST_HOME/.zshrc" ]
  [ -L "$TEST_HOME/.zshenv" ]
}

@test "dry-run shows re-run prompt" {
  run bash "$UNINSTALL_CMD" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Re-run without --dry-run"* ]]
}

@test "dry-run does not remove LaunchAgent plists" {
  touch "$TEST_HOME/Library/LaunchAgents/com.dotfiles.sync.plist"

  run bash "$UNINSTALL_CMD" --dry-run
  [ "$status" -eq 0 ]

  # Plist must still exist
  [ -f "$TEST_HOME/Library/LaunchAgents/com.dotfiles.sync.plist" ]
}

@test "dry-run labels actions with [dry-run] prefix" {
  ln -s "$REAL_DOTFILES/home/zshrc" "$TEST_HOME/.zshrc"
  touch "$TEST_HOME/Library/LaunchAgents/com.dotfiles.sync.plist"

  run bash "$UNINSTALL_CMD" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"* ]]
}

# ── Functional: symlink removal ──

@test "removes symlinks pointing to dotfiles repo" {
  ln -s "$REAL_DOTFILES/home/zshrc" "$TEST_HOME/.zshrc"
  ln -s "$REAL_DOTFILES/home/zshenv" "$TEST_HOME/.zshenv"

  run bash "$UNINSTALL_CMD" --yes
  [ "$status" -eq 0 ]

  # Symlinks should be gone
  [ ! -L "$TEST_HOME/.zshrc" ]
  [ ! -L "$TEST_HOME/.zshenv" ]
}

@test "preserves symlinks not pointing to dotfiles repo" {
  # Create a symlink pointing somewhere else entirely
  mkdir -p "$TEST_DIR/other-tool"
  touch "$TEST_DIR/other-tool/config"
  ln -s "$TEST_DIR/other-tool/config" "$TEST_HOME/.other-config"

  # Also create a dotfiles symlink so chezmoi lists it
  ln -s "$REAL_DOTFILES/home/zshrc" "$TEST_HOME/.zshrc"

  run bash "$UNINSTALL_CMD" --yes
  [ "$status" -eq 0 ]

  # Non-dotfiles symlink must survive
  [ -L "$TEST_HOME/.other-config" ]
}

@test "preserves regular files (not symlinks) even if chezmoi-managed" {
  # .gitconfig is managed by chezmoi in copy mode (regular file)
  echo "[user]" > "$TEST_HOME/.gitconfig"

  run bash "$UNINSTALL_CMD" --yes
  [ "$status" -eq 0 ]

  # Regular file should survive (script only removes symlinks)
  [ -f "$TEST_HOME/.gitconfig" ]
}

@test "reports count of removed symlinks" {
  ln -s "$REAL_DOTFILES/home/zshrc" "$TEST_HOME/.zshrc"
  ln -s "$REAL_DOTFILES/home/zshenv" "$TEST_HOME/.zshenv"

  run bash "$UNINSTALL_CMD" --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removed 2 symlink(s)"* ]]
}

@test "reports zero removed when no dotfiles symlinks exist" {
  # No symlinks at all
  run bash "$UNINSTALL_CMD" --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removed 0 symlink(s)"* ]]
}

# ── Functional: local config preservation ──

@test "preserves .zshrc.local during uninstall" {
  echo "my local config" > "$TEST_HOME/.zshrc.local"
  ln -s "$REAL_DOTFILES/home/zshrc" "$TEST_HOME/.zshrc"

  run bash "$UNINSTALL_CMD" --yes
  [ "$status" -eq 0 ]

  [ -f "$TEST_HOME/.zshrc.local" ]
  [[ "$(cat "$TEST_HOME/.zshrc.local")" == "my local config" ]]
}

@test "preserves .gitconfig.local during uninstall" {
  echo "[user] name = local" > "$TEST_HOME/.gitconfig.local"

  run bash "$UNINSTALL_CMD" --yes
  [ "$status" -eq 0 ]

  [ -f "$TEST_HOME/.gitconfig.local" ]
}

@test "preserves .zshenv.secrets during uninstall" {
  echo "SECRET=hunter2" > "$TEST_HOME/.zshenv.secrets"

  run bash "$UNINSTALL_CMD" --yes
  [ "$status" -eq 0 ]

  [ -f "$TEST_HOME/.zshenv.secrets" ]
}

@test "displays preserved files in output" {
  echo "local" > "$TEST_HOME/.zshrc.local"
  echo "local" > "$TEST_HOME/.gitconfig.local"
  echo "secret" > "$TEST_HOME/.zshenv.secrets"

  run bash "$UNINSTALL_CMD" --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"Preserved"* ]]
  [[ "$output" == *".zshrc.local"* ]]
  [[ "$output" == *".gitconfig.local"* ]]
  [[ "$output" == *".zshenv.secrets"* ]]
}

# ── Functional: LaunchAgent handling ──

@test "unloads and removes dotfiles LaunchAgent plists" {
  touch "$TEST_HOME/Library/LaunchAgents/com.dotfiles.sync.plist"
  touch "$TEST_HOME/Library/LaunchAgents/com.dotfiles.doctor.plist"

  run bash "$UNINSTALL_CMD" --yes
  [ "$status" -eq 0 ]

  # Plists should be removed
  [ ! -f "$TEST_HOME/Library/LaunchAgents/com.dotfiles.sync.plist" ]
  [ ! -f "$TEST_HOME/Library/LaunchAgents/com.dotfiles.doctor.plist" ]
}

@test "calls launchctl bootout for each dotfiles LaunchAgent" {
  touch "$TEST_HOME/Library/LaunchAgents/com.dotfiles.sync.plist"

  bash "$UNINSTALL_CMD" --yes

  # Verify launchctl was called
  [ -f "$TEST_DIR/launchctl.log" ]
  grep -q "bootout" "$TEST_DIR/launchctl.log"
  grep -q "com.dotfiles.sync" "$TEST_DIR/launchctl.log"
}

@test "ignores non-dotfiles LaunchAgent plists" {
  touch "$TEST_HOME/Library/LaunchAgents/com.other.app.plist"

  run bash "$UNINSTALL_CMD" --yes
  [ "$status" -eq 0 ]

  # Non-dotfiles plist must survive
  [ -f "$TEST_HOME/Library/LaunchAgents/com.other.app.plist" ]
}

# ── Functional: output messages ──

@test "shows header banner on run" {
  run bash "$UNINSTALL_CMD" --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dotfiles uninstall"* ]]
}

@test "shows repo location after real uninstall" {
  run bash "$UNINSTALL_CMD" --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"dotfiles repo is still at"* ]]
}

# ── Functional: confirmation prompt ──

@test "confirmation prompt aborts on n" {
  run bash -c "echo n | bash '$UNINSTALL_CMD'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Aborted"* ]]
}

@test "confirmation prompt proceeds on y" {
  run bash -c "echo y | bash '$UNINSTALL_CMD'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Done"* ]]
}

@test "--yes skips confirmation prompt" {
  run bash "$UNINSTALL_CMD" --yes
  [ "$status" -eq 0 ]
  # Should not contain confirmation question
  [[ "$output" != *"Are you sure"* ]]
}

@test "--force skips confirmation prompt" {
  run bash "$UNINSTALL_CMD" --force
  [ "$status" -eq 0 ]
  [[ "$output" != *"Are you sure"* ]]
}

# ── CLI help-text drift guard ──
#
# `bin/dotfiles --help` is the public-facing surface that adopters discover
# the uninstall command through. The previous help string only advertised
# `[--dry-run]`, hiding the `--yes`/`--force` non-interactive form, so users
# scripting an uninstall had to read source. These two assertions pin the
# help-text contract:
#
#   1. The unified CLI help lists [--yes] alongside [--dry-run] for the
#      uninstall row.
#   2. `bin/dotfiles-uninstall` still parses `--yes` and `--force` — so
#      removing the help line by accident still trips a test, and removing
#      the parser branch trips a different test.

@test "bin/dotfiles --help advertises uninstall [--yes]" {
  local cli="$BATS_TEST_DIRNAME/../bin/dotfiles"
  run bash "$cli" --help
  [ "$status" -eq 0 ]
  # Match the literal "  uninstall ..." block in the help output and
  # require [--yes] on that same line.
  local row
  row=$(printf '%s\n' "$output" | grep -E '^  uninstall ')
  [ -n "$row" ] || { echo "missing uninstall row in dotfiles --help"; return 1; }
  [[ "$row" == *"[--yes]"* ]] || {
    echo "dotfiles --help uninstall row missing [--yes]: $row"
    return 1
  }
}

@test "bin/dotfiles-uninstall parser still recognizes --yes and --force" {
  # Pair to the help-text assertion above: if either flag drops out of
  # the parser, scripted uninstalls break even when the help text still
  # advertises [--yes]. Grep the source for the parse case.
  grep -qE '\-\-yes\|--force' "$UNINSTALL_CMD" || {
    echo "uninstall script no longer parses --yes|--force"
    return 1
  }
}
