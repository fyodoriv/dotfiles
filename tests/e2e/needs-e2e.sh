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
TRIGGERS='^(bin/dotfiles-install|bin/dotfiles-doctor|bin/morning|bin/dotfiles$|bin/dotfiles-add|bin/dotfiles-profile|bin/dotfiles-stats|bin/git-safe|lib/plugin\.sh|lib/stats\.sh|data/|modules/git/|modules/shell/|modules/sync/|INSTALL\.md|\.chezmoi\.yaml\.tmpl|\.chezmoiignore|\.chezmoiscripts/|tests/e2e/|launchagents/|dot_gitconfig[^/]*|symlink_dot_zsh[^/]*|home/zsh[^/]*|dot_config/|private_dot_[^/]*|modify_[^/]*)'

if [ "${1:-}" = "--stdin" ]; then
  changed="$(cat)"
else
  cd "$(git rev-parse --show-toplevel)" || exit 2
  base="$(git merge-base HEAD "${1:-origin/feat/chezmoi}" 2>/dev/null || echo HEAD)"
  changed="$({ git diff --name-only "$base"; git ls-files --others --exclude-standard; } | sort -u)"
fi
# Plus every lib that the e2e runs, two levels deep: libs sourced by the e2e
# commands, by the doctor modules the e2e checks (git, shell, sync), and by
# the chezmoi lifecycle scripts the install runs.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
E2E_CMDS="bin/dotfiles-install bin/dotfiles-doctor bin/dotfiles-heal-stuck-agents bin/morning bin/dotfiles bin/dotfiles-add bin/dotfiles-profile bin/dotfiles-stats bin/git-safe"
libs_of() { (cd "$root" && grep -ohE 'lib/[A-Za-z0-9_.-]+\.(sh|awk|py)' "$@" 2>/dev/null | sort -u); }
# Repo files the lifecycle scripts run ({{ .chezmoi.sourceDir }}/macos.sh,
# $DOTFILES_DIR/bin/x, ...) are part of the install too: they trigger the e2e
# and their libs are scanned.
# Not an input: run_after_agentbrew-sync.sh reads Agentfile.yaml only after
# it finds agentbrew, and the hermetic HOME has none (the e2e also passes
# --no-agentbrew; tests/chezmoiscripts.bats covers the skip). So an
# Agentfile-only change does not need the e2e (tests/install-e2e-guard.bats).
NOT_INPUTS='^Agentfile\.yaml$'
targets="$(cd "$root" && grep -ohE '(\.chezmoi\.sourceDir \}\}|\$\{?(DOTFILES_DIR|CHEZMOI_SOURCE_DIR)\}?)/[A-Za-z0-9_./-]+' .chezmoiscripts/* 2>/dev/null |
  sed -E 's#^(\.chezmoi\.sourceDir \}\}|\$\{?(DOTFILES_DIR|CHEZMOI_SOURCE_DIR)\}?)/##; s#/$##' | sort -u | grep -vE "$NOT_INPUTS" |
  while IFS= read -r t; do [ -f "$t" ] && printf '%s\n' "$t"; done)"
E2E_SOURCES="$E2E_CMDS modules/git/doctor.sh modules/shell/doctor.sh modules/sync/doctor.sh $(cd "$root" && ls .chezmoiscripts/* 2>/dev/null | tr '\n' ' ') $(printf '%s ' $targets)"
# shellcheck disable=SC2086 # word-split the command and lib lists on purpose
first="$(libs_of $E2E_SOURCES)"
# shellcheck disable=SC2086
libs="$( { printf '%s\n' "$first" "$targets"; [ -n "$first" ] && libs_of $first; } | grep . | sort -u)"

{ grep -E "$TRIGGERS" <<<"$changed" || true; grep -xF -f <(printf '%s\n' "$libs") <<<"$changed" || true; } | sort -u | grep .
