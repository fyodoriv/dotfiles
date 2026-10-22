#!/usr/bin/env bats
# Tests for bin/jetbrains-install-plugins and the chezmoi step that runs it
# (.chezmoiscripts/run_after_jetbrains-plugins.sh). A fake IDE binary stands
# in for WebStorm: it logs each call and never starts a JVM.

load test_helper

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  export DOTFILES_DIR="$TEST_DIR/dotfiles"
  export XDG_STATE_HOME="$TEST_DIR/state"
  export JETBRAINS_APP_DIRS="$TEST_DIR/apps"
  export LAUNCH_LOG="$TEST_DIR/launches.log"
  mkdir -p "$HOME" "$DOTFILES_DIR/bin" "$DOTFILES_DIR/jetbrains" \
    "$DOTFILES_DIR/.chezmoiscripts" "$JETBRAINS_APP_DIRS"
  cp "$REPO_ROOT/bin/jetbrains-install-plugins" "$DOTFILES_DIR/bin/"
  cp "$REPO_ROOT/.chezmoiscripts/run_after_jetbrains-plugins.sh" "$DOTFILES_DIR/.chezmoiscripts/"
  RUN_AFTER="$DOTFILES_DIR/.chezmoiscripts/run_after_jetbrains-plugins.sh"
  INSTALLER="$DOTFILES_DIR/bin/jetbrains-install-plugins"
  PLUGINS="$DOTFILES_DIR/jetbrains/recommended_plugins.txt"
  printf '# comment\n\nKey Promoter X      # spaces in the id\nzielu.gittoolbox    # GitToolBox\n' > "$PLUGINS"
  STAMP_DIR="$XDG_STATE_HOME/dotfiles/jetbrains-plugins"
  make_ide WebStorm webstorm WS-251.25410.117
  : > "$LAUNCH_LOG"
}

teardown() {
  if [ -f "$TEST_DIR/ide.pid" ]; then
    kill "$(cat "$TEST_DIR/ide.pid")" 2>/dev/null || true
  fi
  rm -rf "$TEST_DIR"
}

# make_ide <App name> <binary> <build>: a fake JetBrains app bundle.
# `installPlugins <id>` logs and succeeds, or fails when <id> is in
# FAKE_FAIL_PLUGIN. FAKE_READ_STDIN=1 makes it read all of stdin, as an IDE
# that reads stdin would. `serve` loops so the IDE looks open to pgrep.
make_ide() {
  local app="$JETBRAINS_APP_DIRS/$1.app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  printf '%s\n' "$3" > "$app/Contents/Resources/build.txt"
  cat > "$app/Contents/MacOS/$2" <<'FAKE'
#!/bin/bash
if [ "${1:-}" = "serve" ]; then
  while :; do sleep 1; done
fi
echo "$(basename "$0") $*" >> "$LAUNCH_LOG"
[ -z "${FAKE_READ_STDIN:-}" ] || cat > /dev/null
if [ "${1:-}" = "installPlugins" ] && [ "${2:-}" = "${FAKE_FAIL_PLUGIN:-}" ]; then
  echo "error: plugin not found: $2"
  exit 1
fi
echo "already installed: ${2:-}"
FAKE
  chmod +x "$app/Contents/MacOS/$2"
}

launches() { grep -c 'installPlugins' "$LAUNCH_LOG" || true; }

@test "second run with no change launches no installPlugins" {
  run bash "$RUN_AFTER"
  [ "$status" -eq 0 ]
  [ "$(launches)" -eq 2 ]
  [ -f "$STAMP_DIR/WebStorm.stamp" ]

  : > "$LAUNCH_LOG"
  run bash "$RUN_AFTER"
  [ "$status" -eq 0 ]
  [ "$(launches)" -eq 0 ]
  [[ "$output" == *"unchanged"* ]]
}

@test "a plugin id spelled with spaces reaches installPlugins whole" {
  run bash "$RUN_AFTER"
  [ "$status" -eq 0 ]
  grep -qx 'webstorm installPlugins Key Promoter X' "$LAUNCH_LOG"
}

@test "an IDE that reads stdin does not swallow the rest of the plugin list" {
  FAKE_READ_STDIN=1 run bash "$INSTALLER"
  [ "$status" -eq 0 ]
  [ "$(launches)" -eq 2 ]
  grep -qx 'webstorm installPlugins Key Promoter X' "$LAUNCH_LOG"
  grep -qx 'webstorm installPlugins zielu.gittoolbox' "$LAUNCH_LOG"
}

@test "a change to the plugin list re-runs the install" {
  run bash "$RUN_AFTER"
  [ "$(launches)" -eq 2 ]

  printf 'com.intellij.mermaid  # Mermaid\n' >> "$PLUGINS"
  : > "$LAUNCH_LOG"
  run bash "$RUN_AFTER"
  [ "$status" -eq 0 ]
  [ "$(launches)" -eq 3 ]

  : > "$LAUNCH_LOG"
  run bash "$RUN_AFTER"
  [ "$(launches)" -eq 0 ]
}

