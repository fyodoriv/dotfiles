#!/usr/bin/env bats

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export ZDOTDIR="$HOME"
  export DOTFILES_DIR="$BATS_TEST_DIRNAME/.."
  export XDG_CONFIG_HOME="$HOME/.config" XDG_STATE_HOME="$HOME/.local/state"
  export XDG_DATA_HOME="$HOME/.local/share" XDG_CACHE_HOME="$HOME/.cache"
  export MLX_FIXTURE_CALLS="$BATS_TEST_TMPDIR/calls"
  export HF_HUB_CACHE="$BATS_TEST_TMPDIR/hub"
  export DOTFILES_ENDPOINT_HARDENING=0 DOTFILES_SHELL_MLX_AUTOSTART=1
  unset DOTFILES_MANAGED_ENDPOINT DOTFILES_ENDPOINT_AGENT_APPS
  unset DOTFILES_SHELL_MLX_ENDPOINT_HARDENING
  unset DOTFILES_ALLOW_PUBLISHER_NA_PYTHON DOTFILES_FORCE_MLX_STARTUP
  unset DOTFILES_JETBRAINS_FAST_SHELL MLX_FIXTURE_READY
  unset MLX_MODEL_OVERRIDE HF_HUB_OFFLINE
  mkdir -p "$HOME/.cache" "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/venv/bin"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  : > "$MLX_FIXTURE_CALLS"

  cat > "$BATS_TEST_TMPDIR/bin/curl" <<'STUB'
#!/bin/sh
printf 'curl\n' >> "$MLX_FIXTURE_CALLS"
[ "${MLX_FIXTURE_READY:-0}" -eq 1 ]
STUB
  cat > "$BATS_TEST_TMPDIR/bin/uv" <<'STUB'
#!/bin/sh
printf 'uv\n' >> "$MLX_FIXTURE_CALLS"
printf '%s\n' "$HOME/.cache/python-fixture"
STUB
  cat > "$HOME/.cache/python-fixture" <<'STUB'
#!/bin/sh
printf 'python\n' >> "$MLX_FIXTURE_CALLS"
STUB
  printf '#!/bin/sh\nprintf "arm64\\n"\n' > "$BATS_TEST_TMPDIR/bin/uname"
  cat > "$BATS_TEST_TMPDIR/bin/sysctl" <<'STUB'
#!/bin/sh
case "$2" in
  machdep.cpu.brand_string) printf 'Apple test fixture\n' ;;
  hw.memsize) printf '34359738368\n' ;;
  *) exit 1 ;;
esac
STUB
  printf '#!/bin/sh\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/sleep"
  chmod +x "$BATS_TEST_TMPDIR/bin/"{curl,uv,uname,sysctl,sleep} "$HOME/.cache/python-fixture"
  awk '
    /^# ── MLX local LLM server/ { copy = 1 }
    /^# `oc` selects/ { exit }
    copy { print }
  ' "$DOTFILES_DIR/home/zshrc.ai-tools" > "$BATS_TEST_TMPDIR/startup"
  [ -s "$BATS_TEST_TMPDIR/startup" ]
}

install_mlx_entry_point() {
  local pkg="$BATS_TEST_TMPDIR/venv"
  cat > "$pkg/bin/python3.15" <<'STUB'
#!/bin/sh
shift
printf 'mlx offline=%s %s\n' "${HF_HUB_OFFLINE:-unset}" "$*" >> "$MLX_FIXTURE_CALLS"
STUB
  printf '#!%s\n' "$pkg/bin/python3.15" > "$pkg/bin/mlx_lm.server"
  printf 'version = 3.15.2\n' > "$pkg/pyvenv.cfg"
  chmod +x "$pkg/bin/mlx_lm.server" "$pkg/bin/python3.15"
  ln -s "$pkg/bin/mlx_lm.server" "$BATS_TEST_TMPDIR/bin/mlx_lm.server"
  if [ "${1:-}" = complete ]; then
    mkdir -p "$pkg/lib/python3.15/site-packages/mlx_lm"
    : > "$pkg/lib/python3.15/site-packages/mlx_lm/server.py"
  fi
}

make_model_files() {
  mkdir -p "$1"
  printf '{}\n' > "$1/config.json"
  printf 'fixture weights\n' > "$1/model.safetensors"
}

source_interactive_startup() {
  /bin/zsh -f -i -c 'source "$1"' fixture "$BATS_TEST_TMPDIR/startup"
}

