#!/bin/bash
# Data-driven blocked-software scan (issue #145, step 7). A company plugin
# lists software its org does not allow in contributes.blocked_software:
#
#   apps: [Example.app]          # looked up in /Applications and ~/Applications
#   casks: [example-cask]        # Homebrew casks
#   formulae: [example-formula]  # Homebrew formulae
#
# The core owns the scan; the plugin passes data only.

# blocked_software_found <yaml>: prints one line per installed blocked item.
blocked_software_found() {
  local file="$1" item installed
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    if [ -d "${BLOCKED_SOFTWARE_APPS_DIR:-/Applications}/$item" ] || [ -d "$HOME/Applications/$item" ]; then
      printf 'app %s\n' "$item"
    fi
  done < <(yq -r '.apps // [] | .[]' "$file" 2>/dev/null)
  command -v brew >/dev/null 2>&1 || return 0
  installed="$(brew list --cask -1 2>/dev/null)"
  while IFS= read -r item; do
    [ -n "$item" ] && printf '%s\n' "$installed" | grep -qxF -- "$item" && printf 'cask %s\n' "$item"
  done < <(yq -r '.casks // [] | .[]' "$file" 2>/dev/null)
  installed="$(brew list --formula -1 2>/dev/null)"
  while IFS= read -r item; do
    [ -n "$item" ] && printf '%s\n' "$installed" | grep -qxF -- "$item" && printf 'formula %s\n' "$item"
  done < <(yq -r '.formulae // [] | .[]' "$file" 2>/dev/null)
  return 0
}
