#!/usr/bin/env bats

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export ZDOTDIR="$HOME"
  export DOTFILES_DIR="$BATS_TEST_DIRNAME/.."
  export XDG_CONFIG_HOME="$HOME/.config" XDG_STATE_HOME="$HOME/.local/state"
  export XDG_DATA_HOME="$HOME/.local/share" XDG_CACHE_HOME="$HOME/.cache"
  export MLX_FIXTURE_CALLS="$BATS_TEST_TMPDIR/calls"
  export DOTFILES_ENDPOINT_HARDENING=0 DOTFILES_SHELL_MLX_AUTOSTART=1
  unset DOTFILES_MANAGED_ENDPOINT DOTFILES_ENDPOINT_AGENT_APPS
  unset DOTFILES_SHELL_MLX_ENDPOINT_HARDENING
  unset DOTFILES_ALLOW_PUBLISHER_NA_PYTHON DOTFILES_FORCE_MLX_STARTUP
  unset DOTFILES_JETBRAINS_FAST_SHELL MLX_FIXTURE_READY
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
  cat > "$pkg/bin/mlx_lm.server" <<'STUB'
#!/bin/sh
printf 'mlx %s\n' "$*" >> "$MLX_FIXTURE_CALLS"
STUB
  chmod +x "$pkg/bin/mlx_lm.server"
  ln -s "$pkg/bin/mlx_lm.server" "$BATS_TEST_TMPDIR/bin/mlx_lm.server"
  if [ "${1:-}" = complete ]; then
    mkdir -p "$pkg/lib/python3.15/site-packages/mlx_lm"
    : > "$pkg/lib/python3.15/site-packages/mlx_lm/server.py"
  fi
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
  run source_interactive_startup
  [ "$status" -eq 0 ]
  [ "$(grep -c '^mlx ' "$MLX_FIXTURE_CALLS")" -eq 1 ]
  grep -q '^mlx .* --port 8080 --host 127.0.0.1 ' "$MLX_FIXTURE_CALLS"
  ! grep -Eq '^(uv|python)$' "$MLX_FIXTURE_CALLS"
}

@test "MLX shell settings render default and explicitly disabled values" {
  local config="$BATS_TEST_TMPDIR/chezmoi.yaml"
  printf 'data:\n  repos_dir: apps\n  dotfiles_dir: apps/tooling/dotfiles\n' > "$config"
  run chezmoi --config "$config" --source "$DOTFILES_DIR" --destination "$HOME" execute-template \
    < "$DOTFILES_DIR/dot_config/dotfiles/env.sh.tmpl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DOTFILES_SHELL_MLX_AUTOSTART=1"* ]]
  [[ "$output" == *"DOTFILES_SHELL_MLX_ENDPOINT_HARDENING=0"* ]]
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
