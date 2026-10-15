#!/usr/bin/env bats
# Tests for bin/dotfiles-pnpm-global-update: topgrade's built-in pnpm step runs
# `pnpm update -g`, which fails with ERR_PNPM_NO_PKG_MANIFEST when no global
# package was ever installed. The helper updates only when the manifest exists.

SCRIPT="$BATS_TEST_DIRNAME/../bin/dotfiles-pnpm-global-update"
TOPGRADE_CFG="$BATS_TEST_DIRNAME/../dot_config/topgrade.toml"

setup() {
  FIXTURE="$(mktemp -d)"
  mkdir -p "$FIXTURE/stub" "$FIXTURE/global/5/node_modules"
  export PNPM_LOG="$FIXTURE/pnpm.log"
  : > "$PNPM_LOG"
  export STUB_ROOT="$FIXTURE/global/5/node_modules"
  export DOTFILES_PNPM_BIN="$FIXTURE/stub/pnpm"
  cat > "$DOTFILES_PNPM_BIN" <<'STUB'
#!/bin/sh
echo "$*" >> "$PNPM_LOG"
case "$1 $2" in
  "root -g") echo "$STUB_ROOT" ;;
  "update -g") exit "${STUB_UPDATE_RC:-0}" ;;
esac
STUB
  chmod +x "$DOTFILES_PNPM_BIN"
}

teardown() {
  rm -rf "$FIXTURE"
}

@test "skips the update when no global manifest exists" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no global packages"* ]]
  ! grep -q '^update' "$PNPM_LOG"
}

@test "updates global packages when the manifest exists" {
  echo '{}' > "$FIXTURE/global/5/package.json"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q '^update -g$' "$PNPM_LOG"
}

@test "passes on a failed update" {
  echo '{}' > "$FIXTURE/global/5/package.json"
  export STUB_UPDATE_RC=3
  run "$SCRIPT"
  [ "$status" -eq 3 ]
}

@test "exits 0 when pnpm is not installed" {
  export DOTFILES_PNPM_BIN="$FIXTURE/stub/missing-pnpm"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pnpm not found"* ]]
}

@test "topgrade disables its pnpm step and runs the helper instead" {
  awk '/^disable = \[/,/^\]/' "$TOPGRADE_CFG" | grep -q '^  "pnpm",'
  grep -q 'dotfiles-pnpm-global-update' "$TOPGRADE_CFG"
}
