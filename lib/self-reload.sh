#!/bin/bash
# Self-reload deferral for LaunchAgents that run the code reloading them.
#
# `dotfiles-sync` runs `chezmoi apply`, and the LaunchAgent script then
# unloads and loads com.dotfiles.dotfiles-sync. Unloading a running job kills
# it, so the rest of that sync (apply, health checks, stats) is lost.
# Instead the reloader writes a marker here and the job reloads itself after
# it has finished (bin/dotfiles-reload-launchagents --deferred).
#
# Marker scope: one empty file per label in $DOTFILES_RELOAD_MARKER_DIR
# (default ~/.local/state/dotfiles/pending-reload). One marker means one
# follow-up reload, however many times the reload is requested.
#
# self_reload_is_self LABEL   0 when this process runs inside job LABEL
# self_reload_defer LABEL     record a pending reload (idempotent)
# self_reload_pending LABEL   0 when a reload is pending
# self_reload_claim LABEL     0 for exactly one caller; removes the marker

_self_reload_dir() { printf '%s\n' "${DOTFILES_RELOAD_MARKER_DIR:-$HOME/.local/state/dotfiles/pending-reload}"; }

# launchd sets XPC_SERVICE_NAME to the job label. dotfiles-sync also exports
# DOTFILES_RELOAD_SELF_LABEL so manual runs and tests are covered.
self_reload_is_self() {
  local label="$1"
  [ "${XPC_SERVICE_NAME:-}" = "$label" ] || [ "${DOTFILES_RELOAD_SELF_LABEL:-}" = "$label" ]
}

self_reload_defer() {
  local dir; dir="$(_self_reload_dir)"
  mkdir -p "$dir" && : > "$dir/$1"
}

self_reload_pending() { [ -e "$(_self_reload_dir)/$1" ]; }

# mv is atomic: of two concurrent callers, only one wins.
self_reload_claim() {
  local dir marker; dir="$(_self_reload_dir)"; marker="$dir/$1"
  mv "$marker" "$marker.claimed.$$" 2>/dev/null || return 1
  rm -f "$marker.claimed.$$"
}
