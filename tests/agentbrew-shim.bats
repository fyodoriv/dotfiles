#!/usr/bin/env bats

load test_helper

bats_require_minimum_version 1.5.0

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME" "$TEST_DIR/bin"
  unset DOTFILES_REPOS_DIR
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "agentbrew shim: runs dist CLI from tooling checkout" {
  local base="$TEST_DIR/repos"
  mkdir -p "$base/tooling/agentbrew/dist"
  cat > "$base/tooling/agentbrew/dist/cli.js" <<'EOF'
#!/bin/sh
printf 'dist:%s\n' "$*"
EOF
  chmod +x "$base/tooling/agentbrew/dist/cli.js"

  run env DOTFILES_REPOS_DIR="$base" PATH="/usr/bin:/bin" "$BATS_TEST_DIRNAME/../bin/agentbrew" status --json

  [ "$status" -eq 0 ]
  [ "$output" = "dist:status --json" ]
}

# Write a dist CLI, a fake agent Node, and a fake codesign that reports the
# given Team ID for every binary. Prints the checkout base.
agent_node_fixture() {
  local team_id="$1" base="$TEST_DIR/repos"
  mkdir -p "$base/tooling/agentbrew/dist" "$TEST_DIR/agent-node/bin" "$TEST_DIR/fake-bin"
  cat > "$base/tooling/agentbrew/dist/cli.js" <<'EOF'
#!/bin/sh
printf 'dist:%s\n' "$*"
EOF
  cat > "$TEST_DIR/agent-node/bin/node" <<'EOF'
#!/bin/sh
printf 'agent-node:%s\n' "$*"
EOF
  cat > "$TEST_DIR/fake-bin/codesign" <<EOF
#!/bin/sh
echo "TeamIdentifier=$team_id" >&2
EOF
  chmod +x "$base/tooling/agentbrew/dist/cli.js" "$TEST_DIR/agent-node/bin/node" "$TEST_DIR/fake-bin/codesign"
  printf '%s' "$base"
}

@test "agentbrew shim: runs dist CLI on DOTFILES_AGENT_NODE_BIN" {
  local base
  base="$(agent_node_fixture EXAMPLE123)"

  run env DOTFILES_REPOS_DIR="$base" PATH="$TEST_DIR/fake-bin:/usr/bin:/bin" \
    DOTFILES_AGENT_NODE_BIN="$TEST_DIR/agent-node/bin/node" \
    "$BATS_TEST_DIRNAME/../bin/agentbrew" auto-sync install

  [ "$status" -eq 0 ]
  [ "$output" = "agent-node:$base/tooling/agentbrew/dist/cli.js auto-sync install" ]
}

@test "agentbrew shim: ignores a missing or non-executable DOTFILES_AGENT_NODE_BIN" {
  local base
  base="$(agent_node_fixture EXAMPLE123)"
  chmod -x "$TEST_DIR/agent-node/bin/node"

  run env DOTFILES_REPOS_DIR="$base" PATH="$TEST_DIR/fake-bin:/usr/bin:/bin" \
    DOTFILES_AGENT_NODE_BIN="$TEST_DIR/agent-node/bin/node" \
    "$BATS_TEST_DIRNAME/../bin/agentbrew" status
  [ "$status" -eq 0 ]
  [ "$output" = "dist:status" ]

  run env DOTFILES_REPOS_DIR="$base" PATH="$TEST_DIR/fake-bin:/usr/bin:/bin" \
    DOTFILES_AGENT_NODE_BIN="$TEST_DIR/missing/node" \
    "$BATS_TEST_DIRNAME/../bin/agentbrew" status
  [ "$status" -eq 0 ]
  [ "$output" = "dist:status" ]
}

@test "agentbrew shim: ignores an agent Node from the blocked publisher" {
  local base
  base="$(agent_node_fixture HX7739G8FX)"

  run env DOTFILES_REPOS_DIR="$base" PATH="$TEST_DIR/fake-bin:/usr/bin:/bin" \
    DOTFILES_AGENT_NODE_BIN="$TEST_DIR/agent-node/bin/node" \
    "$BATS_TEST_DIRNAME/../bin/agentbrew" status

  [ "$status" -eq 0 ]
  [ "$output" = "dist:status" ]
}

