#!/bin/bash
# Shared colors and logging helpers for bin/ scripts.
# Usage: source "$(cd "$(dirname "$0")/.." && pwd)/lib/colors.sh"
# shellcheck disable=SC2034  # variables used by sourcing scripts
#
# Respects NO_COLOR (https://no-color.org/) and non-TTY stdout.
# Override with FORCE_COLOR=1 to enable colors unconditionally.

if [ -n "${NO_COLOR+set}" ] || { [ -z "${FORCE_COLOR:-}" ] && [ ! -t 1 ]; }; then
  GREEN='' YELLOW='' BLUE='' RED='' DIM='' NC=''
else
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  RED='\033[0;31m'
  DIM='\033[2m'
  NC='\033[0m'
fi

_COLORS_SOURCED=1

info()    { echo -e "${BLUE}→${NC} $1"; }
ok()      { echo -e "${GREEN}✓${NC} $1"; }
warn()    { echo -e "${YELLOW}⚠${NC} $1"; }
fail()    { echo -e "${RED}✗${NC} $1"; }
section() { echo -e "\n${BLUE}── $1 ──${NC}"; }

# Send a macOS notification. Uses terminal-notifier (authorized, shows content
# correctly on macOS 14+) when available; falls back to osascript.
# Usage: notify "title" "message" [sound]
notify() {
  local title="$1" message="$2" sound="${3:-}"
  if command -v terminal-notifier &>/dev/null; then
    local args=(-title "$title" -message "$message")
    [ -n "$sound" ] && args+=(-sound default)
    terminal-notifier "${args[@]}" 2>/dev/null || true
  else
    local sound_clause=""
    [ -n "$sound" ] && sound_clause=" sound name \"$sound\""
    osascript -e "display notification \"$message\" with title \"$title\"$sound_clause" 2>/dev/null || true
  fi
}
