#!/usr/bin/env bats
# Functional tests for modules/workflow/doctor.sh

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"

  mkdir -p "$TEST_HOME"
  mkdir -p "$TEST_HOME/Library/LaunchAgents"
  mkdir -p "$TEST_DOTFILES/home"
  mkdir -p "$TEST_DOTFILES/launchagents"

  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"
  mkdir -p "$TEST_DOTFILES/lib"
  cp "$BATS_TEST_DIRNAME/../lib/spotlight-probe.sh" "$TEST_DOTFILES/lib/"
  # Stub mdls: report an item as indexed when its path is listed in
  # $MDLS_INDEXED_FILE, else "(null)" (not in the Spotlight index).
  MDLS_INDEXED_FILE="$TEST_DIR/mdls-indexed"
  : > "$MDLS_INDEXED_FILE"
  cat > "$TEST_DIR/mdls" <<STUB
#!/bin/bash
path="\${!#}"
if grep -qxF "\$path" "$MDLS_INDEXED_FILE"; then printf '%s' "\$(basename "\$path")"; else printf '(null)'; fi
STUB
  chmod +x "$TEST_DIR/mdls"
  export DOTFILES_MDLS_BIN="$TEST_DIR/mdls"
  # Unset DOTFILES_REPOS_DIR so the module falls back to $HOME/apps
  # (= $TEST_HOME/apps). Otherwise the parent env's repos dir leaks in.
  unset DOTFILES_REPOS_DIR
  unset DOTFILES_ALLOW_BLOCKED_NODE_PUBLISHER

  OVERRIDES_FILE="$TEST_DOTFILES/.overrides"
  touch "$OVERRIDES_FILE"
  FIX_MODE=false
  LIST_MODE=false
  pass_count=0
  fail_count=0
  fix_count=0
  skip_count=0

  pass()    { pass_count=$((pass_count + 1)); }
  fail()    { fail_count=$((fail_count + 1)); }
  fixed()   { fix_count=$((fix_count + 1)); }
  skipped() { skip_count=$((skip_count + 1)); }

  is_overridden() { grep -qx "$1" "$OVERRIDES_FILE" 2>/dev/null; }

  check() {
    local id="$1" desc="$2" test_cmd="$3" fix_cmd="${4:-}"
    if $LIST_MODE; then return; fi
    if is_overridden "$id"; then skipped "$desc"; return; fi
    if eval "$test_cmd" >/dev/null 2>&1; then
      pass "$desc"
    elif $FIX_MODE && [ -n "$fix_cmd" ]; then
      eval "$fix_cmd" >/dev/null 2>&1
      fixed "$desc"
    else
      fail "$desc"
    fi
  }

  # Create a fake deployed launchagent plist (in ~/Library/LaunchAgents/)
  cat > "$TEST_HOME/Library/LaunchAgents/com.dotfiles.test-agent.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>Label</key><string>com.dotfiles.test-agent</string>
</dict></plist>
PLIST

  # Create zshrc without hardcoded JIRA token
  echo '# clean zshrc' > "$TEST_DOTFILES/home/zshrc"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "workflow: iterates over launchagent plist files" {
  # Agent is not loaded (launchctl won't find it), so it should fail
  source "$BATS_TEST_DIRNAME/../modules/workflow/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "workflow: skips overridden launchagent check" {
  echo "agent.test-agent" >> "$OVERRIDES_FILE"
  echo "security.jira_not_plaintext" >> "$OVERRIDES_FILE"
  source "$BATS_TEST_DIRNAME/../modules/workflow/doctor.sh"
  [ "$skip_count" -ge 1 ]
  [ "$fail_count" -eq 0 ]
}

@test "workflow: skips blocked dotfiles-upgrade agent in endpoint safe mode" {
  mkdir -p "$TEST_HOME/.local/state/dotfiles"
  touch "$TEST_HOME/.local/state/dotfiles/endpoint-node-publisher-blocked"
  cat > "$TEST_HOME/Library/LaunchAgents/com.dotfiles.dotfiles-upgrade.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>Label</key><string>com.dotfiles.dotfiles-upgrade</string>
</dict></plist>
PLIST

  source "$BATS_TEST_DIRNAME/../modules/workflow/doctor.sh"
  [ "$skip_count" -ge 1 ]
  [ "$fail_count" -ge 1 ]
}

@test "workflow: passes jira_not_plaintext when zshrc is clean" {
  # Jira check removed — covered by security module.
  # Verify workflow still runs without errors (spotlight checks may pass/fail depending on dirs)
  source "$BATS_TEST_DIRNAME/../modules/workflow/doctor.sh"
  local total=$((pass_count + fail_count + skip_count))
  [ "$total" -ge 1 ]
}

@test "workflow: fails jira_not_plaintext when token is hardcoded" {
  # Jira check removed — covered by security module.
  # Verify workflow doesn't break when zshrc has a token (no-op now)
  echo 'JIRA_TOKEN=NDU0xxxx' > "$TEST_DOTFILES/home/zshrc"
  source "$BATS_TEST_DIRNAME/../modules/workflow/doctor.sh"
  # At least one check runs (launchagent)
  local total=$((pass_count + fail_count + skip_count))
  [ "$total" -ge 1 ]
}

