#!/usr/bin/env bats

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home" OPTIONAL_REPO="$TEST_DIR/repo"
  export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share"
  export DOTFILES_USE_LOCAL_AI=false
  mkdir -p "$HOME" "$OPTIONAL_REPO/bin" "$OPTIONAL_REPO/modules/local-llm" "$TEST_DIR/bin"
  cp -R "$BATS_TEST_DIRNAME/../lib" "$OPTIONAL_REPO/lib"
  cp -R "$BATS_TEST_DIRNAME/../config" "$OPTIONAL_REPO/config"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor" "$OPTIONAL_REPO/bin/dotfiles-doctor"
  cp "$BATS_TEST_DIRNAME/../modules/local-llm/doctor.sh" "$OPTIONAL_REPO/modules/local-llm/doctor.sh"
  mkdir -p "$OPTIONAL_REPO/modules/local-ai"
  cp "$BATS_TEST_DIRNAME/../modules/local-ai/doctor.sh" "$OPTIONAL_REPO/modules/local-ai/doctor.sh"
  printf '#!/bin/sh\nexit 1\n' > "$TEST_DIR/bin/chezmoi"
  chmod +x "$TEST_DIR/bin/chezmoi"
  export PATH="$TEST_DIR/bin:$PATH"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "validation recognizes opted-out local AI check IDs" {
  printf 'local-llm.huggingface_cli\n' > "$OPTIONAL_REPO/.overrides"
  run bash "$OPTIONAL_REPO/bin/dotfiles-doctor" --validate-overrides
  [ "$status" -eq 0 ]
  [[ "$output" == *"All overrides are valid"* ]]
}

@test "skip accepts opted-out local AI check IDs" {
  run bash "$OPTIONAL_REPO/bin/dotfiles-doctor" --skip local-llm.huggingface_cli
  [ "$status" -eq 0 ]
  [[ "$output" == *"Added override"* ]]
}

install_optional_plugin() {
  local name="$1" root="$TEST_DIR/$1"
  mkdir -p "$root/doctor/example" "$root/doctor/unrelated"
  printf 'schema: 1\nname: %s\nversion: 1.0.0\ncapabilities:\n  sudo: false\ncontributes:\n  doctor_modules: doctor\n' "$name" > "$root/dotfiles-plugin.yaml"
  cat > "$root/doctor/example/doctor.sh" <<'SH'
check 'example.clean' 'selected module has a clean environment' '[ -z "${DOCTOR_TEST_SECRET:-}" ]' ''
SH
  printf 'touch "$HOME/unrelated-module-ran"\ncheck "unrelated.one" "wrong module" "false" ""\n' > "$root/doctor/unrelated/doctor.sh"
  bash "$BATS_TEST_DIRNAME/../bin/dotfiles-plugin" add --dev "$root" --yes >/dev/null
}

@test "a named plugin module runs only its checks through the sandbox" {
  install_optional_plugin fixture
  export DOCTOR_TEST_SECRET=not-a-real-secret
  run bash "$OPTIONAL_REPO/bin/dotfiles-doctor" --module example --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.[0].id')" = fixture/example.clean ]
  [ "$(printf '%s' "$output" | jq -r '.[0].status')" = pass ]
  [ ! -e "$HOME/unrelated-module-ran" ]
}

@test "a qualified plugin module selects one matching plugin" {
  install_optional_plugin first
  install_optional_plugin second
  run bash "$OPTIONAL_REPO/bin/dotfiles-doctor" --module second/example --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.[0].id')" = second/example.clean ]
  [ ! -e "$HOME/unrelated-module-ran" ]
}

@test "an ambiguous plugin module asks for a qualified module" {
  install_optional_plugin first
  install_optional_plugin second
  run bash "$OPTIONAL_REPO/bin/dotfiles-doctor" --module example
  [ "$status" -ne 0 ]
  [[ "$output" == *"first/example"* ]]
  [[ "$output" == *"second/example"* ]]
  [ ! -e "$HOME/unrelated-module-ran" ]
}

@test "validation recognizes both local AI LaunchAgent IDs with agents off" {
  export DOTFILES_LOCAL_AI_AGENTS=false
  printf 'local-ai.warmup_agent_loaded\nlocal-ai.ollama_agent_loaded\n' > "$OPTIONAL_REPO/.overrides"
  run bash "$OPTIONAL_REPO/bin/dotfiles-doctor" --validate-overrides
  [ "$status" -eq 0 ]
  [[ "$output" == *"All overrides are valid"* ]]
}

@test "local AI list mode enumerates conditional checks without host probes" {
  export PROBE_MARKER="$TEST_DIR/probed"
  for cmd in curl sysctl ollama launchctl; do
    printf '#!/bin/sh\nprintf probe >> "$PROBE_MARKER"\nexit 1\n' > "$TEST_DIR/bin/$cmd"
    chmod +x "$TEST_DIR/bin/$cmd"
    cp "$TEST_DIR/bin/$cmd" "$OPTIONAL_REPO/bin/$cmd"
  done
  run bash "$OPTIONAL_REPO/bin/dotfiles-doctor" --module local-ai --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"local-ai.ollama_agent_loaded"* ]]
  [[ "$output" == *"local-ai.lmstudio_primary"* ]]
  [[ "$output" == *"local-ai.ollama_primary"* ]]
  [ ! -e "$PROBE_MARKER" ]
}
