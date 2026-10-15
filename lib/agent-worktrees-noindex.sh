#!/bin/bash
# Keep Spotlight out of the agent worktree folder.
#
# Agents create many git worktrees under ~/apps/tooling/wt, each with its own
# node_modules. Spotlight (mdworker) indexes them all and keeps the load high
# after a parallel session. A `.metadata_never_index` marker does not stop it
# on current macOS: ~/apps has one, and mdworker still indexes wt. Spotlight
# does skip a folder whose name ends in `.noindex`, and that needs no admin
# rights. So the real folder is wt.noindex, and wt is a symlink to it. Every
# path that names ~/apps/tooling/wt/<name> keeps working.
#
# agent_worktrees_dir             print the worktree folder path (the symlink)
# agent_worktrees_noindexed       0 when wt is a symlink to a *.noindex folder
# agent_worktrees_noindex_fix     make wt a symlink to wt.noindex
#
# The fix renames a real wt folder in place (an atomic rename on one volume),
# then adds the symlink. Git worktree metadata names the wt/<name> path, which
# still resolves through the symlink, so existing worktrees keep working.

agent_worktrees_dir() {
  printf '%s\n' "${DOTFILES_AGENT_WORKTREES_DIR:-${DOTFILES_REPOS_DIR:-$HOME/apps}/tooling/wt}"
}

agent_worktrees_noindexed() {
  local wt target
  wt="$(agent_worktrees_dir)"
  [ -L "$wt" ] || return 1
  target="$(readlink "$wt")"
  case "$target" in
    *.noindex | *.noindex/) [ -d "$wt" ] ;;
    *) return 1 ;;
  esac
}

agent_worktrees_noindex_fix() {
  local wt real
  wt="$(agent_worktrees_dir)"
  real="$wt.noindex"
  agent_worktrees_noindexed && return 0
  [ -d "$(dirname "$wt")" ] || return 1
  if [ -L "$wt" ]; then
    # A symlink to some other folder: leave it for a human.
    return 1
  fi
  if [ -d "$wt" ]; then
    # Never merge two real folders; a human must pick one.
    [ ! -e "$real" ] || return 1
    mv "$wt" "$real" || return 1
  elif [ -e "$wt" ]; then
    return 1
  fi
  mkdir -p "$real" || return 1
  ln -s "$(basename "$real")" "$wt"
}