@test "agentbrew shim: falls back to tsx dev CLI when dist is absent" {
  local base="$TEST_DIR/repos"
  mkdir -p "$base/agentbrew/node_modules/.bin" "$base/agentbrew/src"
  cat > "$base/agentbrew/node_modules/.bin/tsx" <<'EOF'
#!/bin/sh
printf 'tsx:%s\n' "$*"
EOF
  chmod +x "$base/agentbrew/node_modules/.bin/tsx"

  run env DOTFILES_REPOS_DIR="$base" PATH="/usr/bin:/bin" "$BATS_TEST_DIRNAME/../bin/agentbrew" sync

  [ "$status" -eq 0 ]
  [ "$output" = "tsx:$base/agentbrew/src/cli.ts sync" ]
}

@test "agentbrew shim: skips a self-recursive dist CLI stub" {
  local base="$TEST_DIR/repos"
  mkdir -p "$base/tooling/agentbrew/dist" "$base/tooling/agentbrew/node_modules/.bin" "$base/tooling/agentbrew/src"
  cat > "$base/tooling/agentbrew/dist/cli.js" <<EOF
#!/bin/bash
exec $base/tooling/agentbrew/dist/cli.js "\$@"
EOF
  chmod +x "$base/tooling/agentbrew/dist/cli.js"
  cat > "$base/tooling/agentbrew/node_modules/.bin/tsx" <<'EOF'
#!/bin/sh
printf 'tsx:%s\n' "$*"
EOF
  chmod +x "$base/tooling/agentbrew/node_modules/.bin/tsx"

  run env DOTFILES_REPOS_DIR="$base" PATH="/usr/bin:/bin" "$BATS_TEST_DIRNAME/../bin/agentbrew" sync

  [ "$status" -eq 0 ]
  [ "$output" = "tsx:$base/tooling/agentbrew/src/cli.ts sync" ]
}

@test "agentbrew shim: resolves lib path when invoked through a symlink" {
  local base="$TEST_DIR/repos"
  mkdir -p "$base/tooling/agentbrew/dist"
  cat > "$base/tooling/agentbrew/dist/cli.js" <<'EOF'
#!/bin/sh
printf 'dist:%s\n' "$*"
EOF
  chmod +x "$base/tooling/agentbrew/dist/cli.js"
  ln -s "$BATS_TEST_DIRNAME/../bin/agentbrew" "$TEST_DIR/bin/agentbrew"

  run env DOTFILES_REPOS_DIR="$base" PATH="$TEST_DIR/bin:/usr/bin:/bin" "$TEST_DIR/bin/agentbrew" status

  [ "$status" -eq 0 ]
  [ "$output" = "dist:status" ]
}

@test "agentbrew shim: delegates to later PATH binary when no checkout exists" {
  cat > "$TEST_DIR/bin/agentbrew" <<'EOF'
#!/bin/sh
printf 'path:%s\n' "$*"
EOF
  chmod +x "$TEST_DIR/bin/agentbrew"

  run env DOTFILES_REPOS_DIR="$TEST_DIR/missing" PATH="$TEST_DIR/bin:/usr/bin:/bin" "$BATS_TEST_DIRNAME/../bin/agentbrew" status

  [ "$status" -eq 0 ]
  [ "$output" = "path:status" ]
}

@test "agentbrew shim: skips its own PATH symlink when no checkout exists" {
  ln -s "$BATS_TEST_DIRNAME/../bin/agentbrew" "$TEST_DIR/bin/agentbrew"

  run -127 env DOTFILES_REPOS_DIR="$TEST_DIR/missing" PATH="$TEST_DIR/bin:/usr/bin:/bin" "$TEST_DIR/bin/agentbrew" status

  [ "$status" -eq 127 ]
  [[ "$output" == *"agentbrew checkout not found"* ]]
}

@test "agentbrew shim: fails clearly when no checkout or fallback binary exists" {
  run -127 env DOTFILES_REPOS_DIR="$TEST_DIR/missing" PATH="/usr/bin:/bin" "$BATS_TEST_DIRNAME/../bin/agentbrew" status

  [ "$status" -eq 127 ]
  [[ "$output" == *"agentbrew checkout not found"* ]]
}

@test "zshrc.ai-tools does not define an agentbrew shell function" {
  run grep -E '^[[:space:]]*agentbrew\(\)' "$BATS_TEST_DIRNAME/../home/zshrc.ai-tools"
  [ "$status" -ne 0 ]
}
