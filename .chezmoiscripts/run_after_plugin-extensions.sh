#!/bin/bash
# Regenerate company plugin outputs that must follow plugins.lock on every
# apply (issue #145, step 6): the shell fragment loader.
set -euo pipefail

DOTFILES_DIR="${CHEZMOI_SOURCE_DIR:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
[ -f "$DOTFILES_DIR/lib/plugin-extensions.sh" ] || exit 0
command -v yq >/dev/null 2>&1 || exit 0
for lib in plugin plugin-capabilities plugin-extensions; do
  # shellcheck source=/dev/null
  source "$DOTFILES_DIR/lib/$lib.sh"
done
plugin_shell_pass || echo "⚠ Some plugin shell fragments were not loaded (see above)"
