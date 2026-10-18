#!/bin/bash
# Doctor checks for extras module

# dockutil, lazygit, and tig come with the full profile only.
if [ "${DOTFILES_PROFILE:-full}" != "full" ]; then
  return 0 2>/dev/null || exit 0
fi

check "tool.dockutil" "dockutil installed" "command -v dockutil" "brew install dockutil 2>/dev/null"
check_managed "managed.gradle" "$DOTFILES_DIR/dot_gradle/gradle.properties" "$HOME/.gradle/gradle.properties"
check_managed "managed.lazygit" "$DOTFILES_DIR/dot_config/lazygit/config.yml" "$HOME/.config/lazygit/config.yml"
check_managed "managed.tigrc" "$DOTFILES_DIR/dot_tigrc" "$HOME/.tigrc"
