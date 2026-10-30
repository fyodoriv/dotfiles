#!/usr/bin/env bats
# Tests for bin/dotfiles-node-upgrade — one-step Node switch that moves
# ~/.node-version, ~/.local/bin links, and agentbrew plists together.

SCRIPT="$BATS_TEST_DIRNAME/../bin/dotfiles-node-upgrade"

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  STUB_DIR="$TEST_DIR/stubs"
  VERSIONS="$TEST_HOME/.local/share/fnm/node-versions"
  mkdir -p "$TEST_HOME/Library/LaunchAgents" "$TEST_HOME/.local/bin" \
    "$TEST_HOME/.config/agentbrew" "$STUB_DIR"
  export CALL_LOG="$TEST_DIR/calls.log"

  # A fake Node install. Its "node" logs its args. Run as agentbrew
  # `auto-sync install`, it writes com.agentbrew.check.plist with its own
  # path, as the real CLI does with process.execPath.
  _make_version() {
    local bin="$VERSIONS/$1/installation/bin"
    mkdir -p "$bin"
    cat > "$bin/node" <<STUB
#!/bin/bash
echo "node[$1] \$*" >> "$CALL_LOG"
if [ "\${2:-}" = "auto-sync" ] && [ "\${3:-}" = "install" ]; then
  cat > "$TEST_HOME/Library/LaunchAgents/com.agentbrew.check.plist" <<EOF
<plist><dict><key>ProgramArguments</key><array><string>\$0</string></array></dict></plist>
EOF
fi
STUB
    cat > "$bin/npm" <<STUB
#!/bin/bash
echo "npm[$1] \$*" >> "$CALL_LOG"
case "\$1" in
  prefix) echo "${bin%/bin}" ;;
  install)
    printf '#!/bin/bash\necho codex-cli 1.2.3\n' > "$bin/codex"
    chmod +x "$bin/codex" ;;
esac
STUB
    printf '#!/bin/bash\n' > "$bin/npx"
    chmod +x "$bin/node" "$bin/npm" "$bin/npx"
  }
  export -f _make_version
  export VERSIONS TEST_HOME

  cat > "$STUB_DIR/fnm" <<'STUB'
#!/bin/bash
echo "fnm $*" >> "$CALL_LOG"
case "$1" in
  ls-remote) printf 'v22.22.0 (Jod)\nv24.21.0 (Krypton)\nv24.22.0 (Krypton)\n' ;;
  install) _make_version "$2" ;;
esac
STUB
  printf '#!/bin/bash\necho "launchctl $*" >> "%s"\n' "$CALL_LOG" > "$STUB_DIR/launchctl"
  printf '#!/bin/bash\necho "${TEST_AI_TOOLS:-true}"\n' > "$STUB_DIR/chezmoi"
  chmod +x "$STUB_DIR/fnm" "$STUB_DIR/launchctl" "$STUB_DIR/chezmoi"

  # Current state: v24.21.0 everywhere, plus the pinned minsky Node.
  _make_version v24.21.0
  _make_version v24.14.0
  echo "v24.21.0" > "$TEST_HOME/.node-version"
  for t in node npm npx; do
    ln -s "$VERSIONS/v24.21.0/installation/bin/$t" "$TEST_HOME/.local/bin/$t"
  done
  cat > "$TEST_HOME/Library/LaunchAgents/com.agentbrew.check.plist" <<EOF
<plist><dict><key>ProgramArguments</key><array><string>$VERSIONS/v24.21.0/installation/bin/node</string></array></dict></plist>
EOF
  touch "$TEST_HOME/Library/LaunchAgents/com.dotfiles.gui-path.plist"
  : > "$TEST_HOME/.config/agentbrew/Agentfile.yaml"

  # Fake agentbrew checkout for agentbrew_locate.
  mkdir -p "$TEST_DIR/repos/tooling/agentbrew/dist"
  : > "$TEST_DIR/repos/tooling/agentbrew/dist/cli.js"
  export DOTFILES_REPOS_DIR="$TEST_DIR/repos"

  export ORIG_HOME="$HOME"
  export HOME="$TEST_HOME"
  export PATH="$STUB_DIR:$PATH"
}

teardown() {
  export HOME="$ORIG_HOME"
  rm -rf "$TEST_DIR"
}

@test "dotfiles-node-upgrade is executable with a bash shebang" {
  [ -x "$SCRIPT" ]
  head -1 "$SCRIPT" | grep -qx '#!/bin/bash'
}

