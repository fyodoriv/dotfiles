#!/usr/bin/env bats

load test_helper

MODULE="$BATS_TEST_DIRNAME/../modules/codex/doctor.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home" DOTFILES_DIR="$BATS_TEST_DIRNAME/.."
  export DOTFILES_CODEX_APP_DIR="$TEST_DIR/ChatGPT.app"
  export DOTFILES_DOCTOR_FULL=true
  mkdir -p "$HOME/.local/bin" "$HOME/.codex" "$DOTFILES_CODEX_APP_DIR"
  printf '#!/bin/bash\ncase "$1" in --version) echo codex-cli 1.2.3;; login) exit 0;; esac\n' > "$HOME/.local/bin/codex"
  chmod +x "$HOME/.local/bin/codex"
  printf 'model = "example"\n' > "$HOME/.codex/config.toml"
  touch "$HOME/.codex/hooks.json"
  export PATH="$HOME/.local/bin:$PATH"
  failed_ids=""
  check() { eval "$3" >/dev/null 2>&1 || failed_ids="$failed_ids $1"; }
  check_advisory() { check "$@"; }
}

@test "doctor passes a working CLI, sign-in, config, hooks and ChatGPT app" {
  source "$MODULE"
  [ -z "$failed_ids" ]
}

@test "doctor reports missing binary even when the config directory exists" {
  rm "$HOME/.local/bin/codex"
  PATH=/usr/bin:/bin
  source "$MODULE"
  [[ "$failed_ids" == *codex.installed* ]]
}

@test "doctor reports malformed TOML and a stale configured CLI path" {
  printf 'model = [\n' > "$HOME/.codex/config.toml"
  source "$MODULE"
  [[ "$failed_ids" == *codex.config_valid* ]]
  printf '[mcp_servers.example.env]\nCODEX_CLI_PATH = "/missing/codex"\n' > "$HOME/.codex/config.toml"
  failed_ids=""
  source "$MODULE"
  [[ "$failed_ids" == *codex.cli_paths* ]]
}

@test "doctor reports signed-out CLI and missing ChatGPT app" {
  printf '#!/bin/bash\n[ "$1" = "--version" ]\n' > "$HOME/.local/bin/codex"
  rmdir "$DOTFILES_CODEX_APP_DIR"
  source "$MODULE"
  [[ "$failed_ids" == *codex.login* ]]
  [[ "$failed_ids" == *codex.app* ]]
}

@test "doctor bounds a stalled login check" {
  cat > "$HOME/.local/bin/codex" <<'STUB'
#!/bin/bash
case "$1" in
  --version) echo codex-cli 1.2.3 ;;
  login) exec sleep 10 ;;
esac
STUB
  source "$MODULE"
  [[ "$failed_ids" == *codex.login* ]]
}

@test "full profile skips absent Codex when AI tools are explicitly off" {
  export DOTFILES_PROFILE=full
  rm "$HOME/.local/bin/codex"
  rm -rf "$HOME/.codex"
  mkdir -p "$TEST_DIR/bin"
  printf '#!/bin/bash\necho false\n' > "$TEST_DIR/bin/chezmoi"
  chmod +x "$TEST_DIR/bin/chezmoi"
  PATH="$TEST_DIR/bin:/usr/bin:/bin"
  source "$MODULE"
  [ -z "$failed_ids" ]
}

@test "core profile diagnoses a synced Codex config whose enabled CLI is missing" {
  export DOTFILES_PROFILE=core
  rm "$HOME/.local/bin/codex"
  mkdir -p "$TEST_DIR/bin"
  printf '#!/bin/bash\necho true\n' > "$TEST_DIR/bin/chezmoi"
  chmod +x "$TEST_DIR/bin/chezmoi"
  PATH="$TEST_DIR/bin:/usr/bin:/bin"
  source "$MODULE"
  [[ "$failed_ids" == *codex.installed* ]]
}

@test "doctor rejects a directory used as CODEX_CLI_PATH" {
  printf 'CODEX_CLI_PATH = "%s"\n' "$HOME/.codex" > "$HOME/.codex/config.toml"
  source "$MODULE"
  [[ "$failed_ids" == *codex.cli_paths* ]]
}

@test "routine Codex checks do not start the CLI" {
  export DOTFILES_DOCTOR_FULL=false
  printf '#!/bin/bash\necho called >> "%s/calls"\nexit 1\n' "$TEST_DIR" > "$HOME/.local/bin/codex"
  source "$MODULE"
  [ ! -e "$TEST_DIR/calls" ]
  [ -z "$failed_ids" ]
}

@test "full doctor flag enables Codex runtime checks" {
  cat > "$HOME/.local/bin/codex" <<STUB
#!/bin/bash
printf '%s\n' "\$*" >> "$TEST_DIR/calls"
exit 0
STUB
  run bash "$DOTFILES_DIR/bin/dotfiles-doctor" --full --module codex --json
  rg -qx -- --version "$TEST_DIR/calls"
  rg -qx 'login status' "$TEST_DIR/calls"
  [[ "$output" == *codex.version* ]]
  [[ "$output" == *codex.login* ]]
}

@test "doctor list includes full-only Codex checks without enabling probes" {
  run bash "$DOTFILES_DIR/bin/dotfiles-doctor" --module codex --list
  [ "$status" -eq 0 ]
  [[ "$output" == *codex.version* ]]
  [[ "$output" == *codex.login* ]]
}

@test "full-only Codex check IDs can be skipped without the full flag" {
  local repo="$TEST_DIR/repo"
  mkdir -p "$repo/bin" "$repo/modules/codex"
  cp -R "$DOTFILES_DIR/lib" "$repo/lib"
  cp "$DOTFILES_DIR/bin/dotfiles-doctor" "$repo/bin/dotfiles-doctor"
  cp "$MODULE" "$repo/modules/codex/doctor.sh"
  run bash "$repo/bin/dotfiles-doctor" --skip codex.version
  [ "$status" -eq 0 ]
  rg -qx codex.version "$repo/.overrides"
}

@test "watch forwards full mode to each Codex audit" {
  WATCH_MAX_ITERATIONS=1 run bash "$DOTFILES_DIR/bin/dotfiles-doctor" --watch --full --module codex
  [ "$status" -eq 0 ]
  [[ "$output" == *"Codex CLI runs (codex --version)"* ]]
}
