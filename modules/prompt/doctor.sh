#!/bin/bash
# Doctor checks for prompt module
check "tool.starship" "starship installed" "command -v starship" "brew install starship 2>/dev/null"
check_managed "managed.starship" "$DOTFILES_DIR/dot_config/starship.toml" "$HOME/.config/starship.toml"
check "prompt.config_valid" "starship config valid" \
  "! command -v starship >/dev/null 2>&1 || ! [ -f \"$HOME/.config/starship.toml\" ] || STARSHIP_CONFIG=\"$HOME/.config/starship.toml\" starship print-config >/dev/null 2>&1"
