#!/bin/bash
# Move a hand-added [user] section out of ~/.gitconfig into ~/.gitconfig.local.
#
# ~/.gitconfig is chezmoi-managed and holds no identity. `git config --global
# user.email ...` writes into it, so chezmoi sees drift and asks to confirm
# the overwrite. With no TTY (LaunchAgent, agent shell) that prompt fails with
# "could not open a new TTY". ~/.gitconfig.local is included by the managed
# file and chezmoi never manages it, so identity belongs there.
#
# Loss-safe rules:
#   - Keys missing from the local file are copied over (values never printed).
#   - If the local file already holds a different value, the local value wins.
#     The old [user] lines are saved to ~/.gitconfig.user-backup (mode 600).
#   - The [user] section is removed from the managed file last.
#
# Usage: gitconfig_user_migrate [gitconfig] [gitconfig_local]
# Exit: 0 migrated or nothing to do, 1 git failure. Prints one status line.

gitconfig_has_user_section() {
  local gitconfig="${1:-$HOME/.gitconfig}"
  [ -f "$gitconfig" ] || return 1
  git config -f "$gitconfig" --get-regexp '^user\.' >/dev/null 2>&1
}

gitconfig_user_migrate() {
  local gitconfig="${1:-$HOME/.gitconfig}"
  local local_cfg="${2:-$HOME/.gitconfig.local}"
  local backup="${gitconfig}.user-backup"
  local key value existing conflict=0

  gitconfig_has_user_section "$gitconfig" || return 0

  # Own the staged writes: a failed copy leaves the managed file untouched.
  while IFS= read -r key; do
    value="$(git config -f "$gitconfig" --get "$key")" || return 1
    if existing="$(git config -f "$local_cfg" --get "$key" 2>/dev/null)"; then
      if [ "$existing" != "$value" ]; then
        conflict=1
        (umask 077; printf '%s = %s\n' "$key" "$value" >> "$backup")
      fi
      continue
    fi
    git config -f "$local_cfg" "$key" "$value" || return 1
  done < <(git config -f "$gitconfig" --name-only --get-regexp '^user\.' | sort -u)

  git config -f "$gitconfig" --remove-section user || return 1
  if [ "$conflict" -eq 1 ]; then
    echo "gitconfig: moved [user] to $local_cfg (conflicting values kept in $backup)"
  else
    echo "gitconfig: moved [user] from $gitconfig to $local_cfg"
  fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  gitconfig_user_migrate "$@"
fi
