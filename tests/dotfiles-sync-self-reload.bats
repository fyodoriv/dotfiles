#!/usr/bin/env bats
# A running dotfiles-sync must not unload its own LaunchAgent: launchd would
# kill the rest of the run. The reload is deferred and done once, afterwards.
# launchctl is always a stub; nothing here touches the real launchd.
# XPC_SERVICE_NAME (set by launchd) is not faked here: a made-up value makes
# macOS libxpc abort the process. The sync exports DOTFILES_RELOAD_SELF_LABEL
# for the same purpose, and the tests use that.

load test_helper

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
SYNC_LABEL="com.dotfiles.dotfiles-sync"
LAUNCHAGENT_TMPL="$REPO_ROOT/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME/Library/LaunchAgents" "$TEST_DIR/stubs"
  export DOTFILES_RELOAD_MARKER_DIR="$TEST_DIR/markers"
  export DOTFILES_LOCK="$TEST_DIR/dotfiles.lock"
  unset XPC_SERVICE_NAME DOTFILES_RELOAD_SELF_LABEL

  cat > "$TEST_DIR/stubs/launchctl" <<STUB
#!/bin/bash
echo "\$*" >> "$TEST_DIR/launchctl.log"
exit 0
STUB
  chmod +x "$TEST_DIR/stubs/launchctl"
  export PATH="$TEST_DIR/stubs:$PATH"

  # Source plist and the deployed copy that install_plist replaces.
  printf '%s\n' '<plist new/>' > "$TEST_DIR/$SYNC_LABEL.plist"
  printf '%s\n' '<plist old/>' > "$HOME/Library/LaunchAgents/$SYNC_LABEL.plist"
}

teardown() { rm -rf "$TEST_DIR"; }

# Script that runs the real install_plist from the lifecycle template.
write_install_script() {
  {
    echo 'set -euo pipefail'
    echo "source '$REPO_ROOT/lib/self-reload.sh'"
    echo 'PROFILE=full; AUTO_UPGRADE=true; AUTO_SYNC=true; CLAUDE_REMOTE_CONTROL=false; IS_ENTERPRISE=false; failed=0'
    sed -n '/^should_skip_agent()/,/^}/p' "$LAUNCHAGENT_TMPL"
    sed -n '/^install_plist()/,/^}/p' "$LAUNCHAGENT_TMPL"
    echo "install_plist '$TEST_DIR/$SYNC_LABEL.plist' '$SYNC_LABEL.plist' '$SYNC_LABEL' dotfiles-sync"
  } > "$TEST_DIR/install.sh"
}

count_log() {
  [ -f "$TEST_DIR/launchctl.log" ] || { echo 0; return; }
  grep -c -- "$1" "$TEST_DIR/launchctl.log" || true
}

@test "install_plist inside its own job (self label) defers instead of unloading" {
  write_install_script
  DOTFILES_RELOAD_SELF_LABEL="$SYNC_LABEL" run bash "$TEST_DIR/install.sh"
  [ "$status" -eq 0 ]
  [ ! -s "$TEST_DIR/launchctl.log" ]
  [ -e "$DOTFILES_RELOAD_MARKER_DIR/$SYNC_LABEL" ]
}

@test "install_plist from another job still unloads and loads at once" {
  write_install_script
  XPC_SERVICE_NAME="com.dotfiles.dotfiles-doctor" run bash "$TEST_DIR/install.sh"
  [ "$status" -eq 0 ]
  [ "$(count_log '^unload')" -eq 1 ]
  [ "$(count_log '^load')" -eq 1 ]
  [ ! -e "$DOTFILES_RELOAD_MARKER_DIR/$SYNC_LABEL" ]
}

@test "install_plist from a manual apply defers while a sync run holds the lock" {
  write_install_script
  sleep 30 & sync_pid=$!
  printf '%s\n%s\n' "$sync_pid" sync > "$DOTFILES_LOCK"
  run bash "$TEST_DIR/install.sh"
  kill "$sync_pid" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [ "$(count_log '^unload')" -eq 0 ]
  [ "$(count_log '^load')" -eq 0 ]
  [ -e "$DOTFILES_RELOAD_MARKER_DIR/$SYNC_LABEL" ]
  grep -q 'plist new' "$HOME/Library/LaunchAgents/$SYNC_LABEL.plist"
}

