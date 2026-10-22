#!/bin/bash
# Last-apply record: lets `dotfiles apply --if-changed` skip a full
# `chezmoi apply` when nothing changed since the last successful one.
# Usage: source "$DOTFILES_DIR/lib/apply-state.sh"
#
# apply_state_clear             before a full apply: remove the record
# apply_state_record <source>   after a successful full apply: store the
#                               fingerprint (a dirty source removes it)
# apply_state_current <source>  0 when the stored fingerprint matches and the
#                               source checkout has no uncommitted change
# apply_state_drift <source>    print `chezmoi status` drift lines, without
#                               the scripts that run on every apply;
#                               0 = drift, 1 = no drift, 2 = status failed
#
# State owner: this module. Scope: one file per user account,
# ${XDG_STATE_HOME:-~/.local/state}/dotfiles/last-apply. A full apply removes
# it first and writes it back only on success from a clean source. A missing
# file means "do the full apply"; delete it to force one.

apply_state_file() {
  printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/last-apply"
}

# SHA-256 of a file, or "none" when it does not exist.
_apply_state_hash() {
  if [ -f "$1" ]; then
    shasum -a 256 "$1" 2>/dev/null | awk '{ print $1 }'
  else
    echo none
  fi
}

# What a full apply reads besides the target files: the source path and
# commit, the chezmoi config (template data), the pinned plugins (same
# default path as plugin_lock_file in lib/plugin.sh), and this Mac's local
# Agentfile layer (same path as agentfile_local_layer_path in
# lib/agentfile-layers.sh).
apply_state_fingerprint() {
  local source head
  source="$(cd "$1" 2>/dev/null && pwd -P)" || return 1
  head="$(git -C "$source" rev-parse HEAD 2>/dev/null)" || return 1
  printf 'source %s\n' "$source"
  printf 'head %s\n' "$head"
  printf 'config %s\n' "$(_apply_state_hash "${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi/chezmoi.yaml")"
  printf 'plugins %s\n' "$(_apply_state_hash "${DOTFILES_PLUGINS_LOCK:-${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/plugins.lock}")"
  printf 'local_agentfile %s\n' "$(_apply_state_hash "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/Agentfile.local.yaml")"
}

# 0 when the source checkout has no tracked or untracked change.
_apply_state_source_clean() {
  local out
  out="$(git -C "$1" status --porcelain 2>/dev/null)" || return 1
  [ -z "$out" ]
}

apply_state_clear() {
  rm -f "$(apply_state_file)"
}

apply_state_record() {
  local file fingerprint
  file="$(apply_state_file)"
  # An apply from uncommitted files is not described by a commit.
  if ! _apply_state_source_clean "$1" || ! fingerprint="$(apply_state_fingerprint "$1")"; then
    rm -f "$file"
    return 0
  fi
  mkdir -p "$(dirname "$file")" 2>/dev/null || return 0
  if printf '%s\n' "$fingerprint" > "$file.$$" 2>/dev/null; then
    mv -f "$file.$$" "$file" 2>/dev/null || rm -f "$file.$$"
  fi
  return 0
}

apply_state_current() {
  local file want
  file="$(apply_state_file)"
  [ -r "$file" ] || return 1
  _apply_state_source_clean "$1" || return 1
  want="$(apply_state_fingerprint "$1")" || return 1
  [ "$(cat "$file")" = "$want" ]
}

apply_state_drift() {
  local out
  # --exclude=always leaves out the run_ scripts that run on every apply; a
  # changed run_onchange_ or a pending run_once_ script still shows as R.
  out="$(chezmoi status --source "$1" --exclude=always 2>/dev/null)" || return 2
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}
