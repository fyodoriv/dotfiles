#!/bin/bash
# snapshot.sh — Capture current macOS defaults before overwriting them.
#
# Usage:
#   snapshot.sh --macos          Snapshot all domains modified by macos*.sh
#   snapshot.sh --list           List existing snapshots
#   snapshot.sh --diff <file>    Diff a snapshot against current defaults
#
# Snapshots are stored in ~/.dotfiles-snapshots/ with timestamps.

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/colors.sh
source "$DOTFILES_DIR/lib/colors.sh"

SNAPSHOT_DIR="$HOME/.dotfiles-snapshots"

# Domains modified by macos.sh, macos-visual.sh, and macos-apps.sh
MACOS_DOMAINS=(
  NSGlobalDomain
  com.apple.ActivityMonitor
  com.apple.AppleMultitouchTrackpad
  com.apple.appstore
  com.apple.assistant.support
  com.apple.CrashReporter
  com.apple.desktopservices
  com.apple.DiskUtility
  com.apple.dock
  com.apple.driver.AppleBluetoothMultitouch.trackpad
  com.apple.finder
  com.apple.LaunchServices
  com.apple.menuextra.battery
  com.apple.menuextra.clock
  com.apple.ncprefs
  com.apple.print.PrintingPrefs
  com.apple.Safari
  com.apple.screencapture
  com.apple.screensaver
  com.apple.Siri
  com.apple.spaces
  com.apple.SubmitDiagInfo
  com.apple.Terminal
  com.apple.TextEdit
  com.apple.TimeMachine
  com.apple.universalaccess
  com.apple.WindowManager
)

snapshot_macos() {
  mkdir -p "$SNAPSHOT_DIR"
  local timestamp
  timestamp="$(date +%Y%m%d-%H%M%S)"
  local outfile="$SNAPSHOT_DIR/macos-$timestamp.txt"

  info "Snapshotting macOS defaults to $outfile"

  for domain in "${MACOS_DOMAINS[@]}"; do
    echo "=== $domain ===" >> "$outfile"
    defaults read "$domain" 2>/dev/null >> "$outfile" || echo "(not set)" >> "$outfile"
    echo "" >> "$outfile"
  done

  ok "Snapshot saved: $outfile ($(wc -l < "$outfile" | tr -d ' ') lines)"
}

list_snapshots() {
  if [ ! -d "$SNAPSHOT_DIR" ] || [ -z "$(ls -A "$SNAPSHOT_DIR" 2>/dev/null)" ]; then
    info "No snapshots found in $SNAPSHOT_DIR"
    return
  fi
  info "Snapshots in $SNAPSHOT_DIR:"
  ls -lh "$SNAPSHOT_DIR"/*.txt 2>/dev/null | awk '{print "  " $NF " (" $5 ")"}'
}

diff_snapshot() {
  local snapshot_file="$1"
  if [ ! -f "$snapshot_file" ]; then
    fail "Snapshot file not found: $snapshot_file"
    exit 1
  fi

  DIFF_TMPFILE="$(mktemp)" || { fail "mktemp failed"; exit 1; }
  trap 'rm -f "$DIFF_TMPFILE"' EXIT

  for domain in "${MACOS_DOMAINS[@]}"; do
    echo "=== $domain ===" >> "$DIFF_TMPFILE"
    defaults read "$domain" 2>/dev/null >> "$DIFF_TMPFILE" || echo "(not set)" >> "$DIFF_TMPFILE"
    echo "" >> "$DIFF_TMPFILE"
  done

  diff --unified "$snapshot_file" "$DIFF_TMPFILE" || true
}

case "${1:-}" in
  --macos)  snapshot_macos ;;
  --list)   list_snapshots ;;
  --diff)
    if [ -z "${2:-}" ]; then
      fail "Usage: snapshot.sh --diff <snapshot-file>"
      exit 1
    fi
    diff_snapshot "$2"
    ;;
  *)
    echo "Usage: snapshot.sh --macos | --list | --diff <file>"
    exit 1
    ;;
esac
