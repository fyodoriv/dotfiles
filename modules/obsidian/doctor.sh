#!/bin/bash
# Doctor checks for Obsidian module

# Only check if profile is "full" — Obsidian is a full-profile cask
if [ "${DOTFILES_PROFILE:-full}" != "full" ]; then
  return 0 2>/dev/null || exit 0
fi

VAULT_DIR="${OBSIDIAN_VAULT:-$HOME/notes}"

check "tool.obsidian" \
  "Obsidian installed (fix: brew install --cask obsidian)" \
  "[ -d '/Applications/Obsidian.app' ] || [ -d '$HOME/Applications/Obsidian.app' ]" \
  ""

check "obsidian.vault_exists" \
  "Obsidian vault at $VAULT_DIR (fix: mkdir -p $VAULT_DIR/.obsidian)" \
  "[ -d '$VAULT_DIR/.obsidian' ]" \
  "mkdir -p '$VAULT_DIR/.obsidian'"

check "obsidian.vim_mode" \
  "Vim mode enabled in Obsidian" \
  "[ -f '$VAULT_DIR/.obsidian/app.json' ] && grep -q '\"vimMode\": true' '$VAULT_DIR/.obsidian/app.json' 2>/dev/null" \
  ""

check "obsidian.daily_folder" \
  "Daily notes folder exists" \
  "[ -d '$VAULT_DIR/daily' ]" \
  "mkdir -p '$VAULT_DIR/daily'"

check "obsidian.templates_folder" \
  "Templates folder exists" \
  "[ -d '$VAULT_DIR/templates' ]" \
  "mkdir -p '$VAULT_DIR/templates'"
