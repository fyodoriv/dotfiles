#!/usr/bin/env bats

REPO_ROOT="$BATS_TEST_DIRNAME/.."
MEMORY_CMD="$REPO_ROOT/bin/dotfiles-memory"
DOTFILES_CMD="$REPO_ROOT/bin/dotfiles"

setup() {
  TEST_DIR="$(mktemp -d)"
  STUB_DIR="$TEST_DIR/bin"
  mkdir -p "$STUB_DIR"
  export AGENTBREW_LOG="$TEST_DIR/agentbrew.log"
  export PATH="$STUB_DIR:/usr/bin:/bin"
  export DOTFILES_MEMORY_AGENTBREW_BIN="$STUB_DIR/agentbrew"
  cat > "$STUB_DIR/agentbrew" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$AGENTBREW_LOG"
STUB
  chmod +x "$STUB_DIR/agentbrew"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "dotfiles-memory forwards every subcommand to agentbrew memory" {
  run "$MEMORY_CMD" pack verify example --json

  [ "$status" -eq 0 ]
  grep -qx 'memory pack verify example --json' "$AGENTBREW_LOG"
}

@test "dotfiles memory dispatch preserves the compatibility shim" {
  run "$DOTFILES_CMD" memory doctor --json

  [ "$status" -eq 0 ]
  grep -qx 'memory doctor --json' "$AGENTBREW_LOG"
}

@test "dotfiles-memory fails with an actionable error when agentbrew is absent" {
  rm "$STUB_DIR/agentbrew"

  run "$MEMORY_CMD" doctor

  [ "$status" -eq 1 ]
  [[ "$output" == *"agentbrew not found on PATH"* ]]
}

@test "dotfiles-memory help names agentbrew as the lifecycle owner" {
  run "$MEMORY_CMD" --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"delegates to agentbrew memory"* ]]
}
