#!/usr/bin/env bats
# Regression tests for auto-discovering additive dotfiles overlays.

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_BASE="$TEST_DIR/dotfiles"
  TEST_REPOS="$TEST_HOME/apps/tooling"
  TEST_APPLIED="$TEST_REPOS/dotfiles-applied"
  TEST_OVERLAY="$TEST_REPOS/dotfiles-acme"

  mkdir -p "$TEST_HOME" "$TEST_BASE" "$TEST_APPLIED" "$TEST_OVERLAY"
  printf 'mcp: []\n' > "$TEST_APPLIED/Agentfile.yaml"
  printf 'mcp: []\n' > "$TEST_OVERLAY/Agentfile.yaml"

  git -C "$TEST_BASE" init -q
  git -C "$TEST_BASE" remote add origin git@example.test:dotfiles.git
  git -C "$TEST_APPLIED" init -q
  git -C "$TEST_APPLIED" remote add origin git@example.test:dotfiles.git
  git -C "$TEST_OVERLAY" init -q
  git -C "$TEST_OVERLAY" remote add origin git@example.test:dotfiles-acme.git

  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_BASE"
  export DOTFILES_REPOS_DIR="$TEST_HOME/apps"
  unset EXTRA_OVERLAY_ROOT

  # Keep the test on auto-discovery instead of machine-specific chezmoi data.
  chezmoi() { return 1; }
  export -f chezmoi

  source "$BATS_TEST_DIRNAME/../lib/plugin.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "auto-discovery skips a deployed checkout of the base repository" {
  [ "$(plugin_overlay_root)" = "$TEST_OVERLAY" ]
}

@test "an explicit overlay path takes precedence over source-replica filtering" {
  EXTRA_OVERLAY_ROOT="$TEST_APPLIED"
  [ "$(plugin_overlay_root)" = "$TEST_APPLIED" ]
}

@test "a colon-separated overlay root is refused with status 2" {
  EXTRA_OVERLAY_ROOT="$TEST_OVERLAY:$TEST_APPLIED" run plugin_overlay_root
  [ "$status" -eq 2 ]
  [[ "$output" == *"single path"* ]]
}

@test "--no-discover skips auto-discovery but keeps the explicit root" {
  run plugin_overlay_root --no-discover
  [ "$status" -eq 1 ]
  EXTRA_OVERLAY_ROOT="$TEST_OVERLAY" run plugin_overlay_path --no-discover validate
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_OVERLAY/validate" ]
}

@test "plugin_overlay_path joins the discovered root and the path" {
  run plugin_overlay_path Agentfile.yaml
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_OVERLAY/Agentfile.yaml" ]
}

@test "no core file copies the overlay lookup inline (issue #145 step 3)" {
  cd "$BATS_TEST_DIRNAME/.."
  run bash -c "grep -rnE 'dig \"extra_overlay_root\"|\\\$\\{?EXTRA_OVERLAY_ROOT' bin lib modules .chezmoiscripts git-hooks home 2>/dev/null | grep -v '^lib/plugin.sh:' | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#'"
  echo "$output"
  [ -z "$output" ]
}
