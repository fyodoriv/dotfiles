#!/usr/bin/env bats
# Ensures dotfiles/lib/strip-agent-attribution.sh stays in sync with the
# agentbrew deploy copy (AGENTS.md § Hook-based enforcement).

DOTFILES_LIB="$BATS_TEST_DIRNAME/../lib/strip-agent-attribution.sh"
AGENTBREW_LIB="${DOTFILES_AGENTBREW_STRIP_LIB:-$BATS_TEST_DIRNAME/../../agentbrew/hooks/lib/strip-agent-attribution.sh}"

_normalize_strip_lib() {
  # Shebang differs by design (/bin/sh vs /usr/bin/env sh); compare logic only.
  tail -n +2 "$1" | sed '/^[[:space:]]*$/d'
}

@test "strip-agent-attribution: agentbrew copy matches dotfiles lib (logic)" {
  [ -f "$DOTFILES_LIB" ] || skip "dotfiles lib missing"
  [ -f "$AGENTBREW_LIB" ] || skip "agentbrew checkout not present at $AGENTBREW_LIB"

  dotfiles_norm="$BATS_TEST_TMPDIR/dotfiles-strip.norm"
  agentbrew_norm="$BATS_TEST_TMPDIR/agentbrew-strip.norm"
  _normalize_strip_lib "$DOTFILES_LIB" > "$dotfiles_norm"
  _normalize_strip_lib "$AGENTBREW_LIB" > "$agentbrew_norm"

  diff -u "$dotfiles_norm" "$agentbrew_norm"
}
