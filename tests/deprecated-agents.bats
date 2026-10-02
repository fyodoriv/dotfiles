#!/usr/bin/env bats
# Windsurf, Devin, and Augment are deprecated and frozen (AGENTS.md §
# Deprecated agents). Their doctor modules stay in the tree but are skipped,
# and the freeze rule reaches every agent through the Agentfile rules.

DOTFILES_DIR="$BATS_TEST_DIRNAME/.."

run_module() {
  local lock_dir; lock_dir="$(mktemp -d)"
  run env DOTFILES_LOCK="$lock_dir/dotfiles.lock" "$@" \
    bash "$DOTFILES_DIR/bin/dotfiles-doctor" --module "$MODULE" 2>&1
  rm -rf "$lock_dir"
}

@test "doctor skips the windsurf module as a frozen deprecated agent" {
  MODULE=windsurf run_module
  [[ "$output" == *"windsurf skipped: deprecated agent, frozen"* ]]
  [[ "$output" != *"windsurf.installed"* ]]
}

@test "doctor skips the devin module as a frozen deprecated agent" {
  MODULE=devin run_module
  [[ "$output" == *"devin skipped: deprecated agent, frozen"* ]]
}

@test "DOTFILES_DEPRECATED_AGENT_CHECKS=1 runs a frozen module for diagnosis" {
  MODULE=windsurf run_module DOTFILES_DEPRECATED_AGENT_CHECKS=1
  [[ "$output" != *"deprecated agent, frozen"* ]]
}

@test "the frozen modules keep their doctor code" {
  [ -f "$DOTFILES_DIR/modules/windsurf/doctor.sh" ]
  [ -f "$DOTFILES_DIR/modules/devin/doctor.sh" ]
}

@test "Agentfile rules carry the freeze policy to every agent" {
  grep -q 'Windsurf, Devin, and Augment (Auggie) are deprecated and frozen' "$DOTFILES_DIR/Agentfile.yaml"
}

@test "network-watchdog executable check lives outside the frozen devin module" {
  grep -q 'resilience.network_watchdog_exec' "$DOTFILES_DIR/modules/resilience/doctor.sh"
}
