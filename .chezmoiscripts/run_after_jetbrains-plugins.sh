#!/bin/bash
# Install the JetBrains recommended plugin set after every `dotfiles apply`.
#
# Idempotent — `bin/jetbrains-install-plugins` runs `installPlugins` per plugin
# per detected IDE, and `installPlugins` itself is a no-op when the plugin is
# already installed ("already installed: <id>"). Re-running the script daily
# costs ~2s per closed IDE × <plugin-count> network checks, all returning
# cache hits in a steady state.
#
# Gracefully skips IDEs that are currently running — `installPlugins` errors
# with "Only one instance of <IDE> can be run at a time." on a running IDE.
# The script reports the skip and exits 0 so this lifecycle step never blocks
# `dotfiles apply` on whether the operator has WebStorm open.
#
# Skips entirely when:
#   - No JetBrains IDE is installed (no /Applications/{WebStorm,IntelliJ ...,Aqua}.app)
#   - The recommended_plugins.txt list is missing or empty
set -euo pipefail

# Resolve DOTFILES_DIR via the same pattern other lifecycle scripts use.
# chezmoi may copy this script to a tmpdir at runtime; the script's own
# location is unreliable. The well-known repo path is the simplest resolver.
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/apps/tooling/dotfiles}"
if [ ! -d "$DOTFILES_DIR" ]; then
  DOTFILES_DIR="$HOME/apps/dotfiles"
fi
if [ ! -d "$DOTFILES_DIR" ]; then
  echo "⚠ Could not resolve DOTFILES_DIR; skipping jetbrains plugin install."
  exit 0
fi

INSTALLER="$DOTFILES_DIR/bin/jetbrains-install-plugins"
if [ ! -x "$INSTALLER" ]; then
  echo "⚠ $INSTALLER not found; skipping jetbrains plugin install."
  exit 0
fi

# Skip if no JetBrains IDE is installed — the installer would no-op anyway,
# but checking here avoids the noise of "No JetBrains IDEs detected" on every
# `dotfiles apply`.
_has_jb_ide=0
for app in /Applications/WebStorm.app /Applications/IntelliJ\ IDEA.app \
           /Applications/IntelliJ\ IDEA\ Ultimate.app \
           /Applications/IntelliJ\ IDEA\ Community\ Edition.app \
           /Applications/PyCharm.app /Applications/PyCharm\ Professional\ Edition.app \
           /Applications/PyCharm\ Community\ Edition.app \
           /Applications/GoLand.app /Applications/Rider.app /Applications/CLion.app \
           /Applications/RubyMine.app /Applications/PhpStorm.app \
           /Applications/DataGrip.app /Applications/Aqua.app; do
  if [ -d "$app" ]; then
    _has_jb_ide=1
    break
  fi
done
if [ "$_has_jb_ide" -eq 0 ]; then
  exit 0
fi

echo "→ Installing recommended JetBrains plugins..."
"$INSTALLER"
