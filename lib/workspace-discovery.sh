#!/bin/bash
# Workspace discovery — shared by bin/dotfiles-workspace and
# modules/workspace/doctor.sh.
#
# `workspace_discover` prints one `name<TAB>path` line per workspace.
# Resolution order (first source that exists wins):
#   1. $XDG_CONFIG_HOME/tasks-md/workspaces.json (default
#      ~/.config/tasks-md/workspaces.json) — the tasks-md CLI's shared
#      config, written by `tasks workspaces add`. Spec shape (tasks.md
#      spec.md § Workspaces): {"workspaces": [{"name": ..., "root": ...}],
#      "discovery": {...}}. Older hand-written shapes still work: an object
#      {"name": "path"} or an array [{"name": ..., "path": ...}].
#      Requires jq (guarded).
#   2. The sibling workspaces.yaml — minimal `name: path` lines
#      (comments and blanks skipped) for hand-written configs.
#   3. Fallback scan: each colon-separated root in $WORKSPACE_SCAN_ROOTS
#      (default: $HOME/apps). An immediate child dir is a workspace when
#      it contains a `.tasks-md-workspace` sentinel file OR at least two
#      immediate-child `*/TASKS.md` files.
#
# Zero workspaces is not an error: prints nothing, returns 0.
# Paths from configs support a leading `~` / `~/` (expanded to $HOME).
#
# Stays a dotfiles lib (AGENTS.md rule #0 review, docs/workspace.md):
# `tasks workspaces list` has no machine-readable output to consume yet.

# Directory that holds the tasks-md workspaces config. Same rule as the
# tasks CLI: $XDG_CONFIG_HOME when set, else ~/.config.
workspace_config_dir() {
  printf '%s/tasks-md' "${XDG_CONFIG_HOME:-$HOME/.config}"
}

_workspace_expand_tilde() {
  case "$1" in
    "~") printf '%s' "$HOME" ;;
    "~/"*) printf '%s/%s' "$HOME" "${1#\~/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

_workspace_emit() {
  # name, raw-path → one validated tab-separated line
  local name="$1" path="$2"
  [ -n "$name" ] && [ -n "$path" ] || return 0
  printf '%s\t%s\n' "$name" "$(_workspace_expand_tilde "$path")"
}

workspace_discover() {
  local cfg_dir; cfg_dir="$(workspace_config_dir)"
  local cfg_json="$cfg_dir/workspaces.json"
  local cfg_yaml="$cfg_dir/workspaces.yaml"

  if [ -f "$cfg_json" ] && command -v jq >/dev/null 2>&1; then
    local name path
    while IFS=$'\t' read -r name path; do
      _workspace_emit "$name" "$path"
    done < <(jq -r '
        if type == "object" and (.workspaces | type) == "array"
        then .workspaces[] | "\(.name // "")\t\(.root // "")"
        elif type == "array"
        then .[] | "\(.name)\t\(.path)"
        else to_entries[] | "\(.key)\t\(.value)"
        end' "$cfg_json" 2>/dev/null)
    return 0
  fi

  if [ -f "$cfg_yaml" ]; then
    local line name path
    while IFS= read -r line; do
      case "$line" in ''|\#*) continue ;; esac
      case "$line" in *:*) ;; *) continue ;; esac
      name="${line%%:*}"
      path="${line#*:}"
      # trim surrounding whitespace
      name="${name#"${name%%[![:space:]]*}"}"; name="${name%"${name##*[![:space:]]}"}"
      path="${path#"${path%%[![:space:]]*}"}"; path="${path%"${path##*[![:space:]]}"}"
      _workspace_emit "$name" "$path"
    done < "$cfg_yaml"
    return 0
  fi

  local roots="${WORKSPACE_SCAN_ROOTS:-$HOME/apps}"
  local root dir t count
  local IFS=':'
  # shellcheck disable=SC2086  # intentional word-split on colons
  set -- $roots
  unset IFS
  for root in "$@"; do
    [ -d "$root" ] || continue
    for dir in "$root"/*/; do
      [ -d "$dir" ] || continue
      dir="${dir%/}"
      if [ -f "$dir/.tasks-md-workspace" ]; then
        _workspace_emit "$(basename "$dir")" "$dir"
        continue
      fi
      count=0
      for t in "$dir"/*/TASKS.md; do
        [ -f "$t" ] || continue
        count=$((count + 1))
        [ "$count" -ge 2 ] && break
      done
      if [ "$count" -ge 2 ]; then
        _workspace_emit "$(basename "$dir")" "$dir"
      fi
    done
  done
  return 0
}
