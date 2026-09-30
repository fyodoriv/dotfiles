#!/bin/bash
# Resolve the checkout that home links must point into: chezmoi's source.
# Tools can run from another checkout of this repo, such as a development
# clone, and must not relink $HOME to it.

# Print chezmoi's configured source dir. Return non-zero when it is unavailable.
dotfiles_applied_root() {
  local source_dir=""
  if command -v chezmoi >/dev/null 2>&1; then
    source_dir="$(chezmoi source-path 2>/dev/null || true)"
  fi
  if [ -n "$source_dir" ] && [ -d "$source_dir" ]; then
    (cd "$source_dir" && pwd -P)
  else
    return 1
  fi
}

# Print chezmoi's source dir, or $1 when chezmoi has no usable source dir.
dotfiles_link_root() {
  local fallback="$1"
  dotfiles_applied_root || printf '%s\n' "$fallback"
}

# Return success only when $1 is chezmoi's configured source checkout.
# LaunchAgent mutations must be made from this applied checkout, not from a
# development checkout or a linked Git worktree.
dotfiles_is_applied_checkout() {
  local running="$1" applied_root=""
  applied_root="$(dotfiles_applied_root)" || return 1
  [ "$(cd "$running" && pwd -P)" = "$(cd "$applied_root" && pwd -P)" ]
}

# Move a link target under the running checkout ($1) to the same path under
# the link root ($2). Other targets ($3) pass through unchanged.
dotfiles_link_target() {
  local running="$1" link_root="$2" src="$3"
  case "$src" in
    "$running"/*) printf '%s\n' "$link_root/${src#"$running"/}" ;;
    *) printf '%s\n' "$src" ;;
  esac
}
