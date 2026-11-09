#!/usr/bin/env bats

load test_helper

REPO_ROOT="$BATS_TEST_DIRNAME/.."
REAL_CHEZMOI="$(command -v chezmoi || true)"

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home" XDG_CONFIG_HOME="$TEST_DIR/home/.config"
  export BUNDLE_OBSERVED="$TEST_DIR/bundle" BREW_CALLS="$TEST_DIR/calls" LATER_STEP="$TEST_DIR/later"
  mkdir -p "$HOME" "$TEST_DIR/bin" "$TEST_DIR/work"
  cat > "$TEST_DIR/bin/brew" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$BREW_CALLS"
case "$1" in
  info) printf '%s\n' '{"casks":[]}' ;;
  bundle)
    for arg in "$@"; do case "$arg" in --file=*) cp "${arg#--file=}" "$BUNDLE_OBSERVED";; esac; done
    [ -z "${UNRELATED_BUNDLE_FAILURE:-}" ] || exit 7 ;;
  list) exit 1 ;;
  install) [ -z "${FAIL_OPTIONAL:-}" ] || exit 1 ;;
esac
SH
  chmod +x "$TEST_DIR/bin/brew"
  export PATH="$TEST_DIR/bin:$PATH"
}

teardown() { rm -rf "$TEST_DIR"; }

write_config() {
  cat > "$TEST_DIR/config.yaml" <<YAML
data:
  profile: full
  is_enterprise: false
  use_local_ai: false
  use_ai_tools: true
  brew_skip: []
  opencode_desktop: ${1:-false}
YAML
}

run_brew_stage() {
  chezmoi --config "$TEST_DIR/config.yaml" --source "$REPO_ROOT" --destination "$HOME" execute-template \
    < "$REPO_ROOT/.chezmoiscripts/run_onchange_brew.sh.tmpl" > "$TEST_DIR/work/brew.sh" || return "$?"
  bash -e -c 'bash "$1" && touch "$LATER_STEP"' _ "$TEST_DIR/work/brew.sh"
}

@test "default full apply does not install OpenCode Desktop" {
  write_config false
  run run_brew_stage
  [ "$status" -eq 0 ]
  ! grep -q 'opencode-desktop' "$BUNDLE_OBSERVED"
  ! grep -q 'opencode-desktop' "$BREW_CALLS"
}

@test "an excluded OpenCode agent wins over the cask opt-in" {
  write_config true
  mkdir -p "$HOME/.config/agentbrew"
  printf 'excludeAgents: [opencode]\n' > "$HOME/.config/agentbrew/Agentfile.yaml"
  run run_brew_stage
  [ "$status" -eq 0 ]
  ! grep -q 'opencode-desktop' "$BREW_CALLS"
}

@test "chezmoi init preserves an explicit OpenCode Desktop opt-in" {
  [ -n "$REAL_CHEZMOI" ] || skip "chezmoi is unavailable"
  local dir="$TEST_DIR/reinit" config="$TEST_DIR/reinit/chezmoi.yaml"
  mkdir -p "$dir/home"
  printf 'sourceDir: "%s"\ndata:\n  opencode_desktop: true\n' "$REPO_ROOT" > "$config"
  HOME="$dir/home" "$REAL_CHEZMOI" init --source "$REPO_ROOT" --config "$config" --config-path "$config" --promptDefaults >/dev/null 2>&1
  [ "$(yq -r '.data.opencode_desktop' "$config")" = true ]
}

@test "opt-in cask failure warns and later apply steps continue" {
  write_config true
  FAIL_OPTIONAL=1 run run_brew_stage
  [ "$status" -eq 0 ]
  [ -e "$LATER_STEP" ]
  grep -q 'install --cask opencode-desktop' "$BREW_CALLS"
  [[ "$output" == *"OpenCode Desktop"*"optional"* ]]
}

@test "an unrelated bundle failure remains fatal" {
  write_config true
  UNRELATED_BUNDLE_FAILURE=1 run run_brew_stage
  [ "$status" -eq 7 ]
  [ ! -e "$LATER_STEP" ]
}