@test "install_plist reloads at once when the sync lock owner is dead" {
  write_install_script
  bash -c 'exit 0' & dead_pid=$!
  wait "$dead_pid"
  printf '%s\n%s\n' "$dead_pid" sync > "$DOTFILES_LOCK"
  run bash "$TEST_DIR/install.sh"
  [ "$status" -eq 0 ]
  [ "$(count_log '^unload')" -eq 1 ]
  [ "$(count_log '^load')" -eq 1 ]
  [ ! -e "$DOTFILES_RELOAD_MARKER_DIR/$SYNC_LABEL" ]
}

@test "install_plist reloads at once while a manual apply holds the lock" {
  write_install_script
  sleep 30 & apply_pid=$!
  printf '%s\n%s\n' "$apply_pid" apply > "$DOTFILES_LOCK"
  run bash "$TEST_DIR/install.sh"
  kill "$apply_pid" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [ "$(count_log '^unload')" -eq 1 ]
  [ ! -e "$DOTFILES_RELOAD_MARKER_DIR/$SYNC_LABEL" ]
}

@test "reload --deferred reloads a marked job once, then does nothing" {
  mkdir -p "$DOTFILES_RELOAD_MARKER_DIR"
  : > "$DOTFILES_RELOAD_MARKER_DIR/$SYNC_LABEL"
  cat > "$TEST_DIR/stubs/chezmoi" <<STUB
#!/bin/bash
[ "\${1:-}" = "source-path" ] && printf '%s\n' "$REPO_ROOT"
STUB
  chmod +x "$TEST_DIR/stubs/chezmoi"

  run "$REPO_ROOT/bin/dotfiles-reload-launchagents" --deferred
  [ "$status" -eq 0 ]
  run "$REPO_ROOT/bin/dotfiles-reload-launchagents" --deferred
  [ "$status" -eq 0 ]
  [ "$(count_log '^bootout')" -eq 1 ]
  [ "$(count_log '^bootstrap')" -eq 1 ]
  [ ! -e "$DOTFILES_RELOAD_MARKER_DIR/$SYNC_LABEL" ]
}

@test "two concurrent reload --deferred runs reload once" {
  mkdir -p "$DOTFILES_RELOAD_MARKER_DIR"
  : > "$DOTFILES_RELOAD_MARKER_DIR/$SYNC_LABEL"
  cat > "$TEST_DIR/stubs/chezmoi" <<STUB
#!/bin/bash
[ "\${1:-}" = "source-path" ] && printf '%s\n' "$REPO_ROOT"
STUB
  chmod +x "$TEST_DIR/stubs/chezmoi"

  "$REPO_ROOT/bin/dotfiles-reload-launchagents" --deferred >/dev/null 2>&1 &
  "$REPO_ROOT/bin/dotfiles-reload-launchagents" --deferred >/dev/null 2>&1 &
  wait
  [ "$(count_log '^bootstrap')" -eq 1 ]
}

@test "reload --deferred is report-only outside the applied checkout" {
  mkdir -p "$DOTFILES_RELOAD_MARKER_DIR"
  : > "$DOTFILES_RELOAD_MARKER_DIR/$SYNC_LABEL"
  printf '#!/bin/bash\necho /nowhere\n' > "$TEST_DIR/stubs/chezmoi"
  chmod +x "$TEST_DIR/stubs/chezmoi"
  run "$REPO_ROOT/bin/dotfiles-reload-launchagents" --deferred
  [ "$status" -eq 0 ]
  [ ! -s "$TEST_DIR/launchctl.log" ]
  [ -e "$DOTFILES_RELOAD_MARKER_DIR/$SYNC_LABEL" ]
}

