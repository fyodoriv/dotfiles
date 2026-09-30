#!/bin/bash
# Doctor checks for chezmoi-managed symlink integrity.
#
# When the dotfiles repo is relocated (e.g. `~/apps/dotfiles` →
# `~/apps/tooling/dotfiles`) the chezmoi-managed symlinks like `~/.zshrc`,
# `~/.gitconfig`, `~/.zshenv`, `~/.tmux.conf`, etc. silently break — they
# still point at the old `~/apps/dotfiles/...` path which no longer exists.
# The shell loads its fallback defaults so the breakage is invisible until
# the operator notices missing aliases / theme / etc.
#
# This module sweeps every chezmoi-managed symlink and fails on any that
# resolve to a non-existent target. `--fix` runs `chezmoi apply
# --exclude=scripts` to repoint them, skipping the script-execution side
# effects (brew install, macos defaults, launchagent lifecycle) so a
# "just re-link" fix doesn't accidentally re-run a 30-minute setup.
#
# Edge case: chezmoi not yet on PATH (fresh install before bootstrap) —
# skip with a soft warn rather than fail.
#
# Surfaced by 2026-05-15 setup session: dotfiles moved from
# `~/apps/dotfiles` to `~/apps/tooling/dotfiles`; every managed symlink
# pointed at the gone path; manual `chezmoi apply --exclude=scripts` was
# needed to recover. No doctor check caught it.

if ! command -v chezmoi >/dev/null 2>&1; then
  # `audit_warn` is the doctor-framework helper for non-fatal advisories.
  # Skip the sweep entirely — without chezmoi we can't enumerate the
  # managed-symlink set, and any check we ran would be a false signal.
  check_advisory "chezmoi.installed" "chezmoi on PATH" \
    "command -v chezmoi >/dev/null 2>&1" \
    "Install chezmoi via Brewfile (\`brew bundle\`) or \`sh -c \"\$(curl -fsSL get.chezmoi.io)\"\`; then \`chezmoi apply\`."
  return 0
fi

# Build the broken-symlink list once via a helper so the check command
# itself can be a quick "is the list empty" test. The helper resolves
# each managed symlink via `[ -e "$path" ]` (which follows the link) —
# an entry there means the target exists; absence means broken.
_chezmoi_broken_managed_symlinks() {
  local -a broken=()
  local managed
  while IFS= read -r managed; do
    [ -z "$managed" ] && continue
    if [ -L "$managed" ] && [ ! -e "$managed" ]; then
      broken+=("$managed")
    fi
  done < <(chezmoi managed --path-style=absolute --include=symlinks 2>/dev/null)
  if [ "${#broken[@]}" -gt 0 ]; then
    printf '%s\n' "${broken[@]}"
    return 1
  fi
  return 0
}

# The summary check: pass when zero broken managed symlinks exist.
# --fix runs `chezmoi apply --exclude=scripts` so brew/macos/launchagent
# lifecycle scripts don't re-run as a side effect of a "just re-link" fix.
check "chezmoi.managed_symlinks_valid" \
  "no broken chezmoi-managed symlinks (e.g. stale repo-relocation targets)" \
  "_chezmoi_broken_managed_symlinks >/dev/null 2>&1" \
  "chezmoi apply --exclude=scripts"

# Inventory check (informational): when the sweep finds broken symlinks,
# expose the list in audit-warn output so the operator can see WHICH
# files are broken without re-running the helper. This is advisory and
# never fails on its own — the actual fail/fix happens via the check
# above. The advisory only fires when ≥1 broken symlinks exist, so
# clean states stay silent.
_chezmoi_broken_managed_symlinks_summary() {
  local list
  list="$(_chezmoi_broken_managed_symlinks 2>&1 | head -5 | tr '\n' ' ')"
  [ -z "$list" ] && return 0
  printf 'broken: %s\n' "$list" >&2
  return 1
}
check_advisory "chezmoi.managed_symlinks_inventory" \
  "list of broken managed symlinks (when any)" \
  "_chezmoi_broken_managed_symlinks_summary" \
  "Run \`chezmoi apply --exclude=scripts\` to re-link; full list above."

# Managed symlinks whose live target differs from chezmoi's target state, e.g.
# links that a tool running from another checkout of this repo repointed there.
_chezmoi_drifted_managed_symlinks() {
  local drifted
  drifted="$(chezmoi status --include=symlinks --path-style=absolute 2>/dev/null | cut -c4-)"
  if [ -n "$drifted" ]; then
    printf '%s\n' "$drifted"
    return 1
  fi
  return 0
}
check "chezmoi.managed_symlinks_current" \
  "chezmoi-managed symlinks point into chezmoi's source checkout" \
  "_chezmoi_drifted_managed_symlinks >/dev/null 2>&1" \
  "chezmoi apply --exclude=scripts"
