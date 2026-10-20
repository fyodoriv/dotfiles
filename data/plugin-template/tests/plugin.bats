#!/usr/bin/env bats
# Plugin self-tests. DOTFILES_CORE points at a dotfiles checkout.

setup() {
  ROOT="$BATS_TEST_DIRNAME/.."
  CORE="${DOTFILES_CORE:?set DOTFILES_CORE to a dotfiles checkout}"
}

@test "manifest matches the core schema and options" {
  run bash -c 'source "$1/lib/plugin.sh"; source "$1/lib/plugin-capabilities.sh"; source "$1/lib/plugin-extensions.sh"
    plugin_validate_manifest "$2/dotfiles-plugin.yaml" && plugin_validate_options "$2/dotfiles-plugin.yaml"' _ "$CORE" "$ROOT"
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "no exported secrets and no unpinned packages" {
  run bash -c 'source "$1/lib/plugin.sh"; source "$1/lib/plugin-capabilities.sh"; source "$1/lib/plugin-extensions.sh"
    plugin_lint "$2"' _ "$CORE" "$ROOT"
  echo "$output"
  [ "$status" -eq 0 ]
}