@test "one step moves .node-version, ~/.local/bin links, and agentbrew plists" {
  run bash "$SCRIPT" 24.22.0
  [ "$status" -eq 0 ] || { echo "$output"; false; }

  [ "$(cat "$TEST_HOME/.node-version")" = "v24.22.0" ]
  for t in node npm npx codex; do
    [ "$(readlink "$TEST_HOME/.local/bin/$t")" = "$VERSIONS/v24.22.0/installation/bin/$t" ]
  done
  grep -q "v24.22.0/installation/bin/node" "$TEST_HOME/Library/LaunchAgents/com.agentbrew.check.plist"
  grep -q '^fnm install v24.22.0$' "$CALL_LOG"
  grep -q '^fnm default v24.22.0$' "$CALL_LOG"
  grep -q '^node\[v24.22.0\] .*cli.js auto-sync install$' "$CALL_LOG"
  grep -q '^node\[v24.22.0\] .*cli.js sync --no-recommended --agentfile ' "$CALL_LOG"
  grep -q 'kickstart -k gui/.*/com.dotfiles.gui-path' "$CALL_LOG"
  [[ "$output" == *"agentbrew.launchagent_node_pinned: all LaunchAgents"* ]]
}

@test "old Node versions stay installed (minsky pins one)" {
  run bash "$SCRIPT" 24.22.0
  [ "$status" -eq 0 ]
  ! grep -q 'fnm uninstall' "$CALL_LOG"
  [ -x "$VERSIONS/v24.14.0/installation/bin/node" ]
  [ -x "$VERSIONS/v24.21.0/installation/bin/node" ]
}

@test "no version picks the latest LTS and sets the lts-latest alias" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat "$TEST_HOME/.node-version")" = "v24.22.0" ]
  grep -q '^fnm alias v24.22.0 lts-latest$' "$CALL_LOG"
}

@test "--dry-run changes nothing" {
  run bash "$SCRIPT" 24.22.0 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] fnm install v24.22.0"* ]]
  [ "$(cat "$TEST_HOME/.node-version")" = "v24.21.0" ]
  [ "$(readlink "$TEST_HOME/.local/bin/node")" = "$VERSIONS/v24.21.0/installation/bin/node" ]
  # Only read-only calls (the npm globals listing) may run.
  ! grep -qE '^(fnm (install|default|alias)|node\[|launchctl)' "$CALL_LOG" 2>/dev/null
}

@test "a regular file in ~/.local/bin is left alone" {
  rm "$TEST_HOME/.local/bin/npx"
  echo "custom" > "$TEST_HOME/.local/bin/npx"
  run bash "$SCRIPT" 24.22.0
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_HOME/.local/bin/npx")" = "custom" ]
  [[ "$output" == *"npx is a regular file; left alone"* ]]
}

@test "fails when a plist still drifts after the switch" {
  # A second agentbrew plist that auto-sync does not rewrite.
  cat > "$TEST_HOME/Library/LaunchAgents/com.agentbrew.other.plist" <<EOF
<plist><dict><key>ProgramArguments</key><array><string>$VERSIONS/v24.21.0/installation/bin/node</string></array></dict></plist>
EOF
  run bash "$SCRIPT" 24.22.0
  [ "$status" -eq 1 ]
  [[ "$output" == *"com.agentbrew.other.plist runs"* ]]
}

@test "rejects a non-version argument" {
  run bash "$SCRIPT" latest
  [ "$status" -eq 64 ]
}

@test "skips when the Node publisher is blocked" {
  mkdir -p "$TEST_HOME/.local/state/dotfiles"
  : > "$TEST_HOME/.local/state/dotfiles/endpoint-node-publisher-blocked"
  run bash "$SCRIPT" 24.22.0
  [ "$status" -eq 0 ]
  [[ "$output" == *"Node upgrade skipped"* ]]
  [ ! -e "$CALL_LOG" ]
}

@test "dotfiles-upgrade --node delegates to dotfiles-node-upgrade" {
  grep -q -- '--node' "$BATS_TEST_DIRNAME/../bin/dotfiles-upgrade"
  grep -q 'dotfiles-node-upgrade' "$BATS_TEST_DIRNAME/../bin/dotfiles-upgrade"
}

@test "Node upgrade does not add Codex when AI tools are off and it was never installed" {
  export TEST_AI_TOOLS=false
  run bash "$SCRIPT" 24.22.0
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.local/bin/codex" ]
  ! grep -q 'install -g @openai/codex' "$CALL_LOG"
}

@test "Node upgrade preserves an existing Codex install when AI tools are off" {
  export TEST_AI_TOOLS=false
  ln -s "$VERSIONS/v24.21.0/installation/bin/codex" "$HOME/.local/bin/codex"
  run bash "$SCRIPT" 24.22.0
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/.local/bin/codex")" = "$VERSIONS/v24.22.0/installation/bin/codex" ]
}