@test "MLX shell startup skips a hardened endpoint before any probe" {
  install_mlx_entry_point complete
  export DOTFILES_ENDPOINT_HARDENING=1 DOTFILES_FORCE_MLX_STARTUP=1
  run source_interactive_startup
  [ "$status" -eq 0 ]
  if [ -s "$MLX_FIXTURE_CALLS" ]; then
    printf 'Unexpected hardened startup commands:\n'
    sort -u "$MLX_FIXTURE_CALLS"
    return 1
  fi
}

@test "MLX shell startup skips a managed endpoint even with the local setting off" {
  install_mlx_entry_point complete
  export DOTFILES_MANAGED_ENDPOINT=1
  run source_interactive_startup
  [ "$status" -eq 0 ]
  [ ! -s "$MLX_FIXTURE_CALLS" ]
}

@test "MLX shell startup reads the shared endpoint path list in zsh" {
  install_mlx_entry_point complete
  mkdir -p "$HOME/Example Endpoint.app"
  export DOTFILES_ENDPOINT_AGENT_APPS="$HOME/missing:$HOME/Example Endpoint.app"
  run source_interactive_startup
  [ "$status" -eq 0 ]
  [ ! -s "$MLX_FIXTURE_CALLS" ]
}

@test "MLX shell startup skips a disabled feature before any probe" {
  install_mlx_entry_point complete
  export DOTFILES_SHELL_MLX_AUTOSTART=0
  run source_interactive_startup
  [ "$status" -eq 0 ]
  [ ! -s "$MLX_FIXTURE_CALLS" ]
}

@test "MLX shell startup skips an absent or stale package before any probe" {
  run source_interactive_startup
  [ "$status" -eq 0 ]
  [ ! -s "$MLX_FIXTURE_CALLS" ]
  install_mlx_entry_point stale
  run source_interactive_startup
  [ "$status" -eq 0 ]
  [ ! -s "$MLX_FIXTURE_CALLS" ]
}

@test "MLX shell startup keeps an already ready service" {
  install_mlx_entry_point complete
  export MLX_FIXTURE_READY=1
  run source_interactive_startup
  [ "$status" -eq 0 ]
  [ "$(cat "$MLX_FIXTURE_CALLS")" = curl ]
}

@test "MLX shell startup invokes the complete package once on loopback" {
  install_mlx_entry_point complete
  export MLX_MODEL_OVERRIDE="$BATS_TEST_TMPDIR/model"
  make_model_files "$MLX_MODEL_OVERRIDE"
  run source_interactive_startup
  [ "$status" -eq 0 ]
  [ "$(grep -c '^mlx ' "$MLX_FIXTURE_CALLS")" -eq 1 ]
  grep -q '^mlx .* --port 8080 --host 127.0.0.1 ' "$MLX_FIXTURE_CALLS"
  ! grep -Eq '^(uv|python)$' "$MLX_FIXTURE_CALLS"
}

@test "MLX shell startup refuses a launcher whose interpreter disappeared" {
  install_mlx_entry_point complete
  rm "$BATS_TEST_TMPDIR/venv/bin/python3.15"
  run source_interactive_startup
  [ "$status" -eq 0 ]
  [ ! -s "$MLX_FIXTURE_CALLS" ]
}

@test "MLX shell startup refuses package files for a different Python version" {
  install_mlx_entry_point complete
  mv "$BATS_TEST_TMPDIR/venv/lib/python3.15" "$BATS_TEST_TMPDIR/venv/lib/python3.14"
  run source_interactive_startup
  [ "$status" -eq 0 ]
  [ ! -s "$MLX_FIXTURE_CALLS" ]
}

@test "MLX shell startup never starts an uncached remote model" {
  install_mlx_entry_point complete
  export MLX_MODEL_OVERRIDE=example/fixture
  run source_interactive_startup
  [ "$status" -eq 0 ]
  [ "$(cat "$MLX_FIXTURE_CALLS")" = curl ]
}

@test "MLX shell startup uses a cached revision as a local offline model" {
  install_mlx_entry_point complete
  export MLX_MODEL_OVERRIDE=example/fixture
  local cache="$HF_HUB_CACHE/models--example--fixture"
  local revision=1111111111111111111111111111111111111111
  local snapshot="$cache/snapshots/$revision"
  mkdir -p "$cache/refs"
  printf '%s' "$revision" > "$cache/refs/main"
  make_model_files "$snapshot"
  run source_interactive_startup
  [ "$status" -eq 0 ]
  [ "$(grep -c '^mlx ' "$MLX_FIXTURE_CALLS")" -eq 1 ]
  grep -Fq "mlx offline=1 --model $snapshot --port 8080 --host 127.0.0.1" "$MLX_FIXTURE_CALLS"
}

