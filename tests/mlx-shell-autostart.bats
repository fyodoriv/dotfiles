#!/usr/bin/env bats

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export ZDOTDIR="$HOME"
  export DOTFILES_DIR="$BATS_TEST_DIRNAME/.."
  export MLX_FIXTURE_CALLS="$BATS_TEST_TMPDIR/calls"
  export DOTFILES_ENDPOINT_HARDENING=0 DOTFILES_SHELL_MLX_AUTOSTART=1
  unset DOTFILES_MANAGED_ENDPOINT DOTFILES_ENDPOINT_AGENT_APPS
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
  printf '#!/bin/sh\nprintf "34359738368\\n"\n' > "$BATS_TEST_TMPDIR/bin/sysctl"
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
