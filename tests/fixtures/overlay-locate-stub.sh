#!/bin/bash
# Test stub — real overlay_locate is exercised in integration; bats pins
# merge wiring only.
overlay_locate() {
  if [ -n "${EXTRA_OVERLAY_ROOT:-}" ]; then
    printf '%s' "$EXTRA_OVERLAY_ROOT"
    return 0
  fi
  if [ -f "$HOME/apps/tooling/dotfiles-acme/Agentfile.yaml" ]; then
    printf '%s' "$HOME/apps/tooling/dotfiles-acme"
    return 0
  fi
  return 1
}
