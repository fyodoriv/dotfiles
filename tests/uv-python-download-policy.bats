#!/usr/bin/env bats

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/source"
  mkdir -p "$TEST_HOME" "$TEST_DOTFILES" "$TEST_DIR/bin"
  export HOME="$TEST_HOME"
  export XDG_CONFIG_HOME="$TEST_HOME/.config" XDG_DATA_HOME="$TEST_HOME/.local/share"
  export XDG_STATE_HOME="$TEST_HOME/.local/state" XDG_CACHE_HOME="$TEST_HOME/.cache"
  mkdir -p "$XDG_CONFIG_HOME/chezmoi"
  export UV_POLICY_CONFIG="$XDG_CONFIG_HOME/chezmoi/chezmoi.yaml"
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
case "$1" in
  -m) printf '%s\n' arm64 ;;
  -s) printf '%s\n' Darwin ;;
  *) exit 2 ;;
esac
SH
  cat > "$TEST_DIR/bin/uv" <<'SH'
#!/bin/sh
printf '%s|%s\n' "$*" "${UV_PYTHON_DOWNLOADS:-unset}" >> "$UV_POLICY_CALLS"
case "$*" in
  'python find'|'python find 3.13')
    [ -n "${UV_POLICY_PYTHON:-}" ] || exit 1
    printf '%s\n' "$UV_POLICY_PYTHON" ;;
  'tool dir --bin') printf '%s\n' "$HOME/.local/bin" ;;
  'tool dir') printf '%s\n' "$HOME/.local/share/uv/tools" ;;
  'python install 3.13'|'tool upgrade --all'|'tool list'|'tool install '*) exit 0 ;;
  *) exit 90 ;;
esac
SH
  chmod +x "$TEST_DIR/bin/"{chezmoi,uname,uv}
  export PATH="$TEST_DIR/bin:$PATH"
  [ "$(command -v uv)" = "$TEST_DIR/bin/uv" ]
}

teardown() { rm -rf "$TEST_DIR"; }

