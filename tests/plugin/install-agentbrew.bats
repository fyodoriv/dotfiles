#!/usr/bin/env bats
# Slice 2 of US-1: `dotfiles plugin add <path>` wires the
# `plugins/agentbrew/` target — skill source registration in
# state.yaml, agentfile-fragment merge into the global Agentfile,
# rules-fragment append into shared-rules.md inside marker pairs.
# See docs/plugin-system.md.

DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
FIXTURE="$DOTFILES_DIR/tests/fixtures/plugin-fixtures/simple-plugin"

setup() {
  TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-plugin-agentbrew.XXXXXX")"
  export HOME="$TEST_HOME"
  mkdir -p "$TEST_HOME/.config/agentbrew" "$TEST_HOME/.config/dotfiles" "$TEST_HOME/.local/share/dotfiles/logs/plugins"

  # Pre-seed a baseline state.yaml + Agentfile so the install merges
  # into something realistic (matches the user's actual setup shape).
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

This line also must survive intact across install + re-install.
EOF
}

teardown() {
  if [ -n "${TEST_HOME:-}" ] && [ -d "$TEST_HOME" ] && [[ "$TEST_HOME" == /tmp/* || "$TEST_HOME" == /var/folders/* || "$TEST_HOME" == "${TMPDIR:-}"* ]]; then
    rm -rf "$TEST_HOME"
  fi
}

# ── Skill source registration ───────────────────────────────────────

@test "agentbrew skill source registered in state.yaml after add" {
  run "$DOTFILES_DIR/bin/dotfiles-plugin" add "$FIXTURE" --no-sync --no-doctor
  [ "$status" -eq 0 ]
  # The plugin's skills folder is registered as a skillSourceDirs entry.
  # Label is derived from the plugin name: `<name>-plugin`.
  run yq -r '.skillSourceDirs[] | select(.label == "simple-plugin-plugin") | .path' "$TEST_HOME/.config/agentbrew/state.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"plugin-fixtures/simple-plugin/plugins/agentbrew/skills"* ]]
}

@test "skill source registration preserves pre-existing entries" {
  "$DOTFILES_DIR/bin/dotfiles-plugin" add "$FIXTURE" --no-sync --no-doctor
  # The 'installed-skills' label from the pre-seeded state.yaml must still be present.
  run yq -r '.skillSourceDirs[] | select(.label == "installed-skills") | .label' "$TEST_HOME/.config/agentbrew/state.yaml"
  [ "$output" = "installed-skills" ]
}

@test "skill source registration is idempotent — re-add doesn't duplicate" {
  "$DOTFILES_DIR/bin/dotfiles-plugin" add "$FIXTURE" --no-sync --no-doctor
  "$DOTFILES_DIR/bin/dotfiles-plugin" add "$FIXTURE" --no-sync --no-doctor
  run yq '[.skillSourceDirs[] | select(.label == "simple-plugin-plugin")] | length' "$TEST_HOME/.config/agentbrew/state.yaml"
  [ "$output" = "1" ]
}

# ── Agentfile fragment merge ────────────────────────────────────────

@test "agentfile-fragment.yaml mcp entries merged into global Agentfile" {
  "$DOTFILES_DIR/bin/dotfiles-plugin" add "$FIXTURE" --no-sync --no-doctor
  run yq -r '.mcp[]' "$TEST_HOME/.config/agentbrew/Agentfile.yaml"
  # Pre-existing entries survive
  [[ "$output" == *"context7"* ]]
  [[ "$output" == *"playwright"* ]]
  # Plugin's new entry was added
  [[ "$output" == *"test-plugin-mcp"* ]]
}

@test "agentfile-fragment.yaml skills entries merged into global Agentfile" {
  "$DOTFILES_DIR/bin/dotfiles-plugin" add "$FIXTURE" --no-sync --no-doctor
  run yq -r '.skills[]' "$TEST_HOME/.config/agentbrew/Agentfile.yaml"
  # Pre-existing entries survive
  [[ "$output" == *"debug"* ]]
  # Plugin's new entry was added
  [[ "$output" == *"test-plugin-skill"* ]]
}

@test "agentfile-fragment merge is idempotent — re-add doesn't duplicate" {
  "$DOTFILES_DIR/bin/dotfiles-plugin" add "$FIXTURE" --no-sync --no-doctor
  "$DOTFILES_DIR/bin/dotfiles-plugin" add "$FIXTURE" --no-sync --no-doctor
  run yq '[.mcp[] | select(. == "test-plugin-mcp")] | length' "$TEST_HOME/.config/agentbrew/Agentfile.yaml"
  [ "$output" = "1" ]
  run yq '[.skills[] | select(. == "test-plugin-skill")] | length' "$TEST_HOME/.config/agentbrew/Agentfile.yaml"
  [ "$output" = "1" ]
}

# ── Rules fragment append ───────────────────────────────────────────

@test "rules-fragment.md appended to shared-rules.md with name-scoped markers" {
  "$DOTFILES_DIR/bin/dotfiles-plugin" add "$FIXTURE" --no-sync --no-doctor
  grep -q "<!-- plugin:simple-plugin:start -->" "$TEST_HOME/.config/agentbrew/shared-rules.md"
  grep -q "<!-- plugin:simple-plugin:end -->" "$TEST_HOME/.config/agentbrew/shared-rules.md"
  grep -q "TEST_SENTINEL_LINE: this exact phrase must show up" "$TEST_HOME/.config/agentbrew/shared-rules.md"
}

@test "rules-fragment append preserves pre-existing rules verbatim" {
  "$DOTFILES_DIR/bin/dotfiles-plugin" add "$FIXTURE" --no-sync --no-doctor
  grep -q "The plugin's rules-fragment must NOT touch this line" "$TEST_HOME/.config/agentbrew/shared-rules.md"
  grep -q "This line also must survive intact" "$TEST_HOME/.config/agentbrew/shared-rules.md"
}

@test "rules-fragment append is idempotent — re-add replaces inside markers, no duplication" {
  "$DOTFILES_DIR/bin/dotfiles-plugin" add "$FIXTURE" --no-sync --no-doctor
  local count_first
  count_first="$(grep -c "TEST_SENTINEL_LINE" "$TEST_HOME/.config/agentbrew/shared-rules.md")"
  [ "$count_first" -eq 1 ]
  "$DOTFILES_DIR/bin/dotfiles-plugin" add "$FIXTURE" --no-sync --no-doctor
  local count_second
  count_second="$(grep -c "TEST_SENTINEL_LINE" "$TEST_HOME/.config/agentbrew/shared-rules.md")"
  [ "$count_second" -eq 1 ]
  # Marker pair still appears exactly once. Use start-of-line anchor so
  # a plugin's rules-fragment content can mention the marker string
  # without inflating the count (it's a real-world risk — meta-docs
  # often refer to their own markers).
  local starts
  starts="$(grep -c '^<!-- plugin:simple-plugin:start -->$' "$TEST_HOME/.config/agentbrew/shared-rules.md")"
  [ "$starts" -eq 1 ]
}

# ── install-state tracks agentbrew-target writes for clean remove ───

@test "install-state.json records the agentbrew skill source label + agentfile entries" {
  "$DOTFILES_DIR/bin/dotfiles-plugin" add "$FIXTURE" --no-sync --no-doctor
  local state="$TEST_HOME/.config/dotfiles/plugins/simple-plugin/install-state.json"
  [ -f "$state" ]
  run jq -r '.skillSourceLabel' "$state"
  [ "$output" = "simple-plugin-plugin" ]
  # Agentfile fragment entries we added are tracked so remove can find them
  run jq -r '.agentfileMcpEntries[]' "$state"
  [[ "$output" == *"test-plugin-mcp"* ]]
  run jq -r '.agentfileSkillEntries[]' "$state"
  [[ "$output" == *"test-plugin-skill"* ]]
}
