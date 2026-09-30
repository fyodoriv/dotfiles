#!/bin/bash
# Locate the agentbrew checkout on this machine.
#
# Different operators clone agentbrew under different parents:
#   ~/apps/tooling/agentbrew (current monorepo-tooling layout)
#   ~/apps/agentbrew         (historical layout — many setup docs reference this)
#   $DOTFILES_REPOS_DIR/agentbrew[/tooling/agentbrew]  (custom)
#
# Without a probe, hardcoding the historical path silently breaks
# `dotfiles apply` (run_after_agentbrew-sync.sh prints "agentbrew not
# available" and skips the sync).
#
# This helper mirrors the shell-function pattern in
# home/zshrc.ai-tools (see `_dotfiles_first_existing`) so bash scripts
# and zsh shells resolve to the same checkout on every machine.
#
# Usage (sourced):
#   source "$DOTFILES_DIR/lib/agentbrew-locate.sh"
#   if agentbrew_dir=$(agentbrew_locate); then
#     ...use "$agentbrew_dir"...
#   else
#     echo "no agentbrew checkout found" >&2
#   fi
#
# Returns 0 + prints the first existing path on success; 1 on miss.

# shellcheck disable=SC2120  # callers always pass zero args; documented above
agentbrew_locate() {
  local base candidate
  # Probe DOTFILES_REPOS_DIR first when set, then fall back to ~/apps so a
  # stale test/agent temp dir does not hide the real checkout from doctor.
  for base in "${DOTFILES_REPOS_DIR:-}" "$HOME/apps"; do
    [ -n "$base" ] || continue
    for candidate in \
      "$base/tooling/agentbrew" \
      "$base/agentbrew"
    do
      [ -d "$candidate" ] && { printf '%s' "$candidate"; return 0; }
    done
  done
  return 1
}
