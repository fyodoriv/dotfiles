#!/usr/bin/env bats
# Windsurf and Devin support was removed on 2026-10-08. Augment (Auggie) stays
# deprecated and frozen (AGENTS.md § Deprecated agents): doctor skips its
# module, and the freeze rule reaches every agent through the Agentfile rules.

DOTFILES_DIR="$BATS_TEST_DIRNAME/.."

@test "windsurf and devin doctor modules are gone" {
  [ ! -e "$DOTFILES_DIR/modules/windsurf" ]
  [ ! -e "$DOTFILES_DIR/modules/devin" ]
}

@test "doctor skip logic names only augment" {
  grep -q 'augment)' "$DOTFILES_DIR/bin/dotfiles-doctor"
  ! grep -qE 'windsurf\|devin|devin\|augment' "$DOTFILES_DIR/bin/dotfiles-doctor"
  grep -q 'DOTFILES_DEPRECATED_AGENT_CHECKS' "$DOTFILES_DIR/bin/dotfiles-doctor"
}

@test "Agentfile rules carry the removal and freeze policy to every agent" {
  grep -q 'Windsurf and Devin support was removed on 2026-10-08' "$DOTFILES_DIR/Agentfile.yaml"
  grep -q 'Augment (Auggie) is deprecated and frozen' "$DOTFILES_DIR/Agentfile.yaml"
}

@test "network-watchdog executable check lives in the resilience module" {
  grep -q 'resilience.network_watchdog_exec' "$DOTFILES_DIR/modules/resilience/doctor.sh"
}
