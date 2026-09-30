#!/bin/bash
# Doctor checks for shell module
check_symlink "symlink.zshenv"  "$DOTFILES_DIR/home/zshenv"   "$HOME/.zshenv"
check_symlink "symlink.zshrc"   "$DOTFILES_DIR/home/zshrc"    "$HOME/.zshrc"
check_managed "managed.hushlogin" "$DOTFILES_DIR/dot_hushlogin" "$HOME/.hushlogin"

check "shell.fzf_cached"     "fzf init cached"     "[ -f \"$HOME/.cache/zsh/fzf.zsh\" ]"     "fzf --zsh > \"$HOME/.cache/zsh/fzf.zsh\" 2>/dev/null"
check "shell.zoxide_cached"  "zoxide init cached"  "[ -f \"$HOME/.cache/zsh/zoxide.zsh\" ]"  "zoxide init zsh --cmd cd > \"$HOME/.cache/zsh/zoxide.zsh\" 2>/dev/null"
check "shell.dotfiles_on_path" "dotfiles bin on PATH (fix: chezmoi apply)" "grep -q '_dotfiles_bin' \"$DOTFILES_DIR/home/zshrc\"" ""
check "shell.node_options"   "NODE_OPTIONS max-old-space-size (fix: chezmoi apply)" "grep -q 'max-old-space-size' \"$DOTFILES_DIR/home/zshrc\"" ""
check "shell.ulimit"         "ulimit -n 65535 in .zshrc (fix: chezmoi apply)" "grep -q 'ulimit -n 65535' \"$DOTFILES_DIR/home/zshrc\"" ""
check "shell.homebrew_no_autoupdate" "HOMEBREW_NO_AUTO_UPDATE=1 (fix: chezmoi apply)" "grep -q 'HOMEBREW_NO_AUTO_UPDATE=1' \"$DOTFILES_DIR/home/zshrc\"" ""
