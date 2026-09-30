#!/bin/bash
# Locate the company overlay root (e.g. dotfiles-<org>) on this machine.
#
# Resolution order:
#   1. $EXTRA_OVERLAY_ROOT (explicit env — highest priority)
#   2. chezmoi data key `extra_overlay_root`
#   3. Auto-discover dotfiles-* overlay repos at common clone layouts when
#      Agentfile.yaml exists, excluding checkouts with the base repo's origin
#      (fixes missing chezmoi data without treating source worktrees as overlays)
#
# Usage (sourced):
#   source "$DOTFILES_DIR/lib/overlay-locate.sh"
#   if overlay_root=$(overlay_locate); then
#     ...use "$overlay_root"...
#   fi
#
# Returns 0 + prints the path on success; 1 on miss.

_overlay_is_dotfiles_source_replica() {
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

overlay_locate() {
  local configured repos_dir search_parent agentfile candidate

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
    repos_dir="$(
      chezmoi execute-template '{{ dig "repos_dir" "apps" . }}' 2>/dev/null || echo "apps"
    )"
  else
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
      _overlay_is_dotfiles_source_replica "$candidate" && continue
      printf '%s' "$candidate"
      return 0
    done
  done
  return 1
}
