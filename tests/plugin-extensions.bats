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
  printf '#!/bin/sh\necho "launchctl $*" >> "%s"\n' "$MARKER" > "$TEST_DIR/stub/launchctl"
  export DOTFILES_LAUNCHAGENTS_DIR="$TEST_DIR/LaunchAgents" XDG_STATE_HOME="$HOME/.local/state"
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

plist() {
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$1</string>
<key>ProgramArguments</key><array><string>@PLUGIN_DIR@/bin/run</string><string>@HOME@</string></array>
</dict></plist>
PLIST
}

@test "6b: a declared LaunchAgent template is rendered, installed and loaded" {
  mkdir -p "$PLUGIN/launchagents"
  plist com.acme.sync > "$PLUGIN/launchagents/sync.plist"
  install_plugin '  launchagents: [com.acme.*]' '  launchagents: launchagents'
  run ext plugin_launchagents_pass
  [ "$status" -eq 0 ]
  dest="$DOTFILES_LAUNCHAGENTS_DIR/com.acme.sync.plist"
  [ -f "$dest" ]
  grep -q "<string>$HOME</string>" "$dest"
  grep -q "dotfiles-acme/bin/run" "$dest"
  ! grep -q '@HOME@\|@PLUGIN_DIR@' "$dest"
  grep -q "launchctl bootstrap gui/" "$MARKER"
}

@test "6b: an undeclared Label is refused and not installed" {
  mkdir -p "$PLUGIN/launchagents"
  plist com.other.agent > "$PLUGIN/launchagents/x.plist"
  install_plugin '  launchagents: [com.acme.*]' '  launchagents: launchagents'
  run ext plugin_launchagents_pass
  [ "$status" -ne 0 ]
  [[ "$output" == *"capability not declared: launchagents com.other.agent (plugin acme)"* ]]
  [ ! -e "$DOTFILES_LAUNCHAGENTS_DIR/com.other.agent.plist" ]
}

@test "6b: an unchanged agent is not reloaded" {
  mkdir -p "$PLUGIN/launchagents"
  plist com.acme.sync > "$PLUGIN/launchagents/sync.plist"
  install_plugin '  launchagents: [com.acme.*]' '  launchagents: launchagents'
  ext plugin_launchagents_pass
  rm -f "$MARKER"
  run ext plugin_launchagents_pass
  [ "$status" -eq 0 ]
  [ ! -f "$MARKER" ]
}

@test "6b: plugin remove unloads and deletes its LaunchAgents" {
  mkdir -p "$PLUGIN/launchagents"
  plist com.acme.sync > "$PLUGIN/launchagents/sync.plist"
  install_plugin '  launchagents: [com.acme.*]' '  launchagents: launchagents'
  ext plugin_launchagents_pass
  run bash "$CLI" remove acme
  [ "$status" -eq 0 ]
  [ ! -e "$DOTFILES_LAUNCHAGENTS_DIR/com.acme.sync.plist" ]
  grep -q "launchctl bootout gui/.*/com.acme.sync" "$MARKER"
}

@test "6d: a declared shell fragment is sourced by the generated loader" {
  mkdir -p "$PLUGIN/shell"
  printf 'export ACME_FRAGMENT=loaded\n' > "$PLUGIN/shell/zshrc.zsh"
  install_plugin '  shell_fragment: true' '  shell: shell/zshrc.zsh'
  run ext plugin_shell_pass
  [ "$status" -eq 0 ]
  loader="$XDG_STATE_HOME/dotfiles/plugin-shell.zsh"
  run zsh -fc "source '$loader'; print -r -- \$ACME_FRAGMENT"
  [ "$output" = loaded ]
}

@test "6d: an undeclared shell fragment is left out" {
  mkdir -p "$PLUGIN/shell"
  printf 'touch "%s"\n' "$MARKER" > "$PLUGIN/shell/zshrc.zsh"
  install_plugin '  sudo: false' '  shell: shell/zshrc.zsh'
  run ext plugin_shell_pass
  [ "$status" -ne 0 ]
  [[ "$output" == *"capability not declared: shell_fragment (plugin acme)"* ]]
  ! grep -q zshrc.zsh "$XDG_STATE_HOME/dotfiles/plugin-shell.zsh"
}

@test "6d: plugin add and remove refresh the loader" {
  mkdir -p "$PLUGIN/shell"
  printf ':\n' > "$PLUGIN/shell/zshrc.zsh"
  install_plugin '  shell_fragment: true' '  shell: shell/zshrc.zsh'
  grep -q 'shell/zshrc.zsh' "$XDG_STATE_HOME/dotfiles/plugin-shell.zsh"
  bash "$CLI" remove acme
  ! grep -q 'shell/zshrc.zsh' "$XDG_STATE_HOME/dotfiles/plugin-shell.zsh"
}

@test "6d: home/zshrc loads plugin fragments before ~/.zshrc.local" {
  run awk '/plugin-shell.zsh/ && !p { p = NR } /source ~\/.zshrc.local/ && !l && p { l = NR } END { exit !(p && l && p < l) }' \
    "$REPO_ROOT/home/zshrc"
  [ "$status" -eq 0 ]
}