# End to end: a sync whose chezmoi apply asks to reload this same job.
@test "sync finishes its run, then starts exactly one follow-up reload" {
  local fx="$TEST_DIR/fx"
  git init --bare --quiet "$fx/remote.git"
  git init --quiet "$fx/dotfiles"
  mkdir -p "$fx/dotfiles/bin" "$fx/dotfiles/lib"
  for f in bin/dotfiles-sync; do cp "$REPO_ROOT/$f" "$fx/dotfiles/$f"; done
  for f in colors stats errors-log lock push-error-classify agentbrew-locate self-reload zshrc-appends; do
    cp "$REPO_ROOT/lib/$f.sh" "$fx/dotfiles/lib/$f.sh"
  done
  # Stub follow-up helper: records each call.
  cat > "$fx/dotfiles/bin/dotfiles-reload-launchagents" <<STUB
#!/bin/bash
echo "followup \$*" >> "$TEST_DIR/followup.log"
STUB
  chmod +x "$fx/dotfiles/bin/dotfiles-sync" "$fx/dotfiles/bin/dotfiles-reload-launchagents"
  git -C "$fx/dotfiles" add -A
  git -C "$fx/dotfiles" commit --no-verify -qm "chore: initial"
  git -C "$fx/dotfiles" remote add origin "$fx/remote.git"
  git -C "$fx/dotfiles" push -q -u origin "$(git -C "$fx/dotfiles" branch --show-current)" 2>/dev/null
  git -C "$fx/dotfiles" remote set-head origin "$(git -C "$fx/dotfiles" branch --show-current)"

  # Fake chezmoi: apply runs the real install_plist (twice) as the job itself.
  write_install_script
  cat > "$TEST_DIR/stubs/chezmoi" <<STUB
#!/bin/bash
if [ "\${1:-}" = "apply" ]; then
  bash "$TEST_DIR/install.sh"
  bash "$TEST_DIR/install.sh"
  echo applied >> "$TEST_DIR/apply.log"
fi
STUB
  chmod +x "$TEST_DIR/stubs/chezmoi"

  run "$fx/dotfiles/bin/dotfiles-sync"
  [ "$status" -eq 0 ]
  # The current run finished: apply completed and the run was logged.
  [ "$(wc -l < "$TEST_DIR/apply.log" | tr -d ' ')" -eq 1 ]
  [[ "$output" == *"No changes"* ]]
  [ ! -s "$TEST_DIR/launchctl.log" ]

  for _ in $(seq 1 50); do [ -s "$TEST_DIR/followup.log" ] && break; sleep 0.1; done
  sleep 0.3
  [ "$(wc -l < "$TEST_DIR/followup.log" | tr -d ' ')" -eq 1 ]
  grep -q -- '--deferred' "$TEST_DIR/followup.log"
}

@test "sync without a reload request starts no follow-up" {
  local fx="$TEST_DIR/fx"
  git init --bare --quiet "$fx/remote.git"
  git init --quiet "$fx/dotfiles"
  mkdir -p "$fx/dotfiles/bin" "$fx/dotfiles/lib"
  cp "$REPO_ROOT/bin/dotfiles-sync" "$fx/dotfiles/bin/"
  for f in colors stats errors-log lock push-error-classify agentbrew-locate self-reload zshrc-appends; do
    cp "$REPO_ROOT/lib/$f.sh" "$fx/dotfiles/lib/$f.sh"
  done
  printf '#!/bin/bash\necho followup >> "%s/followup.log"\n' "$TEST_DIR" > "$fx/dotfiles/bin/dotfiles-reload-launchagents"
  chmod +x "$fx/dotfiles/bin/"*
  git -C "$fx/dotfiles" add -A
  git -C "$fx/dotfiles" commit --no-verify -qm "chore: initial"
  git -C "$fx/dotfiles" remote add origin "$fx/remote.git"
  git -C "$fx/dotfiles" push -q -u origin "$(git -C "$fx/dotfiles" branch --show-current)" 2>/dev/null
  git -C "$fx/dotfiles" remote set-head origin "$(git -C "$fx/dotfiles" branch --show-current)"
  run "$fx/dotfiles/bin/dotfiles-sync"
  [ "$status" -eq 0 ]
  sleep 0.5
  [ ! -e "$TEST_DIR/followup.log" ]
}
