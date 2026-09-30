#!/bin/bash
# Doctor checks for editor module
check_managed "managed.editorconfig" "$DOTFILES_DIR/dot_editorconfig" "$HOME/.editorconfig"
check_managed "managed.npmrc"        "$DOTFILES_DIR/modify_private_dot_npmrc" "$HOME/.npmrc"
