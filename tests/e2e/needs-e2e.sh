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
# Plus every lib the e2e commands load, two levels deep, so a change to a lib
# the doctor or morning sources (lib/output.sh, ...) runs the story e2e too.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
E2E_CMDS="bin/dotfiles-install bin/dotfiles-doctor bin/morning bin/dotfiles bin/dotfiles-add bin/dotfiles-profile bin/dotfiles-stats bin/git-safe"
libs_of() { (cd "$root" && grep -ohE 'lib/[A-Za-z0-9_.-]+\.(sh|awk|py)' "$@" 2>/dev/null | sort -u); }
# shellcheck disable=SC2086 # word-split the command and lib lists on purpose
first="$(libs_of $E2E_CMDS)"
# shellcheck disable=SC2086
libs="$( { printf '%s\n' "$first"; [ -n "$first" ] && libs_of $first; } | grep . | sort -u)"

{ grep -E "$TRIGGERS" <<<"$changed" || true; grep -xF -f <(printf '%s\n' "$libs") <<<"$changed" || true; } | sort -u | grep .
