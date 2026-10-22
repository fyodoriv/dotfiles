#!/usr/bin/env bats
# Capability enforcement for company plugins (issue #145, step 5):
# undeclared steps are refused with exit 3 and one standard message.

load test_helper

REPO_ROOT="$BATS_TEST_DIRNAME/.."
CLI="$BATS_TEST_DIRNAME/../bin/dotfiles-plugin"

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  export MARKER="$TEST_DIR/ran"
  unset DOTFILES_PLUGINS_LOCK DOTFILES_PLUGINS_HOME \
    OSS_READINESS_ENV_FILE OSS_READINESS_INTERNAL_PATTERN DOTFILES_PUBLIC_PUSH_ALLOWLIST
  mkdir -p "$HOME" "$TEST_DIR/stub"
  printf '#!/bin/sh\nexit 1\n' > "$TEST_DIR/stub/chezmoi"
  for tool in defaults brew sudo; do
    printf '#!/bin/sh\necho "%s $*" >> "%s"\n' "$tool" "$MARKER" > "$TEST_DIR/stub/$tool"
  done
  chmod +x "$TEST_DIR/stub/"*
  export PATH="$TEST_DIR/stub:$PATH"
  PLUGIN="$TEST_DIR/dotfiles-acme"
  mkdir -p "$PLUGIN/hooks"
  printf '#!/bin/sh\ntouch "%s.hook"\n' "$MARKER" > "$PLUGIN/hooks/pre-push"
  chmod +x "$PLUGIN/hooks/pre-push"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# install_plugin <capabilities yaml>: a dev-linked plugin with those caps.
install_plugin() {
  printf 'schema: 1\nname: acme\nversion: 1.0.0\ncapabilities:\n%s\n' "$1" > "$PLUGIN/dotfiles-plugin.yaml"
  bash "$CLI" add --dev "$PLUGIN" --yes >/dev/null
}

caps() {
  bash -c 'source "$1/lib/plugin.sh"; source "$1/lib/plugin-capabilities.sh"; shift; "$@"' _ "$REPO_ROOT" "$@"
}

@test "an undeclared LaunchAgent label exits 3 with the standard message" {
  install_plugin '  launchagents: [com.acme.*]'
  run caps plugin_launchagent_check acme com.other.agent
  [ "$status" -eq 3 ]
  [ "$output" = "capability not declared: launchagents com.other.agent (plugin acme)" ]
  run caps plugin_launchagent_check acme com.acme.sync
  [ "$status" -eq 0 ]
}

@test "defaults write runs only for a declared domain" {
  install_plugin '  defaults_write: [com.acme.*]'
  run caps plugin_defaults_write acme com.apple.dock autohide -bool true
  [ "$status" -eq 3 ]
  [ ! -f "$MARKER" ]
  run caps plugin_defaults_write acme com.acme.app key -string v
  [ "$status" -eq 0 ]
  grep -qxF 'defaults write com.acme.app key -string v' "$MARKER"
}

@test "brew tap runs only for a declared tap" {
  install_plugin '  brew: {taps: [acme/private]}'
  run caps plugin_brew_tap acme other/tap
  [ "$status" -eq 3 ]
  run caps plugin_brew_tap acme acme/private
  [ "$status" -eq 0 ]
  grep -qxF 'brew tap acme/private' "$MARKER"
}

@test "sudo is refused when undeclared, and without a terminal when declared" {
  install_plugin '  sudo: false'
  run caps plugin_sudo acme true
  [ "$status" -eq 3 ]
  [[ "$output" == *"capability not declared: sudo (plugin acme)"* ]]
  bash "$CLI" remove acme --yes >/dev/null
  install_plugin '  sudo: true'
  run caps plugin_sudo acme true < /dev/null
  [ "$status" -eq 3 ]
  [ ! -f "$MARKER" ]
}

push_fixture() {
  local repo="$TEST_DIR/repo"
  git init -q "$repo"
  git init -q --bare "$repo.remote.git"
  git -C "$repo" remote add origin "$repo.remote.git"
  echo hi > "$repo/a.txt"
  git -C "$repo" add a.txt
  git -C "$repo" -c core.hooksPath=/dev/null -c user.name=t -c user.email=t@example.com commit -qm init
  git -C "$repo" -c core.hooksPath="$REPO_ROOT/git-hooks" push -q origin HEAD:refs/heads/main
}

@test "a locked plugin's undeclared hook blocks the push and never runs" {
  install_plugin '  sudo: false'
  run push_fixture
  [ "$status" -ne 0 ]
  [[ "$output" == *"capability not declared: hooks pre-push (plugin acme)"* ]]
  [ ! -f "$MARKER.hook" ]
}

@test "a locked plugin's declared hook runs during git push" {
  install_plugin '  hooks: [pre-push]'
  run push_fixture
  [ "$status" -eq 0 ]
  [ -f "$MARKER.hook" ]
}
