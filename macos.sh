#!/bin/bash
# macOS no-brainer developer defaults — universally good, no taste involved.
# Run: ./macos.sh
# Taste-dependent settings are in macos-visual.sh and macos-apps.sh (applied in --full only).
# Some changes require logout or restart to take effect.
#
# ⚠ SECURITY-RELEVANT CHANGES (review before running):
#   - pmset (power management changes via sudo)
#   - killall Dock/Finder/SystemUIServer: restarts system UI
#   - Spotlight indexing locations modified
#   - Auto-correct, smart quotes, smart dashes disabled globally
#
# Defaults are defined in data/macos-defaults.json (script: "core").
# Non-defaults commands (pmset, spotlight, killall) remain inline below.

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/colors.sh
source "$DOTFILES_DIR/lib/colors.sh"
# shellcheck source=lib/apply-defaults.sh
source "$DOTFILES_DIR/lib/apply-defaults.sh"

# ── Auto-snapshot guard (safety net for direct invocation) ───────────
# install.sh sets DOTFILES_SNAPSHOT_DONE=1 before calling modules, so this
# only fires when macos.sh is run directly (./macos.sh).
if [ -z "${DOTFILES_SNAPSHOT_DONE:-}" ]; then
  info "Creating safety snapshot before applying macOS defaults..."
  bash "$DOTFILES_DIR/snapshot.sh" --macos 2>/dev/null || warn "Snapshot failed — continuing anyway"
  export DOTFILES_SNAPSHOT_DONE=1
fi

info "Applying macOS defaults (no-brainer only)..."

# ── Apply all core defaults from data file ────────────────────────────
apply_defaults "core"

# ── Transparency note ────────────────────────────────────────────────
# com.apple.universalaccess is TCC-protected on macOS 16+ and cannot
# be written via defaults. Set manually: System Settings → Accessibility →
# Display → Reduce transparency.
echo "⚠️  Transparency: set manually via System Settings → Accessibility → Display → Reduce transparency"

# ── Spotlight: exclude dev directories ───────────────────────────────
REPOS_DIR="${DOTFILES_REPOS_DIR:-$HOME/apps}"
for dir in \
  "$REPOS_DIR" \
  "$HOME/.nvm" \
  "$HOME/.gradle" \
  "$HOME/.cache" \
  "$HOME/.npm" \
  "$HOME/.yarn" \
  "$HOME/.docker" \
  "$HOME/.rd" \
  "$HOME/.pyenv" \
  "$HOME/.local" \
  "$HOME/.orbstack" \
  "$HOME/.config" \
  "$HOME/Library/Caches" \
  "$HOME/Library/Application Support/JetBrains" \
  "$HOME/Library/Application Support/Google/Chrome" \
  "$HOME/.orchestrator" \
  "$HOME/.claude/projects" \
  "$HOME/.agent-browser"; do
  [ -d "$dir" ] || continue
  [ -e "$dir/.metadata_never_index" ] && continue
  # macOS privacy protection can deny writes in app data dirs (e.g. Chrome).
  touch "$dir/.metadata_never_index" 2>/dev/null ||
    warn "Spotlight: cannot write marker in $dir — optional: grant the terminal Full Disk Access, or exclude it in System Settings → Spotlight"
