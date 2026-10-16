#!/bin/bash
# needs-e2e — decide whether a change needs the hermetic install e2e.
#
# Usage:
#   tests/e2e/needs-e2e.sh [base-ref]   check this branch + uncommitted files
#   printf '%s\n' paths | tests/e2e/needs-e2e.sh --stdin
# Prints the matching paths and exits 0 when the e2e must run; exits 1 when
# no changed path can affect the install.
set -uo pipefail

# Paths that change what `dotfiles-install` does on a new Mac, plus the
# commands the story e2e drives (stories-e2e.bats).
TRIGGERS='^(bin/dotfiles-install|bin/dotfiles-doctor|bin/morning|bin/dotfiles$|bin/dotfiles-add|bin/dotfiles-profile|bin/dotfiles-stats|bin/git-safe|lib/overlay-locate\.sh|lib/stats\.sh|modules/git/|INSTALL\.md|\.chezmoi\.yaml\.tmpl|\.chezmoiignore|\.chezmoiscripts/|tests/e2e/|launchagents/|dot_gitconfig[^/]*|symlink_dot_zsh[^/]*|home/zsh[^/]*|dot_config/|private_dot_[^/]*|modify_[^/]*)'

if [ "${1:-}" = "--stdin" ]; then
  changed="$(cat)"
else
  cd "$(git rev-parse --show-toplevel)" || exit 2
  base="$(git merge-base HEAD "${1:-origin/feat/chezmoi}" 2>/dev/null || echo HEAD)"
  changed="$({ git diff --name-only "$base"; git ls-files --others --exclude-standard; } | sort -u)"
fi
grep -E "$TRIGGERS" <<<"$changed"
