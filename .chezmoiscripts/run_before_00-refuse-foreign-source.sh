#!/bin/bash
# Refuse to apply from a checkout that is not chezmoi's configured source.
# Every symlink_ template points into the source dir, so
# `chezmoi apply --source <other checkout>` would relink $HOME to that checkout.
# To switch checkouts on purpose, run `chezmoi init --source <dir>` first, or
# set DOTFILES_ALLOW_SOURCE_SWITCH=1 for a one-off apply.
set -euo pipefail

[ "${DOTFILES_ALLOW_SOURCE_SWITCH:-}" = "1" ] && exit 0

config="${CHEZMOI_CONFIG_FILE:-}"
effective="${CHEZMOI_SOURCE_DIR:-}"
if [ -z "$config" ] || [ ! -f "$config" ] || [ -z "$effective" ]; then
  exit 0
fi

configured="$(sed -n 's/^sourceDir:[[:space:]]*//p' "$config" | head -n 1 | tr -d "\"'")"
[ -z "$configured" ] && exit 0

_physical() { (cd "$1" 2>/dev/null && pwd -P) || printf '%s\n' "$1"; }
[ "$(_physical "$effective")" = "$(_physical "$configured")" ] && exit 0

{
  echo "dotfiles: refusing to apply from $effective"
  echo "  chezmoi's configured source is $configured ($config)."
  echo "  Applying from another checkout would relink \$HOME to it."
  echo "  Merge the change, then run 'dotfiles-sync' in $configured to fast-forward it."
  echo "  To switch checkouts on purpose, run 'chezmoi init --source <dir>' first."
} >&2
exit 1
