#!/usr/bin/env bats
# Slice 3 of US-2 + US-3: `dotfiles plugin remove|heal|status`.
# remove inverts everything add created (symlinks, state.yaml skill
# source, Agentfile fragment entries, shared-rules.md marker pair) and
# leaves the source repo untouched. heal restores drift idempotently.
# status reports per-plugin health for dotfiles-doctor consumption.
# See docs/plugin-system.md US-2 + US-3.

DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
FIXTURE="$DOTFILES_DIR/tests/fixtures/plugin-fixtures/simple-plugin"

setup() {
  TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-plugin-lifecycle.XXXXXX")"
  export HOME="$TEST_HOME"
  mkdir -p "$TEST_HOME/.config/agentbrew" "$TEST_HOME/.config/dotfiles" "$TEST_HOME/.local/share/dotfiles/logs/plugins"

  cat > "$TEST_HOME/.config/agentbrew/state.yaml" <<'EOF'
schemaVersion: 1
mcpServers:
  - name: context7
    command: npx
    args: ['-y', '@upstash/context7-mcp@latest']
    env: {}
    source: agentfile
skillSourceDirs:
  - label: installed-skills
    path: ~/.config/agentbrew/installed-skills
EOF

  cat > "$TEST_HOME/.config/agentbrew/Agentfile.yaml" <<'EOF'
mcp:
  - context7
  - playwright
skills:
  - debug
EOF

  cat > "$TEST_HOME/.config/agentbrew/shared-rules.md" <<'EOF'
# Pre-existing operator rules

The plugin's rules-fragment must NOT touch this line.

## Some other section

This line also must survive intact across install + remove.
EOF

  # Snapshot the fixture state pre-install so US-2 can assert "source untouched".
  FIXTURE_BEFORE_HASH="$(find "$FIXTURE" -type f -exec shasum {} + | sort | shasum | awk '{print $1}')"
  FIXTURE_BEFORE_FILES="$(find "$FIXTURE" -type f | sort)"
  export FIXTURE_BEFORE_HASH FIXTURE_BEFORE_FILES

  # Install the plugin so remove/heal/status have something to act on.
  "$DOTFILES_DIR/bin/dotfiles-plugin" add "$FIXTURE" --no-sync --no-doctor > /dev/null
}