@test "a comment-only edit to the plugin list does not re-run" {
  run bash "$RUN_AFTER"
  [ "$(launches)" -eq 2 ]

  printf '# a new comment line\n' >> "$PLUGINS"
  : > "$LAUNCH_LOG"
  run bash "$RUN_AFTER"
  [ "$status" -eq 0 ]
  [ "$(launches)" -eq 0 ]
}

@test "an IDE build change re-runs the install" {
  run bash "$RUN_AFTER"
  [ "$(launches)" -eq 2 ]

  printf 'WS-252.1.1\n' > "$JETBRAINS_APP_DIRS/WebStorm.app/Contents/Resources/build.txt"
  : > "$LAUNCH_LOG"
  run bash "$RUN_AFTER"
  [ "$status" -eq 0 ]
  [ "$(launches)" -eq 2 ]
}

@test "a new IDE installs only in that IDE" {
  run bash "$RUN_AFTER"
  [ "$(launches)" -eq 2 ]

  make_ide GoLand goland GO-251.1.1
  : > "$LAUNCH_LOG"
  run bash "$RUN_AFTER"
  [ "$status" -eq 0 ]
  [ "$(launches)" -eq 2 ]
  [ "$(grep -c '^goland installPlugins' "$LAUNCH_LOG")" -eq 2 ]
  [ -f "$STAMP_DIR/GoLand.stamp" ]
}

@test "a failed install writes no stamp, and the next run retries" {
  export FAKE_FAIL_PLUGIN=zielu.gittoolbox
  run bash "$RUN_AFTER"
  # The chezmoi step never fails the apply on a plugin error.
  [ "$status" -eq 0 ]
  [[ "$output" == *"did not install"* ]]
  [ ! -e "$STAMP_DIR/WebStorm.stamp" ]

  unset FAKE_FAIL_PLUGIN
  : > "$LAUNCH_LOG"
  run bash "$RUN_AFTER"
  [ "$(launches)" -eq 2 ]
  [ -f "$STAMP_DIR/WebStorm.stamp" ]
}

@test "a failed forced install removes an old stamp" {
  run bash "$RUN_AFTER"
  [ -f "$STAMP_DIR/WebStorm.stamp" ]

  FAKE_FAIL_PLUGIN=zielu.gittoolbox run "$INSTALLER"
  [ "$status" -eq 1 ]
  [ ! -e "$STAMP_DIR/WebStorm.stamp" ]
}

@test "the installer without --if-changed always installs (doctor --fix path)" {
  run "$INSTALLER"
  [ "$status" -eq 0 ]
  run "$INSTALLER"
  [ "$status" -eq 0 ]
  [ "$(launches)" -eq 4 ]
  [ -f "$STAMP_DIR/WebStorm.stamp" ]
}

@test "an IDE with no build number is never skipped" {
  rm "$JETBRAINS_APP_DIRS/WebStorm.app/Contents/Resources/build.txt"
  run bash "$RUN_AFTER"
  [ "$status" -eq 0 ]
  run bash "$RUN_AFTER"
  [ "$(launches)" -eq 4 ]
  [ ! -e "$STAMP_DIR/WebStorm.stamp" ]
}

@test "a running IDE is skipped, gets no stamp, and installs once closed" {
  ide_bin="$JETBRAINS_APP_DIRS/WebStorm.app/Contents/MacOS/webstorm"
  "$ide_bin" serve >/dev/null 2>&1 3>&- &
  echo $! > "$TEST_DIR/ide.pid"
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -f "$ide_bin" >/dev/null 2>&1 && break
    sleep 0.2
  done

  run bash "$RUN_AFTER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"running"* ]]
  [ "$(launches)" -eq 0 ]
  [ ! -e "$STAMP_DIR/WebStorm.stamp" ]

  kill "$(cat "$TEST_DIR/ide.pid")"
  rm "$TEST_DIR/ide.pid"
  sleep 0.2
  run bash "$RUN_AFTER"
  [ "$(launches)" -eq 2 ]
  [ -f "$STAMP_DIR/WebStorm.stamp" ]
}

@test "no JetBrains IDE installed: the chezmoi step is silent and writes nothing" {
  rm -rf "$JETBRAINS_APP_DIRS/WebStorm.app"
  run bash "$RUN_AFTER"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -d "$STAMP_DIR" ]
}

@test "the chezmoi step calls the installer with --if-changed" {
  grep -q 'INSTALLER" --if-changed ||' "$REPO_ROOT/.chezmoiscripts/run_after_jetbrains-plugins.sh"
}
