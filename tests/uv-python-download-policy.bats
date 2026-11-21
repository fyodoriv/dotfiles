#!/usr/bin/env bats

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/source"
  mkdir -p "$TEST_HOME" "$TEST_DOTFILES" "$TEST_DIR/bin"
  export HOME="$TEST_HOME"
  export UV_POLICY_CONFIG="$TEST_DIR/chezmoi.yaml"
  export UV_POLICY_CHEZMOI="$(command -v chezmoi)"
  export UV_POLICY_SOURCE="$TEST_DOTFILES"
  export UV_POLICY_CALLS="$TEST_DIR/uv-calls"
  : > "$UV_POLICY_CALLS"
  unset UV_PYTHON_DOWNLOADS UV_POLICY_PYTHON

  cat > "$TEST_DIR/bin/chezmoi" <<'SH'
#!/bin/sh
exec "$UV_POLICY_CHEZMOI" --config "$UV_POLICY_CONFIG" \
  --source "$UV_POLICY_SOURCE" --destination "$HOME" --no-tty "$@"
SH
  cat > "$TEST_DIR/bin/uname" <<'SH'
#!/bin/sh
[ "$1" = -m ] || exit 2
printf '%s\n' arm64
SH
  cat > "$TEST_DIR/bin/uv" <<'SH'
#!/bin/sh
printf '%s|%s\n' "$*" "${UV_PYTHON_DOWNLOADS:-unset}" >> "$UV_POLICY_CALLS"
case "$*" in
  'python find 3.13')
    [ -n "${UV_POLICY_PYTHON:-}" ] || exit 1
    printf '%s\n' "$UV_POLICY_PYTHON" ;;
  'python install 3.13'|'tool upgrade --all') exit 0 ;;
  *) exit 90 ;;
esac
SH
  chmod +x "$TEST_DIR/bin/"{chezmoi,uname,uv}
  export PATH="$TEST_DIR/bin:$PATH"
  [ "$(command -v uv)" = "$TEST_DIR/bin/uv" ]
}

teardown() { rm -rf "$TEST_DIR"; }

set_policy() {
  printf 'data:\n  uv_python_downloads_never: %s\n  use_local_ai: true\n  is_enterprise: false\n' "$1" > "$UV_POLICY_CONFIG"
}

render_topgrade() {
  chezmoi execute-template < "$BATS_TEST_DIRNAME/../dot_config/topgrade.toml.tmpl" > "$TEST_DIR/topgrade.toml"
}

stage_apply_install() {
  awk '
    /Ad-hoc sign uv pythons/ { print "fi"; exit }
    { print }
  ' "$BATS_TEST_DIRNAME/../.chezmoiscripts/run_after_uv-python-setup.sh" > "$TEST_DIR/install"
  bash -n "$TEST_DIR/install"
}

stage_local_llm() {
  chezmoi execute-template < "$BATS_TEST_DIRNAME/../.chezmoiscripts/run_after_install_local_llm.sh.tmpl" |
    awk '
      /^_LL_SENTINEL=/ { variables = 1 }
      /^_resolve_uv_python\(\)/ { resolver = 1 }
      /^_pipx_package_present\(\)/ { exit }
      !variables || resolver { print }
      END { print "_resolve_uv_python" }
    ' > "$TEST_DIR/local-llm"
  bash -n "$TEST_DIR/local-llm"
}

@test "uv policy preserves the default scheduled update" {
  set_policy false
  render_topgrade
  ! yq -p=toml -e '.misc.disable | any_c(. == "uv")' "$TEST_DIR/topgrade.toml"
  ! yq -p=toml -e '.commands["uv tools (installed Python only)"]' "$TEST_DIR/topgrade.toml"
}

@test "uv policy replaces the combined scheduled step with tool upgrades only" {
  set_policy true
  render_topgrade
  yq -p=toml -e '.misc.disable | any_c(. == "uv")' "$TEST_DIR/topgrade.toml"
  local command
  command="$(yq -p=toml -r '.commands["uv tools (installed Python only)"]' "$TEST_DIR/topgrade.toml")"
  [ "$command" = 'UV_PYTHON_DOWNLOADS=never uv tool upgrade --all' ]
  run /bin/bash -c "$command"
  [ "$status" -eq 0 ]
  [ "$(cat "$UV_POLICY_CALLS")" = 'tool upgrade --all|never' ]
}

@test "uv policy leaves the normal apply-time installer available" {
  set_policy false
  stage_apply_install
  run /bin/bash "$TEST_DIR/install"
  [ "$status" -eq 0 ]
  [ "$(cat "$UV_POLICY_CALLS")" = 'python install 3.13|unset' ]
}

@test "uv policy skips the apply-time installer when no managed Python exists" {
  set_policy true
  stage_apply_install
  run /bin/bash "$TEST_DIR/install"
  [ "$status" -eq 0 ]
  [[ "$output" == *"automatic Python downloads are disabled"* ]]
  [ ! -s "$UV_POLICY_CALLS" ]
}

@test "uv policy keeps the local-LLM installer on an existing interpreter only" {
  set_policy true
  stage_local_llm
  run /bin/bash "$TEST_DIR/local-llm"
  [ "$status" -eq 1 ]
  [[ "$output" == *"automatic Python downloads are disabled"* ]]
  [ "$(cat "$UV_POLICY_CALLS")" = 'python find 3.13|never' ]

  export UV_POLICY_PYTHON="$TEST_DIR/python3.13"
  cp /bin/echo "$UV_POLICY_PYTHON"
  : > "$UV_POLICY_CALLS"
  run /bin/bash "$TEST_DIR/local-llm"
  [ "$status" -eq 0 ]
  [ "$output" = "$UV_POLICY_PYTHON" ]
  [ "$(cat "$UV_POLICY_CALLS")" = 'python find 3.13|never' ]
}