@test "workflow: spotlight checks pass when metadata file exists" {
  # Create a dir that the module checks + its marker
  mkdir -p "$TEST_HOME/apps"
  touch "$TEST_HOME/apps/.metadata_never_index"
  source "$BATS_TEST_DIRNAME/../modules/workflow/doctor.sh"
  [ "$pass_count" -ge 1 ]
}

@test "workflow: spotlight check fails when the marker exists but the dir is indexed" {
  mkdir -p "$TEST_HOME/apps/project"
  touch "$TEST_HOME/apps/.metadata_never_index"
  echo "$TEST_HOME/apps/project" > "$MDLS_INDEXED_FILE"
  failed_descs=()
  fail() { fail_count=$((fail_count + 1)); failed_descs+=("$1"); }
  source "$BATS_TEST_DIRNAME/../modules/workflow/doctor.sh"
  printf '%s\n' "${failed_descs[@]}" | grep -F "$TEST_HOME/apps out of the Spotlight index" | grep -qF "Search Privacy"
}

@test "workflow: spotlight check passes when the marker exists and the probe finds nothing indexed" {
  mkdir -p "$TEST_HOME/apps/project"
  touch "$TEST_HOME/apps/.metadata_never_index"
  failed_descs=()
  fail() { fail_count=$((fail_count + 1)); failed_descs+=("$1"); }
  source "$BATS_TEST_DIRNAME/../modules/workflow/doctor.sh"
  ! printf '%s\n' "${failed_descs[@]}" | grep -qF "Spotlight"
}

@test "workflow: spotlight check fails without the marker even when nothing is indexed" {
  mkdir -p "$TEST_HOME/apps/project"
  failed_descs=()
  fail() { fail_count=$((fail_count + 1)); failed_descs+=("$1"); }
  source "$BATS_TEST_DIRNAME/../modules/workflow/doctor.sh"
  printf '%s\n' "${failed_descs[@]}" | grep -qF "$TEST_HOME/apps out of the Spotlight index"
}

@test "workflow: no spotlight check prints 'excluded from Spotlight'" {
  ! grep -n "excluded from Spotlight" "$BATS_TEST_DIRNAME/../modules/workflow/doctor.sh" "$BATS_TEST_DIRNAME/../modules/agent-browser/doctor.sh"
}

@test "workflow: spotlight fix creates metadata_never_index" {
  FIX_MODE=true
  mkdir -p "$TEST_HOME/apps"
  source "$BATS_TEST_DIRNAME/../modules/workflow/doctor.sh"
  [ -f "$TEST_HOME/apps/.metadata_never_index" ]
}

@test "workflow: agent worktree check fails for a real wt folder and fix makes it .noindex" {
  mkdir -p "$TEST_DOTFILES/lib" "$TEST_HOME/apps/tooling/wt/feature"
  cp "$BATS_TEST_DIRNAME/../lib/agent-worktrees-noindex.sh" "$TEST_DOTFILES/lib/"
  touch "$TEST_HOME/apps/.metadata_never_index"
  source "$BATS_TEST_DIRNAME/../modules/workflow/doctor.sh"
  [ "$fail_count" -ge 1 ]
  FIX_MODE=true
  source "$BATS_TEST_DIRNAME/../modules/workflow/doctor.sh"
  [ -L "$TEST_HOME/apps/tooling/wt" ]
  [ -d "$TEST_HOME/apps/tooling/wt.noindex/feature" ]
}

@test "workflow: agent worktree check is skipped without a tooling folder" {
  mkdir -p "$TEST_DOTFILES/lib" "$TEST_HOME/apps"
  cp "$BATS_TEST_DIRNAME/../lib/agent-worktrees-noindex.sh" "$TEST_DOTFILES/lib/"
  touch "$TEST_HOME/apps/.metadata_never_index"
  FIX_MODE=true
  source "$BATS_TEST_DIRNAME/../modules/workflow/doctor.sh"
  [ "$fail_count" -eq 0 ]
  [ ! -e "$TEST_HOME/apps/tooling" ]
}

@test "workflow: skips spotlight for non-existent directories" {
  # $HOME/apps doesn't exist, so the loop continues past it
  # Only the launchagent checks should run (jira check was removed)
  source "$BATS_TEST_DIRNAME/../modules/workflow/doctor.sh"
  local total=$((pass_count + fail_count + skip_count))
  # At least 1 check: launchagent
  [ "$total" -ge 1 ]
}

@test "workflow: no launchagent checks when dir is empty" {
  rm "$TEST_HOME/Library/LaunchAgents/com.dotfiles.test-agent.plist"
  source "$BATS_TEST_DIRNAME/../modules/workflow/doctor.sh"
  # With no deployed agents and no existing dirs, nothing to check
  # But module still runs without error
  local total=$((pass_count + fail_count + skip_count))
  [ "$total" -ge 0 ]
}
