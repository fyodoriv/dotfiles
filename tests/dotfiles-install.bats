#!/usr/bin/env bats
# bin/dotfiles-install: plan, backup, apply, heal, verify, auto-restore, and
# the agentbrew hand-off. chezmoi, defaults, launchctl, brew, zsh, and the
# doctor are stubs, so nothing touches the real Mac.

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$TEST_DIR/home" XDG_STATE_HOME="$TEST_DIR/home/.local/state"
  STUBS="$TEST_DIR/stubs"; LOG="$TEST_DIR/calls.log"; STORE="$TEST_DIR/defaults"
  mkdir -p "$HOME/.config/chezmoi" "$STUBS" "$STORE"
  printf '# my zshrc\n' > "$HOME/.zshrc"
  printf 'old-config\n' > "$HOME/.config/chezmoi/chezmoi.yaml"
  printf 'original-dock\n' > "$STORE/com.apple.dock"

  stub() { printf '#!/bin/bash\n%s\n' "$2" > "$STUBS/$1"; chmod +x "$STUBS/$1"; }
  stub chezmoi 'echo "chezmoi $*" >> "$LOG"
case "$1" in
  init) echo new-config > "$HOME/.config/chezmoi/chezmoi.yaml" ;;
  managed) printf ".zshrc\n.gitconfig\n" ;;
  apply)
    echo "# dotfiles zshrc" > "$HOME/.zshrc"; echo "[user]" > "$HOME/.gitconfig"
    mkdir -p "$HOME/Library/LaunchAgents"; echo plist > "$HOME/Library/LaunchAgents/com.dotfiles.sync.plist"
    [ "${DOTFILES_SKIP_MACOS_DEFAULTS:-}" = 1 ] || { defaults write com.apple.dock autohide -bool true; defaults write com.apple.finder X -bool true; }
    exit "${FAIL_APPLY:-0}" ;;
  verify) exit "${FAIL_VERIFY:-0}" ;;
esac'
  stub defaults 'echo "defaults $*" >> "$LOG"
case "$1" in
  export) [ -f "$STORE/$2" ] && cp "$STORE/$2" "$3" ;;
  import) cp "$3" "$STORE/$2" ;;
  write) echo "changed $*" > "$STORE/$2" ;;
  delete) rm -f "$STORE/$2" ;;
esac'
  for tool in launchctl brew killall xcode-select; do stub "$tool" "echo \"$tool \$*\" >> \"\$LOG\""; done
  stub zsh 'exit 0'
  stub doctor 'echo "doctor $*" >> "$LOG"'
  export PATH="$STUBS:$PATH" LOG STORE DOTFILES_INSTALL_DOCTOR="$STUBS/doctor"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "plan explains needs, steps, backup, rollback limits, and choices, and changes nothing" {
  run bash "$REPO/bin/dotfiles-install" plan
  [ "$status" -eq 0 ]
  for text in "What you need" "Your Mac password" "Back up to" "macOS settings domains" \
    "restores the backup automatically" "Homebrew packages stay installed" "Also install agentbrew"; do
    [[ "$output" == *"$text"* ]] || { echo "missing: $text"; return 1; }
  done
  [ ! -e "$XDG_STATE_HOME/dotfiles" ]
  [ "$(cat "$HOME/.zshrc")" = "# my zshrc" ]
}

@test "run refuses without --yes" {
  run bash "$REPO/bin/dotfiles-install" run
  [ "$status" -eq 2 ]
}

@test "run backs up, applies with the answers, heals, verifies, and suggests a fork PR" {
  run bash "$REPO/bin/dotfiles-install" run --yes --profile full --name "Alex Example" --email alex@example.com --no-agentbrew
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -q 'promptChoice Installation profile.*=full' "$LOG"
  grep -q 'Git commit email for work/default identity=alex@example.com' "$LOG"
  grep -q 'chezmoi apply' "$LOG"
  grep -q 'doctor --fix' "$LOG"
  grep -q 'chezmoi verify' "$LOG"
  [[ "$output" == *"dotfiles contribute"* ]]
  [[ "$output" == *"add a test and update the docs"* ]]
  local backup; backup="$(ls "$XDG_STATE_HOME/dotfiles/install-backups")"
  [ -f "$XDG_STATE_HOME/dotfiles/install-backups/$backup/defaults/com.apple.dock.plist" ]
  [ "$(cat "$XDG_STATE_HOME/dotfiles/install-backups/$backup/chezmoi.yaml")" = "old-config" ]
}

@test "a failed verify restores files, LaunchAgents, chezmoi config, and macOS settings by itself" {
  FAIL_VERIFY=1 run bash "$REPO/bin/dotfiles-install" run --yes --no-agentbrew
  [ "$status" -eq 1 ]
  [[ "$output" == *"Critical error during verification"* ]]
  [ "$(cat "$HOME/.zshrc")" = "# my zshrc" ]
  [ ! -e "$HOME/.gitconfig" ]
  [ ! -e "$HOME/Library/LaunchAgents/com.dotfiles.sync.plist" ]
  [ "$(cat "$HOME/.config/chezmoi/chezmoi.yaml")" = "old-config" ]
  [ "$(cat "$STORE/com.apple.dock")" = "original-dock" ]
  [ ! -e "$STORE/com.apple.finder" ]
}

@test "a failed apply restores too, and --no-macos-defaults leaves settings alone" {
  FAIL_APPLY=1 run bash "$REPO/bin/dotfiles-install" run --yes --no-agentbrew
  [ "$status" -eq 1 ]
  [ "$(cat "$HOME/.zshrc")" = "# my zshrc" ]

  run bash "$REPO/bin/dotfiles-install" run --yes --no-agentbrew --no-macos-defaults
  [ "$status" -eq 0 ]
  [ "$(cat "$STORE/com.apple.dock")" = "original-dock" ]
  run bash "$REPO/bin/dotfiles-install" restore
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.zshrc")" = "# my zshrc" ]
}

@test "hands off to agentbrew's installer with the user's agentbrew flags" {
  mkdir -p "$TEST_DIR/agentbrew/.git" "$TEST_DIR/agentbrew/scripts"
  printf '#!/bin/bash\necho "agentbrew-install $*" >> "%s"\n' "$LOG" > "$TEST_DIR/agentbrew/scripts/install.sh"
  run bash "$REPO/bin/dotfiles-install" run --yes --agentbrew-dir "$TEST_DIR/agentbrew" --agentbrew-flags "--no-auto-repair"
  [ "$status" -eq 0 ]
  grep -q 'agentbrew-install run --yes --no-auto-repair' "$LOG"
}

@test "README opens with the one sentence for the agent, and INSTALL.md covers every phase" {
  head -25 "$REPO/README.md" | grep -qF "Install dotfiles by following https://github.com/fyodoriv/dotfiles/blob/feat/chezmoi/INSTALL.md"
  for text in "dotfiles-install plan" "dotfiles-install run --yes" "dotfiles-install restore" \
    "full context" "restores the backup by itself" "add or update a test" "dotfiles contribute"; do
    grep -qF "$text" "$REPO/INSTALL.md" || { echo "INSTALL.md missing: $text"; return 1; }
  done
  # Every flag the playbook maps answers to exists in the installer.
  for flag in $(grep -oE -- '--(no-[a-z-]+|profile|name|email|agentbrew-flags)' "$REPO/INSTALL.md" | sort -u); do
    grep -qF -- "$flag" "$REPO/bin/dotfiles-install" || { echo "unknown flag in INSTALL.md: $flag"; return 1; }
  done
  grep -qx 'INSTALL.md' "$REPO/.chezmoiignore"
}
