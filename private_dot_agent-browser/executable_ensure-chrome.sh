#!/bin/bash
set -euo pipefail

_dotfiles_dir="${DOTFILES_DIR:-$HOME/apps/tooling/dotfiles}"
if [ -f "$_dotfiles_dir/lib/dotfiles-endpoint-paths.sh" ]; then
  # shellcheck source=../../lib/dotfiles-endpoint-paths.sh
  source "$_dotfiles_dir/lib/dotfiles-endpoint-paths.sh"
  dotfiles_prepend_endpoint_tool_paths "$_dotfiles_dir/bin"
fi
unset _dotfiles_dir

CDP_PORT=9223
LABEL="com.dotfiles.agent-browser-chrome"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"

if curl -sf --max-time 1 "http://127.0.0.1:${CDP_PORT}/json/version" >/dev/null 2>&1; then
  echo "Chrome already running on port ${CDP_PORT}"
  exit 0
fi

if [ ! -f "$PLIST" ]; then
  echo "ERROR: missing LaunchAgent plist: $PLIST" >&2
  exit 1
fi

launchctl load "$PLIST" 2>/dev/null || true
launchctl kickstart -k "gui/$(id -u)/${LABEL}" 2>/dev/null || launchctl start "$LABEL" 2>/dev/null || true

for _ in {1..20}; do
  if curl -sf --max-time 1 "http://127.0.0.1:${CDP_PORT}/json/version" >/dev/null 2>&1; then
    echo "Chrome ready on port ${CDP_PORT}"
    exit 0
  fi
  sleep 1
done

echo "ERROR: ${LABEL} did not expose CDP on port ${CDP_PORT}" >&2
exit 1
