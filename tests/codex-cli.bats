#!/usr/bin/env bats

load test_helper

SCRIPT="$BATS_TEST_DIRNAME/../bin/dotfiles-install-codex"

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home" CALL_LOG="$TEST_DIR/calls"
  export CODEX_TEST_BIN="$TEST_DIR/node/bin"
  mkdir -p "$HOME/.local/bin" "$CODEX_TEST_BIN"
  cat > "$CODEX_TEST_BIN/npm" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$CALL_LOG"
case "$1" in
  prefix) dirname "$CODEX_TEST_BIN" ;;
  install)
    printf '#!/bin/bash\necho codex-cli 1.2.3\n' > "$CODEX_TEST_BIN/codex"
    chmod +x "$CODEX_TEST_BIN/codex" ;;
esac
STUB
  chmod +x "$CODEX_TEST_BIN/npm"
  export PATH="$CODEX_TEST_BIN:$PATH"
}

@test "install repairs missing codex despite a stale npm package entry" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/.local/bin/codex")" = "$CODEX_TEST_BIN/codex" ]
  run "$HOME/.local/bin/codex" --version
  [ "$status" -eq 0 ]
  grep -q '^install -g @openai/codex@latest$' "$CALL_LOG"
}

@test "repeat apply reuses the working CLI but upgrade reinstalls it" {
  bash "$SCRIPT"
  : > "$CALL_LOG"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  ! grep -q '^install' "$CALL_LOG"
  run bash "$SCRIPT" --upgrade
  [ "$status" -eq 0 ]
  grep -q '^install -g @openai/codex@latest$' "$CALL_LOG"
}

@test "install preserves an owner executable at the link destination" {
  printf 'owner executable\n' > "$HOME/.local/bin/codex"
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [ "$(cat "$HOME/.local/bin/codex")" = 'owner executable' ]
}

@test "blocked Node publisher prevents npm execution" {
  mkdir -p "$HOME/.local/state/dotfiles"
  touch "$HOME/.local/state/dotfiles/endpoint-node-publisher-blocked"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "$CALL_LOG" ]
}

@test "AI setup installs ChatGPT and invokes the managed npm installer" {
  grep -q 'cask "chatgpt"' "$BATS_TEST_DIRNAME/../.chezmoiscripts/run_onchange_brew.sh.tmpl"
  grep -q dotfiles-install-codex "$BATS_TEST_DIRNAME/../.chezmoiscripts/run_after_codex.sh.tmpl"
}

@test "upkeep checks the real Codex version and sign-in and uses one upgrade helper" {
  for skill in update-tooling tooling-checkup; do
    grep -q 'codex --version' "$BATS_TEST_DIRNAME/../skills/$skill/SKILL.md"
    grep -q 'codex login status' "$BATS_TEST_DIRNAME/../skills/$skill/SKILL.md"
    grep -q 'dotfiles-install-codex.*--upgrade' "$BATS_TEST_DIRNAME/../skills/$skill/SKILL.md"
  done
}
