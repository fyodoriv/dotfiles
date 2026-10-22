#!/bin/bash
# Install the JetBrains recommended plugin set after every `dotfiles apply`.
#
# Runs `bin/jetbrains-install-plugins --if-changed`. Each `installPlugins` call
# starts one headless IDE JVM, even for a plugin that is already installed: 40 s+
# and ~400 MB each on a busy Mac, 5 plugins per IDE. `bin/dotfiles-sync` applies
# every 30 minutes, so the installer keeps a stamp per IDE in
# ${XDG_STATE_HOME:-~/.local/state}/dotfiles/jetbrains-plugins/ (IDE build +
# plugin list). A no-change apply starts no JVM. A plugin list change, an IDE
# upgrade, or a new IDE re-runs the install. A failed install writes no stamp.
#
# Gracefully skips IDEs that are currently running — `installPlugins` errors
# with "Only one instance of <IDE> can be run at a time." on a running IDE.
# The script reports the skip and exits 0 so this lifecycle step never blocks
# `dotfiles apply` on whether the operator has WebStorm open. A skipped IDE
# gets no stamp, so the next apply after you close it installs.
#
# Skips entirely when:
#   - No JetBrains IDE is installed (no /Applications/{WebStorm,IntelliJ ...,Aqua}.app;
#     JETBRAINS_APP_DIRS overrides the folder list, for tests)
#   - The recommended_plugins.txt list is missing or empty
set -euo pipefail

# Resolve DOTFILES_DIR via the same pattern other lifecycle scripts use.
# chezmoi may copy this script to a tmpdir at runtime; the script's own
# location is unreliable. chezmoi exports CHEZMOI_SOURCE_DIR to scripts; the
# well-known repo path is the last resort.
DOTFILES_DIR="${DOTFILES_DIR:-${CHEZMOI_SOURCE_DIR:-$HOME/apps/tooling/dotfiles}}"
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
IFS=: read -r -a _jb_app_dirs <<< "${JETBRAINS_APP_DIRS:-/Applications}"
for _jb_dir in "${_jb_app_dirs[@]}"; do
  for app in WebStorm "IntelliJ IDEA" "IntelliJ IDEA Ultimate" \
             "IntelliJ IDEA Community Edition" \
             PyCharm "PyCharm Professional Edition" "PyCharm Community Edition" \
             GoLand Rider CLion RubyMine PhpStorm DataGrip Aqua; do
    if [ -d "$_jb_dir/$app.app" ]; then
      _has_jb_ide=1
      break 2
    fi
  done
done
if [ "$_has_jb_ide" -eq 0 ]; then
  exit 0
fi

echo "→ Checking recommended JetBrains plugins..."
# A failed plugin download (network, renamed plugin id) must not fail the
# whole apply: bin/dotfiles-install treats a failed apply as critical and
# rolls the Mac back. The installer prints which plugins failed.
"$INSTALLER" --if-changed || echo "⚠ Some JetBrains plugins did not install; rerun: $INSTALLER"
