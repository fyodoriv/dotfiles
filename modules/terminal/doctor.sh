#!/bin/bash
# Doctor checks for terminal module
# shellcheck source=../../lib/dotfiles-arch.sh
source "$DOTFILES_DIR/lib/dotfiles-arch.sh"

check "tool.tmux" "tmux installed" "command -v tmux" "brew install tmux 2>/dev/null"
check_symlink "symlink.tmux"    "$DOTFILES_DIR/home/tmux.conf"   "$HOME/.tmux.conf"
check "tool.ghostty" "Ghostty installed (fix: brew install --cask ghostty)" "[ -d '/Applications/Ghostty.app' ]" ""
# Apple Silicon: legacy dotfiles forced Ghostty to Rosetta — flag if still set.
if dotfiles_is_apple_silicon; then
  check "apps.no_rosetta_override" "Managed work apps not forced to x86_64 Rosetta (LSArchitecturePriority)" \
    "dotfiles_managed_apps_have_no_x86_override" \
    "dotfiles_clear_managed_app_rosetta_overrides && echo 'Quit affected apps and reopen, or chezmoi apply'"
  check "tool.ghostty.arch" "Ghostty not forced to x86_64 Rosetta on Apple Silicon" \
    "[ ! -d '/Applications/Ghostty.app' ] || ! dotfiles_app_has_x86_ls_priority 'com.mitchellh.ghostty'" \
    "dotfiles_clear_app_ls_architecture_priority 'com.mitchellh.ghostty' && echo 'Quit Ghostty, reopen, or chezmoi apply'"
fi
check_managed "managed.ghostty" "$DOTFILES_DIR/dot_config/ghostty/config"   "$HOME/.config/ghostty/config"