teardown() {
  if [ -n "${TEST_HOME:-}" ] && [ -d "$TEST_HOME" ] && [[ "$TEST_HOME" == /tmp/* || "$TEST_HOME" == /var/folders/* || "$TEST_HOME" == "${TMPDIR:-}"* ]]; then
    rm -rf "$TEST_HOME"
  fi
}

# ── US-2: remove ────────────────────────────────────────────────────

@test "remove: requires a plugin name argument" {
  run "$DOTFILES_DIR/bin/dotfiles-plugin" remove
  [ "$status" -ne 0 ]
  [[ "$output" == *"name"* || "$output" == *"usage"* || "$output" == *"Usage"* ]]
}

@test "remove: fails with a clear message when plugin not installed" {
  run "$DOTFILES_DIR/bin/dotfiles-plugin" remove never-installed-plugin
  [ "$status" -ne 0 ]
  [[ "$output" == *"not installed"* || "$output" == *"not found"* ]]
}

@test "remove: deletes the doctor symlink + the plugin state directory" {
  local linked="$TEST_HOME/.config/dotfiles/plugins/simple-plugin/modules/test-plugin/doctor.sh"
  [ -L "$linked" ]
  run "$DOTFILES_DIR/bin/dotfiles-plugin" remove simple-plugin --no-sync
  [ "$status" -eq 0 ]
  [ ! -L "$linked" ]
  [ ! -d "$TEST_HOME/.config/dotfiles/plugins/simple-plugin" ]
}

@test "remove: drops the plugin's skillSourceDirs entry from state.yaml" {
  run "$DOTFILES_DIR/bin/dotfiles-plugin" remove simple-plugin --no-sync
  [ "$status" -eq 0 ]
  run yq -r '.skillSourceDirs[] | select(.label == "simple-plugin-plugin") | .label' "$TEST_HOME/.config/agentbrew/state.yaml"
  [ -z "$output" ]
  # Pre-existing entries survive.
  run yq -r '.skillSourceDirs[] | select(.label == "installed-skills") | .label' "$TEST_HOME/.config/agentbrew/state.yaml"
  [ "$output" = "installed-skills" ]
}

@test "remove: drops the plugin's Agentfile fragment entries" {
  run "$DOTFILES_DIR/bin/dotfiles-plugin" remove simple-plugin --no-sync
  [ "$status" -eq 0 ]
  run yq -r '.mcp[]' "$TEST_HOME/.config/agentbrew/Agentfile.yaml"
  [[ "$output" != *"test-plugin-mcp"* ]]
  # Pre-existing entries survive
  [[ "$output" == *"context7"* ]]
  [[ "$output" == *"playwright"* ]]
  run yq -r '.skills[]' "$TEST_HOME/.config/agentbrew/Agentfile.yaml"
  [[ "$output" != *"test-plugin-skill"* ]]
  [[ "$output" == *"debug"* ]]
}

@test "remove: strips the rules-fragment markers from shared-rules.md" {
  run "$DOTFILES_DIR/bin/dotfiles-plugin" remove simple-plugin --no-sync
  [ "$status" -eq 0 ]
  ! grep -q "^<!-- plugin:simple-plugin:start -->$" "$TEST_HOME/.config/agentbrew/shared-rules.md"
  ! grep -q "TEST_SENTINEL_LINE" "$TEST_HOME/.config/agentbrew/shared-rules.md"
  # Pre-existing rules survive
  grep -q "The plugin's rules-fragment must NOT touch this line" "$TEST_HOME/.config/agentbrew/shared-rules.md"
  grep -q "This line also must survive intact" "$TEST_HOME/.config/agentbrew/shared-rules.md"
}

@test "remove: leaves the source repo untouched (file count + content hashes)" {
  "$DOTFILES_DIR/bin/dotfiles-plugin" remove simple-plugin --no-sync
  local after_hash after_files
  after_hash="$(find "$FIXTURE" -type f -exec shasum {} + | sort | shasum | awk '{print $1}')"
  after_files="$(find "$FIXTURE" -type f | sort)"
  [ "$after_hash" = "$FIXTURE_BEFORE_HASH" ]
  [ "$after_files" = "$FIXTURE_BEFORE_FILES" ]
}

@test "remove: list no longer shows the plugin" {
  "$DOTFILES_DIR/bin/dotfiles-plugin" remove simple-plugin --no-sync
  run "$DOTFILES_DIR/bin/dotfiles-plugin" list
  [ "$status" -eq 0 ]
  [[ "$output" != *"simple-plugin"* ]]
}

# ── US-3: heal ──────────────────────────────────────────────────────

@test "heal: restores a deleted doctor symlink" {
  local linked="$TEST_HOME/.config/dotfiles/plugins/simple-plugin/modules/test-plugin/doctor.sh"
  rm "$linked"
  [ ! -L "$linked" ]
  run "$DOTFILES_DIR/bin/dotfiles-plugin" heal simple-plugin --no-doctor
  [ "$status" -eq 0 ]
  [ -L "$linked" ]
}

@test "heal: restores a manually-deleted skill source entry in state.yaml" {
  # Operator (or buggy sync) wipes the entry.
  yq -i '.skillSourceDirs |= map(select(.label != "simple-plugin-plugin"))' "$TEST_HOME/.config/agentbrew/state.yaml"
  run yq -r '.skillSourceDirs[] | select(.label == "simple-plugin-plugin") | .label' "$TEST_HOME/.config/agentbrew/state.yaml"
  [ -z "$output" ]
  run "$DOTFILES_DIR/bin/dotfiles-plugin" heal simple-plugin --no-doctor
  [ "$status" -eq 0 ]
  run yq -r '.skillSourceDirs[] | select(.label == "simple-plugin-plugin") | .label' "$TEST_HOME/.config/agentbrew/state.yaml"
  [ "$output" = "simple-plugin-plugin" ]
}

@test "heal: re-run is a no-op on a healthy install" {
  run "$DOTFILES_DIR/bin/dotfiles-plugin" heal simple-plugin --no-doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"already healthy"* || "$output" == *"no-op"* || "$output" == *"unchanged"* ]]
}

@test "heal: fails when plugin not installed" {
  run "$DOTFILES_DIR/bin/dotfiles-plugin" heal never-installed-plugin
  [ "$status" -ne 0 ]
}

# ── US-3 / doctor: status ───────────────────────────────────────────

@test "status: reports healthy on a clean install" {
  run "$DOTFILES_DIR/bin/dotfiles-plugin" status simple-plugin
  [ "$status" -eq 0 ]
  [[ "$output" == *"healthy"* || "$output" == *"OK"* || "$output" == *"\u2713"* ]]
}

@test "status: reports broken when a symlink is missing" {
  rm "$TEST_HOME/.config/dotfiles/plugins/simple-plugin/modules/test-plugin/doctor.sh"
  run "$DOTFILES_DIR/bin/dotfiles-plugin" status simple-plugin
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing"* || "$output" == *"broken"* || "$output" == *"drift"* ]]
}

@test "status: fails when plugin not installed" {
  run "$DOTFILES_DIR/bin/dotfiles-plugin" status never-installed-plugin
  [ "$status" -ne 0 ]
}
