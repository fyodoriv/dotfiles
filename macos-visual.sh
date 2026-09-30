#!/bin/bash
# macOS visual & input preferences — taste-dependent, applied only in --full profile.
# These are personal preferences. Review before applying.
# Run: ./macos-visual.sh
#
# Defaults are defined in data/macos-defaults.json (script: "visual").
# Non-defaults commands (hidutil, dockutil, killall) remain inline below.

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/colors.sh
source "$DOTFILES_DIR/lib/colors.sh"
# shellcheck source=lib/apply-defaults.sh
source "$DOTFILES_DIR/lib/apply-defaults.sh"

info "Applying macOS visual preferences..."

# ── Apply all visual defaults from data file ──────────────────────────
apply_defaults "visual"

# ── Undo static-only (was hiding persistent-others folders) ──────────
defaults delete com.apple.dock static-only 2>/dev/null || true

# ── Dock items (folders on the right side) ────────────────────────────
if command -v dockutil &>/dev/null; then
  if dockutil --find Applications &>/dev/null; then
    dockutil --add /Applications --view grid --display folder --sort name --replacing Applications --no-restart
  else
    dockutil --add /Applications --view grid --display folder --sort name --no-restart
  fi
  if dockutil --find Downloads &>/dev/null; then
    dockutil --add "$HOME/Downloads" --view grid --display stack --sort dateadded --replacing Downloads --no-restart
  else
    dockutil --add "$HOME/Downloads" --view grid --display stack --sort dateadded --no-restart
  fi
fi

# ── Caps Lock → Control ──────────────────────────────────────────────
hidutil property --set '{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x7000000E0}]}' >/dev/null 2>&1

# ── Restart affected services ────────────────────────────────────────
killall Dock 2>/dev/null || true
killall Finder 2>/dev/null || true

echo "✅ Visual preferences applied. Some changes may require logout."
