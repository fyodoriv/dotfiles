#!/bin/bash
# Test stub — real plugin_overlay_root is exercised in integration; bats pins
# merge wiring only.
plugin_overlay_root() {
  if [ -n "${EXTRA_OVERLAY_ROOT:-}" ]; then
    case "$EXTRA_OVERLAY_ROOT" in *:*) echo "ERROR: EXTRA_OVERLAY_ROOT must be a single path, not colon-separated. One overlay at a time." >&2; return 2 ;; esac
    printf '%s' "$EXTRA_OVERLAY_ROOT"
    return 0
  fi
  if [ -f "$HOME/apps/tooling/dotfiles-acme/Agentfile.yaml" ]; then
    printf '%s' "$HOME/apps/tooling/dotfiles-acme"
    return 0
  fi
  return 1
}
plugin_overlay_path() {
  local root
  [ "${1:-}" != --no-discover ] || shift
  local rc=0
  root="$(plugin_overlay_root)" || rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  printf '%s/%s' "$root" "$1"
}
