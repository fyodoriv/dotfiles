#!/bin/bash
# Doctor checks for the personal-machine setup — verifies the one-time setup
# of a personal Mac is intact.
#
# Surfaced 2026-05-15: on a fresh boot of the personal machine, `git config
# --global user.email` was unset and the tooling repos weren't cloned — with
# no automated detection, no doctor check, and no recovery hint. The operator
# only noticed when a `git commit` failed and spent 15 minutes re-discovering
# the setup steps.
#
# What this module guards:
#   1. Global git identity is the personal one (NOT @company.example, NOT blank).
#   2. The tooling repos are cloned at the canonical paths with the expected
#      GitHub.com remote URL and current branch.
#
# Profile gate: this module is PERSONAL-MACHINE ONLY (skips when
# is_enterprise=true). On corporate Macs the global git identity is
# @company.example by org policy — running these checks there produces
# false alarms.
if [ "${IS_ENTERPRISE:-false}" = "true" ]; then
  # shellcheck disable=SC2317  # return when sourced; exit when executed directly
  return 0 2>/dev/null || exit 0
fi

# ── (1) Global git identity ──────────────────────────────────────────
# The personal-machine setup hardcodes "fyodor@sent.com". This is a public
# email and only relevant on the operator's own personal machine — so it
# lives in this dotfiles repo, not as a generic project rule.
_global_email_is_personal() {
  local email
  # --includes follows ~/.gitconfig's [include] of ~/.gitconfig.local.
  email="$(git config --global --includes user.email 2>/dev/null || true)"
  [ -n "$email" ] && [ "$email" = "fyodor@sent.com" ]
}
# Fix writes ~/.gitconfig.local: ~/.gitconfig is chezmoi-managed, and a
# write there is drift that blocks the next non-TTY `chezmoi apply`.
check "personal-machine.global_email" \
  "global git user.email is 'fyodor@sent.com' (NOT @company.example, NOT blank)" \
  "_global_email_is_personal" \
  "git config --file ~/.gitconfig.local user.email 'fyodor@sent.com'"

# ── (2-3) Tooling repos cloned with expected remote + branch ─────────
# Each check verifies the repo dir is a git checkout AND the `origin`
# remote URL contains the expected fyodoriv repo path AND the current
# branch matches the repo's canonical branch.
#
# The URL check uses substring match (grep) rather than exact equality
# because `git clone` may store either the SSH form
# (git@github.com:fyodoriv/<repo>.git) or HTTPS form
# (https://github.com/fyodoriv/<repo>.git) depending on which clone
# command the operator ran — both are valid; the only thing we care
# about is that origin points at the fyodoriv repo, not @company.example
# or anywhere else.
_repo_matches() {
  local repo_dir="$1" expected_path="$2" expected_branch="$3"
  [ -d "$repo_dir/.git" ] || return 1
  local origin_url current_branch
  origin_url="$(git -C "$repo_dir" remote get-url origin 2>/dev/null || true)"
  [ -n "$origin_url" ] && printf '%s' "$origin_url" | grep -q "$expected_path" || return 1
  current_branch="$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  [ "$current_branch" = "$expected_branch" ]
}

check "personal-machine.dotfiles_clone" \
  '$HOME/apps/tooling/dotfiles is a git checkout of fyodoriv/dotfiles on feat/chezmoi' \
  "_repo_matches \"\$HOME/apps/tooling/dotfiles\" \"fyodoriv/dotfiles\" feat/chezmoi" \
  "mkdir -p \$HOME/apps/tooling && git clone git@github.com:fyodoriv/dotfiles.git \$HOME/apps/tooling/dotfiles && cd \$HOME/apps/tooling/dotfiles && git checkout feat/chezmoi"

check "personal-machine.agentbrew_clone" \
  '$HOME/apps/tooling/agentbrew is a git checkout of fyodoriv/agentbrew on main' \
  "_repo_matches \"\$HOME/apps/tooling/agentbrew\" \"fyodoriv/agentbrew\" main" \
  "mkdir -p \$HOME/apps/tooling && git clone git@github.com:fyodoriv/agentbrew.git \$HOME/apps/tooling/agentbrew"

