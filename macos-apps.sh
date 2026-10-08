#!/bin/bash
# macOS app-specific preferences — taste-dependent, applied only in --full profile.
# These configure third-party apps. Review before applying.
# Run: ./macos-apps.sh
#
# Defaults are defined in data/macos-defaults.json (script: "apps").
# Dynamic app-nap commands (osascript bundle lookup) remain inline below.

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/colors.sh
source "$DOTFILES_DIR/lib/colors.sh"
# shellcheck source=lib/apply-defaults.sh
source "$DOTFILES_DIR/lib/apply-defaults.sh"
# shellcheck source=lib/dotfiles-arch.sh
source "$DOTFILES_DIR/lib/dotfiles-arch.sh"

info "Applying app-specific preferences..."

# ── App Nap: keep work apps responsive ───────────────────────────────
# These use osascript for dynamic bundle ID lookup, so they stay inline.
set_app_responsiveness_defaults() {
  local app_name="$1"
  local fallback_bundle_identifier="$2"
  local app_bundle_identifier
  app_bundle_identifier=$(osascript -e "id of app \"$app_name\"" 2>/dev/null || echo "$fallback_bundle_identifier")
  defaults write "$app_bundle_identifier" NSAppSleepDisabled -bool true 2>/dev/null || true
  defaults write "$app_bundle_identifier" NSDisableAutomaticTermination -bool true 2>/dev/null || true
}

set_app_responsiveness_defaults "Cursor" "com.todesktop.230313mzl4w4u92"
set_app_responsiveness_defaults "Slack" "com.tinyspeck.slackmacgap"
set_app_responsiveness_defaults "Google Chrome" "com.google.Chrome"
set_app_responsiveness_defaults "Microsoft Outlook" "com.microsoft.Outlook"
set_app_responsiveness_defaults "Ghostty" "com.mitchellh.ghostty"
set_app_responsiveness_defaults "WebStorm" "com.jetbrains.WebStorm"
set_app_responsiveness_defaults "Terminal" "com.apple.Terminal"

# ── Login items: apps that start on boot ──────────────────────────────
# Declarative list of apps that should be login items. Adds missing ones,
# removes legacy dotfiles-managed items, does NOT remove other user extras.
# Cursor starts via com.dotfiles.cursor-at-login LaunchAgent (open -g -a Cursor)
# so it does not steal focus at login. Uses osascript — the only reliable way
# to manage login items on macOS.
_login_items="$(osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null || echo "")"
_removed_login_apps=(
  "WebStorm"
)
for _name in "${_removed_login_apps[@]}"; do
  if [[ "$_login_items" == *"$_name"* ]]; then
    osascript -e "tell application \"System Events\" to delete login item \"$_name\"" 2>/dev/null || true
    echo "  ✓ Removed $_name from login items (replaced by Cursor LaunchAgent)"
  fi
done
_desired_login_apps=(
  "Ghostty:/Applications/Ghostty.app"
)
for _entry in "${_desired_login_apps[@]}"; do
  _name="${_entry%%:*}"
  _path="${_entry#*:}"
  if [[ "$_login_items" != *"$_name"* ]] && [ -d "$_path" ]; then
    osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"$_path\", hidden:false}" 2>/dev/null || true
    echo "  ✓ Added $_name to login items"
  fi
done

# ── Architecture: native arm64 on Apple Silicon ───────────────────────
# Legacy dotfiles forced Ghostty (and occasionally other work apps) to x86_64
# Rosetta so /usr/local Intel Homebrew tools resolved in shell children. After
# the arm64 Homebrew migration that causes Rosetta warnings for every native
# app/tool. Clear LSArchitecturePriority overrides for all managed apps.
dotfiles_clear_managed_app_rosetta_overrides

# ── Apply all app defaults from data file ─────────────────────────────
apply_defaults "apps"

echo "✅ App preferences applied."
