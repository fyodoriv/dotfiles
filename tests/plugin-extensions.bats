#!/usr/bin/env bats
# Typed extension points for company plugins (issue #145, step 6).

load test_helper

REPO_ROOT="$BATS_TEST_DIRNAME/.."
CLI="$BATS_TEST_DIRNAME/../bin/dotfiles-plugin"

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  export DOTFILES_PLUGINS_V2=1
  export MARKER="$TEST_DIR/ran"
  unset EXTRA_OVERLAY_ROOT DOTFILES_PLUGINS_LOCK DOTFILES_PLUGINS_HOME
  mkdir -p "$HOME" "$TEST_DIR/stub"
  printf '#!/bin/sh\nexit 1\n' > "$TEST_DIR/stub/chezmoi"
  printf '#!/bin/sh\necho "brew $*" >> "%s"\n[ -z "${BREW_FAIL:-}" ]\n' "$MARKER" > "$TEST_DIR/stub/brew"
  chmod +x "$TEST_DIR/stub/"*
  export PATH="$TEST_DIR/stub:$PATH"
  PLUGIN="$TEST_DIR/dotfiles-acme"
  mkdir -p "$PLUGIN"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# install_plugin <capabilities yaml> <contributes yaml>
install_plugin() {
  printf 'schema: 1\nname: acme\nversion: 1.0.0\ncapabilities:\n%s\ncontributes:\n%s\n' "$1" "$2" \
    > "$PLUGIN/dotfiles-plugin.yaml"
  bash "$CLI" add --dev "$PLUGIN" --yes >/dev/null
}

ext() {
  bash -c 'for f in plugin plugin-capabilities plugin-extensions; do source "$1/lib/$f.sh"; done; shift; "$@"' \
    _ "$REPO_ROOT" "$@"
}

@test "6a: a declared plugin Brewfile gets its own brew bundle pass" {
  printf 'tap "acme/private"\ncask "acme-app"\nbrew "jq"\n' > "$PLUGIN/Brewfile"
  install_plugin '  brew: {taps: [acme/private], casks: true}' '  brewfile: Brewfile'
  run ext plugin_brew_pass
  [ "$status" -eq 0 ]
  grep -qE "^brew bundle --no-upgrade --file=.*/dotfiles-acme/Brewfile$" "$MARKER"
}

@test "6a: an undeclared tap refuses the plugin Brewfile" {
  printf 'tap "other/tap"\n' > "$PLUGIN/Brewfile"
  install_plugin '  brew: {taps: [acme/private]}' '  brewfile: Brewfile'
  run ext plugin_brew_pass
  [ "$status" -ne 0 ]
  [[ "$output" == *"capability not declared: brew_tap other/tap (plugin acme)"* ]]
  [ ! -f "$MARKER" ]
}

@test "6a: casks need capabilities.brew.casks" {
  printf 'cask "acme-app"\n' > "$PLUGIN/Brewfile"
  install_plugin '  sudo: false' '  brewfile: Brewfile'
  run ext plugin_brew_pass
  [ "$status" -ne 0 ]
  [[ "$output" == *"capability not declared: brew_cask"* ]]
}

@test "6a: a failed bundle is reported as unreachable, not a silent pass" {
  printf 'brew "jq"\n' > "$PLUGIN/Brewfile"
  install_plugin '  sudo: false' '  brewfile: Brewfile'
  BREW_FAIL=1 run ext plugin_brew_pass
  [ "$status" -ne 0 ]
  [[ "$output" == *"unreachable (plugin acme)"* ]]
}

@test "6a: a plugin that fails verification is skipped" {
  printf 'brew "jq"\n' > "$PLUGIN/Brewfile"
  install_plugin '  sudo: false' '  brewfile: Brewfile'
  printf '  sudo: true\n' >> "$PLUGIN/dotfiles-plugin.yaml"
  sed -i.bak '/^  sudo: false$/d' "$PLUGIN/dotfiles-plugin.yaml" && rm -f "$PLUGIN/dotfiles-plugin.yaml.bak"
  run ext plugin_brew_pass
  [[ "$output" == *"skipped plugin acme"* ]]
  [ ! -f "$MARKER" ]
}