@test "MLX shell startup requires every indexed weight shard to be present" {
  install_mlx_entry_point complete
  export MLX_MODEL_OVERRIDE="$BATS_TEST_TMPDIR/sharded"
  mkdir -p "$MLX_MODEL_OVERRIDE"
  local index="$MLX_MODEL_OVERRIDE/model.safetensors.index.json"
  local first=model-00001-of-00002.safetensors second=model-00002-of-00002.safetensors
  printf '{}\n' > "$MLX_MODEL_OVERRIDE/config.json"
  printf 'fixture weights 1\n' > "$MLX_MODEL_OVERRIDE/$first"
  printf '{"weight_map":{"first":"%s","second":"%s"}}\n' "$first" "$second" > "$index"
  run source_interactive_startup
  [ "$status" -eq 0 ]
  [ "$(cat "$MLX_FIXTURE_CALLS")" = curl ]

  : > "$MLX_MODEL_OVERRIDE/$second"
  : > "$MLX_FIXTURE_CALLS"
  run source_interactive_startup
  [ "$status" -eq 0 ]
  [ "$(cat "$MLX_FIXTURE_CALLS")" = curl ]

  printf 'fixture weights 2\n' > "$MLX_MODEL_OVERRIDE/$second"
  : > "$MLX_FIXTURE_CALLS"
  run source_interactive_startup
  [ "$status" -eq 0 ]
  [ "$(grep -c '^mlx offline=1 ' "$MLX_FIXTURE_CALLS")" -eq 1 ]

  printf 'invalid index\n' > "$index"
  : > "$MLX_FIXTURE_CALLS"
  run source_interactive_startup
  [ "$status" -eq 0 ]
  [ "$(cat "$MLX_FIXTURE_CALLS")" = curl ]
}

@test "MLX shell settings render default and explicitly disabled values" {
  local config="$BATS_TEST_TMPDIR/chezmoi.yaml"
  printf 'data:\n  repos_dir: apps\n  dotfiles_dir: apps/tooling/dotfiles\n' > "$config"
  run chezmoi --config "$config" --source "$DOTFILES_DIR" --destination "$HOME" execute-template \
    < "$DOTFILES_DIR/dot_config/dotfiles/env.sh.tmpl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DOTFILES_SHELL_MLX_AUTOSTART=0"* ]]
  [[ "$output" == *"DOTFILES_SHELL_MLX_ENDPOINT_HARDENING=0"* ]]
  printf '  use_local_ai: true\n' >> "$config"
  run chezmoi --config "$config" --source "$DOTFILES_DIR" --destination "$HOME" execute-template \
    < "$DOTFILES_DIR/dot_config/dotfiles/env.sh.tmpl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DOTFILES_SHELL_MLX_AUTOSTART=1"* ]]
  printf '  shell_mlx_autostart: false\n  endpoint_hardening: true\n' >> "$config"
  run chezmoi --config "$config" --source "$DOTFILES_DIR" --destination "$HOME" execute-template \
    < "$DOTFILES_DIR/dot_config/dotfiles/env.sh.tmpl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DOTFILES_SHELL_MLX_AUTOSTART=0"* ]]
  [[ "$output" == *"DOTFILES_SHELL_MLX_ENDPOINT_HARDENING=1"* ]]
}

@test "MLX Doctor reports one advisory for an incomplete installed package" {
  install_mlx_entry_point stale
  run env USE_LOCAL_AI=true bash -c '
    check() { if [ "$1" = local-llm.mlx_lm ]; then echo required; fi; }
    check_advisory() {
      if [ "$1" = local-llm.mlx_lm ]; then
        if eval "$3"; then echo ready; else echo warning; fi
      fi
    }
    source "$DOTFILES_DIR/lib/dotfiles-endpoint-paths.sh"
    source "$DOTFILES_DIR/modules/local-llm/doctor.sh"
  '
  [ "$status" -eq 0 ]
  [ "$output" = warning ]
  [ ! -s "$MLX_FIXTURE_CALLS" ]
}