done
fd -t d -d 3 "^node_modules$" "$REPOS_DIR" --exec touch {}/.metadata_never_index 2>/dev/null || true
defaults write com.apple.Spotlight orderedItems -array \
  '{"enabled" = 1;"name" = "DIRECTORIES";}' \
  '{"enabled" = 1;"name" = "DOCUMENTS";}' \
  '{"enabled" = 1;"name" = "IMAGES";}' \
  '{"enabled" = 1;"name" = "PDF";}' \
  '{"enabled" = 1;"name" = "PRESENTATIONS";}' \
  '{"enabled" = 1;"name" = "SPREADSHEETS";}' \
  '{"enabled" = 1;"name" = "SOURCE";}' \
  '{"enabled" = 1;"name" = "MENU_OTHER";}' \
  '{"enabled" = 1;"name" = "CONTACT";}' \
  '{"enabled" = 1;"name" = "EVENT_TODO";}' \
  '{"enabled" = 0;"name" = "APPLICATIONS";}' \
  '{"enabled" = 0;"name" = "SYSTEM_PREFS";}' \
  '{"enabled" = 0;"name" = "MENU_SPOTLIGHT_SUGGESTIONS";}' \
  '{"enabled" = 0;"name" = "MENU_CONVERSION";}' \
  '{"enabled" = 0;"name" = "MENU_EXPRESSION";}' \
  '{"enabled" = 0;"name" = "MENU_DEFINITION";}' \
  '{"enabled" = 0;"name" = "MESSAGES";}' \
  '{"enabled" = 0;"name" = "BOOKMARKS";}' \
  '{"enabled" = 0;"name" = "MUSIC";}' \
  '{"enabled" = 0;"name" = "MOVIES";}' \
  '{"enabled" = 0;"name" = "FONTS";}' \
  '{"enabled" = 0;"name" = "MENU_WEBSEARCH";}' 2>/dev/null || true

# ── Power management ─────────────────────────────────────────────────
if id -Gn 2>/dev/null | grep -qw admin; then
  echo "→ Power management settings require sudo (complete your SSO/MFA prompt now)..."
  if ! sudo -v 2>/dev/null; then
    echo "⚠ sudo unavailable (no TTY) — skipping power management. Run 'chezmoi apply' in an interactive terminal to apply pmset settings."
  else
  if [ "${IS_ENTERPRISE:-false}" = "true" ] && profiles list 2>/dev/null | grep -q .; then
    echo -e "${YELLOW}⚠${NC} MDM profiles detected — power management settings below may be overridden by your IT department"
  fi
  # AC: normal idle timers. The process-scoped keepawake manager temporarily
  # holds sleep/disk sleep only while Cursor or Claude Code is actually running.
  sudo pmset -c powermode 2 2>/dev/null || true
  sudo pmset -c sleep 1 2>/dev/null || true
  sudo pmset -c disksleep 10 2>/dev/null || true
  # Wake on LAN: off — dev workstations don't need remote wakeup
  sudo pmset -c womp 0 2>/dev/null || true

  # ── Network resilience (survives sleep/wake + lid close/open) ────────
  # Keep WiFi and TCP alive during sleep so agent sessions reconnect fast.
  # Without these, closing the lid kills all websocket connections and the
  # security stack (VPN / endpoint agents) must cold-start on wake.
  sudo pmset -a tcpkeepalive 1 2>/dev/null || true
  sudo pmset -a networkoversleep 1 2>/dev/null || true
  # Power Nap on AC: periodic background wake for keepalives and sync.
  # Disabled on battery (-b) to preserve charge.
  sudo pmset -c powernap 1 2>/dev/null || true
  sudo pmset -b powernap 0 2>/dev/null || true
  # Idle lock target: 15 min on AC and battery. Display sleep must not be
  # shorter because password-on-sleep locks immediately once display sleep starts.
  sudo pmset -a displaysleep 15 2>/dev/null || true
  sudo pmset -b sleep 15 2>/dev/null || true
  sudo pmset -b disksleep 15 2>/dev/null || true
  # Instant wake on lid open
  sudo pmset -a lidwake 1 2>/dev/null || true
  fi  # sudo -v succeeded
else
  echo "→ Skipping power management — no admin rights on this machine"
fi

# ── Restart affected services ────────────────────────────────────────
killall Dock 2>/dev/null || true
killall Finder 2>/dev/null || true
killall SystemUIServer 2>/dev/null || true

echo "✅ macOS defaults applied (no-brainer only). Run macos-visual.sh + macos-apps.sh for taste settings."
echo "ℹ️  Some changes require logout or restart to take effect."
