#!/bin/bash
# Doctor checks for tools module
for tool in fzf eza bat fd rg zoxide tree htop jq gum delta fastfetch topgrade; do
  case "$tool" in
    rg)    brew_pkg="ripgrep" ;;
    delta) brew_pkg="git-delta" ;;
    *)     brew_pkg="$tool" ;;
  esac
  check "tool.$tool" "$tool installed" "command -v $tool" "brew install $brew_pkg 2>/dev/null"
done

# topgrade config — managed by dotfiles. The wrapper script + LaunchAgent
# both depend on this file existing at the path topgrade actually reads.
# topgrade reads ~/.config/topgrade.toml (file directly under .config),
# NOT ~/.config/topgrade/topgrade.toml (subdir). PR #126 shipped the wrong
# path and topgrade silently ran with defaults — disabled steps like
# chezmoi / git_repos / containers all fired. Verified via the actual
# topgrade 17.5.1 behaviour: `topgrade --edit-config` opens
# "~/.config/topgrade.toml".
check_managed "managed.topgrade" \
  "$DOTFILES_DIR/dot_config/topgrade.toml" \
  "$HOME/.config/topgrade.toml"
