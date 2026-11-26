#!/bin/bash
# Last-apply record: lets `dotfiles apply --if-changed` skip a full
# `chezmoi apply` when nothing changed since the last successful one.
# Usage: source "$DOTFILES_DIR/lib/apply-state.sh"
#
# apply_state_clear             before a full apply: remove the record
# apply_state_fingerprint <source> before a full apply: read its inputs
# apply_state_record <source> <before> after success: record only unchanged
#                               inputs (a dirty source removes the record)
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
# lib/agentfile-layers.sh). Verified plugins can register mutable
# per-user Agentfile layers as well.
apply_state_fingerprint() {
  local source head lock
  source="$(cd "$1" 2>/dev/null && pwd -P)" || return 1
  head="$(git -C "$source" rev-parse HEAD 2>/dev/null)" || return 1
  printf 'source %s\n' "$source"
  printf 'head %s\n' "$head"
  printf 'config %s\n' "$(_apply_state_hash "${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi/chezmoi.yaml")"
  lock="${DOTFILES_PLUGINS_LOCK:-${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/plugins.lock}"
  printf 'plugins %s\n' "$(_apply_state_hash "$lock")"
  printf 'local_agentfile %s\n' "$(_apply_state_hash "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/Agentfile.local.yaml")"
  if [ -f "$lock" ]; then
    _apply_state_plugin_agentfiles "$source"
  fi
}

_apply_state_plugin_agentfiles() (
  set -o pipefail
  local source="$1" name path fingerprint pairs
  command -v yq >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || return 1
  # shellcheck source=/dev/null
  source "$source/lib/plugin.sh"
  # shellcheck source=/dev/null
  source "$source/lib/plugin-extensions.sh"
  pairs="$(plugin_agentfile_pairs registered)" || return 1
  [ -n "$pairs" ] || return 0
  while IFS=$'\t' read -r name path; do
    [ -f "$path" ] || return 1
    fingerprint="$(_apply_state_hash "$path")" || return 1
    printf 'plugin_agentfile %s\t%s\t%s\n' "$name" "$path" "$fingerprint"
  done <<< "$pairs"
)

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
  local file fingerprint before="${2:-}"
  file="$(apply_state_file)"
  # An input may change after its apply step read it. A later sample
  # alone cannot establish which bytes were applied.
  if [ -z "$before" ] || ! _apply_state_source_clean "$1" ||
     ! fingerprint="$(apply_state_fingerprint "$1")" || [ "$before" != "$fingerprint" ]; then
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
