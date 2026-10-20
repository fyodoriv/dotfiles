#!/bin/bash
# The one overlay ("plugin") lookup for the whole core (issue #145, step 3).
# Every caller (doctor, validate, brew, vscode, agentbrew, oss-readiness,
# agentbrew sync) uses these functions. Do not copy the lookup inline.
#
# Resolution order:
#   1. $EXTRA_OVERLAY_ROOT (explicit env — highest priority)
#   2. chezmoi data key `extra_overlay_root`
#   3. Auto-discover dotfiles-* overlay repos at common clone layouts when
#      Agentfile.yaml exists, excluding checkouts with the base repo's origin.
#      Known gap S3: a later step replaces this with plugins.lock.
#
# Usage (sourced):
#   source "$DOTFILES_DIR/lib/plugin.sh"
#   if root="$(plugin_overlay_root)"; then ...; fi
#   file="$(plugin_overlay_path Agentfile.yaml)"
#
# --no-discover (first argument of either function) skips step 3. Callers
# that never auto-discovered (vscode, brew, validate) pass it, so this
# refactor does not widen gap S3.
#
# plugin_overlay_root prints the path and returns 0, returns 1 when there is
# no overlay, and returns 2 (with a message on stderr) for a colon-separated
# list, because only one overlay is allowed.

_plugin_is_source_replica() {
  local candidate="$1" base_dir candidate_dir base_origin candidate_origin
  [ -n "${DOTFILES_DIR:-}" ] || return 1
  [ -d "$DOTFILES_DIR" ] || return 1

  base_dir="$(cd "$DOTFILES_DIR" 2>/dev/null && pwd -P)" || return 1
  candidate_dir="$(cd "$candidate" 2>/dev/null && pwd -P)" || return 1
  [ "$candidate_dir" = "$base_dir" ] && return 0

  command -v git >/dev/null 2>&1 || return 1
  base_origin="$(git -C "$base_dir" remote get-url origin 2>/dev/null || true)"
  candidate_origin="$(git -C "$candidate_dir" remote get-url origin 2>/dev/null || true)"
  [ -n "$base_origin" ] && [ "$base_origin" = "$candidate_origin" ]
}

_plugin_find_overlay_root() {
  local discover="${1:-1}" configured repos_dir search_parent agentfile candidate

  if [ -n "${EXTRA_OVERLAY_ROOT:-}" ]; then
    printf '%s' "$EXTRA_OVERLAY_ROOT"
    return 0
  fi

  if command -v chezmoi &>/dev/null; then
    configured="$(
      chezmoi execute-template '{{ dig "extra_overlay_root" "" . }}' 2>/dev/null || true
    )"
    if [ -n "$configured" ] && [ -d "$configured" ]; then
      printf '%s' "$configured"
      return 0
    fi
    [ "$discover" -eq 1 ] || return 1
    repos_dir="$(
      chezmoi execute-template '{{ dig "repos_dir" "apps" . }}' 2>/dev/null || echo "apps"
    )"
  else
    [ "$discover" -eq 1 ] || return 1
    repos_dir="${DOTFILES_REPOS_DIR:-apps}"
    repos_dir="${repos_dir##*/}"
    [ -n "$repos_dir" ] || repos_dir="apps"
  fi

  for search_parent in \
    "${DOTFILES_REPOS_DIR:-$HOME/$repos_dir}/tooling" \
    "$HOME/$repos_dir/tooling" \
    "$HOME/$repos_dir" \
    "$HOME/apps/tooling" \
    "$HOME/apps"
  do
    [ -d "$search_parent" ] || continue
    for agentfile in "$search_parent"/dotfiles-*/Agentfile.yaml; do
      [ -f "$agentfile" ] || continue
      candidate="$(dirname "$agentfile")"
      # A deployed source checkout or feature worktree also has Agentfile.yaml.
      # It is not an additive overlay; loading it duplicates every base module.
      _plugin_is_source_replica "$candidate" && continue
      printf '%s' "$candidate"
      return 0
    done
  done
  return 1
}

plugin_overlay_root() {
  local root discover=1
  [ "${1:-}" != --no-discover ] || discover=0
  root="$(_plugin_find_overlay_root "$discover")" || return 1
  if [[ "$root" == *:* ]]; then
    echo "ERROR: EXTRA_OVERLAY_ROOT must be a single path, not colon-separated. One overlay at a time. — fix: set EXTRA_OVERLAY_ROOT to one path" >&2
    return 2
  fi
  printf '%s' "$root"
}

# Prints <overlay root>/<relative path> when an overlay exists. Same return
# codes as plugin_overlay_root. The path may not exist; callers check.
plugin_overlay_path() {
  local root rc=0 flag=""
  if [ "${1:-}" = --no-discover ]; then flag=--no-discover; shift; fi
  root="$(plugin_overlay_root $flag)" || rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  printf '%s/%s' "$root" "$1"
}