set_policy() {
  printf 'data:\n  profile: full\n  uv_python_downloads_never: %s\n  use_local_ai: true\n  is_enterprise: false\n' "$1" > "$UV_POLICY_CONFIG"
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
  [ "$command" = 'command -v uv >/dev/null 2>&1 || exit 0; UV_PYTHON_DOWNLOADS=never uv tool upgrade --all' ]
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

@test "uv policy constrains the apply-time tool installer" {
  set_policy true
  CHEZMOI_SOURCE_DIR="$TEST_DOTFILES" run bash "$BATS_TEST_DIRNAME/../.chezmoiscripts/run_after_uv-tools.sh"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^tool install .*|never$' "$UV_POLICY_CALLS")" -eq 4 ]
  ! grep -q '^tool install .*|unset$' "$UV_POLICY_CALLS"
}

@test "uv policy creates a missing user config and preserves an existing one" {
  mkdir -p "$TEST_DOTFILES/dot_config/uv"
  cp "$BATS_TEST_DIRNAME/../dot_config/uv/create_uv.toml" "$TEST_DOTFILES/dot_config/uv/"
  cp "$BATS_TEST_DIRNAME/../.chezmoiignore" "$TEST_DOTFILES/"
  local config="$XDG_CONFIG_HOME/uv/uv.toml"
  set_policy false
  run chezmoi apply
  [ "$status" -eq 0 ] || { printf '%s\n' "$output"; return 1; }
  [ ! -e "$config" ]

  run "$BATS_TEST_DIRNAME/../bin/dotfiles-config" set uv_python_downloads_never true
  [ "$status" -eq 0 ]
  run chezmoi apply
  [ "$status" -eq 0 ]
  [ "$(yq -p=toml -r '."python-downloads"' "$config")" = never ]

  printf 'python-downloads = "manual"\n# Existing user preference\n' > "$config"
  cp "$config" "$TEST_DIR/original-config"
  run chezmoi apply
  [ "$status" -eq 0 ]
  cmp -s "$config" "$TEST_DIR/original-config"
  run "$BATS_TEST_DIRNAME/../bin/dotfiles-config" set uv_python_downloads_never false
  [ "$status" -eq 0 ]
  run chezmoi apply
  [ "$status" -eq 0 ]
  cmp -s "$config" "$TEST_DIR/original-config"
}

@test "uv policy Doctor checks the top-level user configuration only when enabled" {
  local block="$TEST_DIR/security-policy"
  awk '
    /^_uv_python_download_policy_matches\(\)/ { print_block = 1 }
    /Git Configuration Safety/ { if (print_block) exit }
    print_block { print }
  ' "$BATS_TEST_DIRNAME/../modules/security/doctor.sh" > "$block"
  cat > "$TEST_DIR/doctor" <<'SH'
#!/bin/bash
check() {
  if eval "$3"; then printf 'pass %s\n' "$1"
  else printf 'fail %s\n' "$1"; fi
}
source "$1"
SH
  set_policy false
  run bash "$TEST_DIR/doctor" "$block"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  set_policy true
  run bash "$TEST_DIR/doctor" "$block"
  [ "$status" -eq 0 ]
  [ "$output" = 'fail security.uv_python_downloads_never' ]

  mkdir -p "$XDG_CONFIG_HOME/uv"
  printf 'python-downloads = "never"\n' > "$XDG_CONFIG_HOME/uv/uv.toml"
  run bash "$TEST_DIR/doctor" "$block"
  [ "$status" -eq 0 ]
  [ "$output" = 'pass security.uv_python_downloads_never' ]

  printf '[tool]\npython-downloads = "never"\n' > "$XDG_CONFIG_HOME/uv/uv.toml"
  run bash "$TEST_DIR/doctor" "$block"
  [ "$status" -eq 0 ]
  [ "$output" = 'fail security.uv_python_downloads_never' ]
}

@test "uv policy stops the full local-LLM installer before dependent work without Python" {
  set_policy true
  local script="$TEST_DIR/local-llm-full" name
  for name in pipx hf huggingface-cli; do
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\n' "$TEST_DIR/downstream-calls" > "$TEST_DIR/bin/$name"
    chmod +x "$TEST_DIR/bin/$name"
  done
  export LOCAL_LLM_SENTINEL="$TEST_DIR/model-sentinel" HF_HOME="$TEST_DIR/model-cache"
  export LOCAL_LLM_MODEL_REPO="fixture/model"
  touch "$LOCAL_LLM_SENTINEL"
  chezmoi execute-template < "$BATS_TEST_DIRNAME/../.chezmoiscripts/run_after_install_local_llm.sh.tmpl" > "$script"
  run bash "$script"
  [ "$status" -eq 0 ]
  [[ "$output" == *"automatic Python downloads are disabled"* ]]
  if [ -s "$TEST_DIR/downstream-calls" ]; then
    echo "Expected no pipx or model command without an installed interpreter."
    return 1
  fi
}

@test "uv policy leaves Poetry in place without an installed interpreter" {
  set_policy true
  local lib="$BATS_TEST_DIRNAME/../lib/poetry-repair.sh"
  local poetry="$HOME/.local/bin/poetry" venv="$HOME/Library/Application Support/pypoetry/venv"
  mkdir -p "$(dirname "$poetry")" "$venv"
  printf 'fixture poetry\n' > "$poetry"

  run bash -c 'source "$1"; poetry_repair_to_uv "$2"' policy "$lib" "$poetry"
  if [ "$status" -ne 1 ]; then
    printf 'Expected missing-Python refusal, got exit %s.\n' "$status"
    return 1
  fi
  [ -f "$poetry" ] && [ -d "$venv" ]
  [ ! -e "$poetry.bak" ] && [ ! -e "$venv.bak" ]
  [ "$(cat "$UV_POLICY_CALLS")" = 'python find|never' ]

  export UV_POLICY_PYTHON="$TEST_DIR/python-available"
  cp /bin/echo "$UV_POLICY_PYTHON"
  : > "$UV_POLICY_CALLS"
  run bash -c 'source "$1"; poetry_repair_to_uv "$2"' policy "$lib" "$poetry"
  [ "$status" -eq 0 ]
  [ -f "$poetry.bak" ] && [ -d "$venv.bak" ]
  grep -Fxq 'tool install poetry|never' "$UV_POLICY_CALLS"
}

@test "uv policy leaves the unused default config absent with custom XDG config" {
  set_policy true
  export XDG_CONFIG_HOME="$TEST_HOME/custom-config"
  mkdir -p "$TEST_DOTFILES/dot_config/uv" "$XDG_CONFIG_HOME/uv"
  cp "$BATS_TEST_DIRNAME/../dot_config/uv/create_uv.toml" "$TEST_DOTFILES/dot_config/uv/"
  cp "$BATS_TEST_DIRNAME/../.chezmoiignore" "$TEST_DOTFILES/"
  printf 'python-downloads = "manual"\n' > "$XDG_CONFIG_HOME/uv/uv.toml"
  cp "$XDG_CONFIG_HOME/uv/uv.toml" "$TEST_DIR/original"
  run chezmoi apply
  [ "$status" -eq 0 ] || { printf '%s\n' "$output"; return 1; }
  [ ! -e "$HOME/.config/uv/uv.toml" ]
  cmp -s "$XDG_CONFIG_HOME/uv/uv.toml" "$TEST_DIR/original"
}
