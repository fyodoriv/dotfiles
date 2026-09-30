#!/bin/bash
# Doctor checks for ssh module
check_managed "managed.ssh" "$DOTFILES_DIR/private_dot_ssh/config.tmpl" "$HOME/.ssh/config"
check "security.ssh_permissions" "SSH config permissions (600)" \
  "[ \"\$(stat -f '%A' $HOME/.ssh/config 2>/dev/null)\" = '600' ]" \
  "chmod 600 $HOME/.ssh/config 2>/dev/null"
