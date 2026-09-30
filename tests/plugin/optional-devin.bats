#!/usr/bin/env bats
# US-4: a plugin's `plugins/<target>/.devin/` content is wired up only
# when the Devin CLI is detected on the user's machine. Detection is
# overridable via DOTFILES_PLUGIN_DEVIN_PRESENT (=0 to force skip, =1 to
# force include) so tests don't depend on the operator's real PATH.

DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
FIXTURE="$DOTFILES_DIR/tests/fixtures/plugin-fixtures/simple-plugin"

setup() {
  TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-plugin-devin.XXXXXX")"
  export HOME="$TEST_HOME"
  mkdir -p "$TEST_HOME/.config/agentbrew" "$TEST_HOME/.config/dotfiles" "$TEST_HOME/.local/share/dotfiles/logs/plugins"

  cat > "$TEST_HOME/.config/agentbrew/state.yaml" <<'EOF'
schemaVersion: 1
mcpServers: []
skillSourceDirs:
  - label: installed-skills
    path: ~/.config/agentbrew/installed-skills
EOF
  cat > "$TEST_HOME/.config/agentbrew/Agentfile.yaml" <<'EOF'
mcp: []
skills: []
EOF
  : > "$TEST_HOME/.config/agentbrew/shared-rules.md"
}

teardown() {
  if [ -n "${TEST_HOME:-}" ] && [ -d "$TEST_HOME" ] && [[ "$TEST_HOME" == /tmp/* || "$TEST_HOME" == /var/folders/* || "$TEST_HOME" == "${TMPDIR:-}"* ]]; then
    rm -rf "$TEST_HOME"
  fi
  unset DOTFILES_PLUGIN_DEVIN_PRESENT
}

# ── Devin absent: .devin/skills/ silently skipped ───────────────────

@test "Devin absent: .devin/skills/ NOT registered as a skill source" {
  export DOTFILES_PLUGIN_DEVIN_PRESENT=0
  run "$DOTFILES_DIR/bin/dotfiles-plugin" add "$FIXTURE" --no-sync --no-doctor
  [ "$status" -eq 0 ]
  # Regular skill source still registered
  run yq -r '.skillSourceDirs[] | select(.label == "simple-plugin-plugin") | .label' "$TEST_HOME/.config/agentbrew/state.yaml"
  [ "$output" = "simple-plugin-plugin" ]
  # Devin-only skill source NOT registered
  run yq -r '.skillSourceDirs[] | select(.label == "simple-plugin-devin-skills") | .label' "$TEST_HOME/.config/agentbrew/state.yaml"
  [ -z "$output" ]
}

@test "Devin absent: install message surfaces that Devin contributions were skipped" {
  export DOTFILES_PLUGIN_DEVIN_PRESENT=0
  run "$DOTFILES_DIR/bin/dotfiles-plugin" add "$FIXTURE" --no-sync --no-doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"Devin"* ]]
  [[ "$output" == *"skip"* || "$output" == *"absent"* ]]
}

@test "Devin absent: install-state.json marks devinSkipped=true" {
  export DOTFILES_PLUGIN_DEVIN_PRESENT=0
  "$DOTFILES_DIR/bin/dotfiles-plugin" add "$FIXTURE" --no-sync --no-doctor
  run jq -r '.devinSkipped' "$TEST_HOME/.config/dotfiles/plugins/simple-plugin/install-state.json"
  [ "$output" = "true" ]
}

# ── Devin present: .devin/skills/ wired up under a distinct label ───

@test "Devin present: .devin/skills/ registered as a separate skill source" {
  export DOTFILES_PLUGIN_DEVIN_PRESENT=1
  run "$DOTFILES_DIR/bin/dotfiles-plugin" add "$FIXTURE" --no-sync --no-doctor
  [ "$status" -eq 0 ]
  run yq -r '.skillSourceDirs[] | select(.label == "simple-plugin-devin-skills") | .path' "$TEST_HOME/.config/agentbrew/state.yaml"
  [[ "$output" == *"plugin-fixtures/simple-plugin/plugins/agentbrew/.devin/skills"* ]]
}

@test "Devin present: install-state.json marks devinSkipped=false" {
  export DOTFILES_PLUGIN_DEVIN_PRESENT=1
  "$DOTFILES_DIR/bin/dotfiles-plugin" add "$FIXTURE" --no-sync --no-doctor
  run jq -r '.devinSkipped' "$TEST_HOME/.config/dotfiles/plugins/simple-plugin/install-state.json"
  [ "$output" = "false" ]
}

# ── remove cleans up Devin entries when they were installed ─────────

@test "Devin present: remove drops the devin-skills label too" {
  export DOTFILES_PLUGIN_DEVIN_PRESENT=1
  "$DOTFILES_DIR/bin/dotfiles-plugin" add "$FIXTURE" --no-sync --no-doctor
  "$DOTFILES_DIR/bin/dotfiles-plugin" remove simple-plugin --no-sync
  run yq -r '.skillSourceDirs[] | select(.label == "simple-plugin-devin-skills") | .label' "$TEST_HOME/.config/agentbrew/state.yaml"
  [ -z "$output" ]
}

# ── Devin-absent installs survive a later Devin-present heal ────────
# This is the realistic scenario: user installs without Devin, later
# installs the Devin CLI, runs `dotfiles plugin heal` — the Devin
# contributions appear without needing remove+re-add.

@test "Devin absent install + later Devin present heal: skill registered after heal" {
  export DOTFILES_PLUGIN_DEVIN_PRESENT=0
  "$DOTFILES_DIR/bin/dotfiles-plugin" add "$FIXTURE" --no-sync --no-doctor
  run yq -r '.skillSourceDirs[] | select(.label == "simple-plugin-devin-skills") | .label' "$TEST_HOME/.config/agentbrew/state.yaml"
  [ -z "$output" ]
  export DOTFILES_PLUGIN_DEVIN_PRESENT=1
  "$DOTFILES_DIR/bin/dotfiles-plugin" heal simple-plugin --no-doctor
  run yq -r '.skillSourceDirs[] | select(.label == "simple-plugin-devin-skills") | .label' "$TEST_HOME/.config/agentbrew/state.yaml"
  [ "$output" = "simple-plugin-devin-skills" ]
}
