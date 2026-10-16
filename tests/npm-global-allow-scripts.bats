#!/usr/bin/env bats
# Tests for bin/dotfiles-npm-global-scripts: global npm CLIs that need install
# scripts. npm 11+ blocks those scripts unless allowed, which leaves the CLI
# installed but broken. The helper reads the list from
# data/npm-global-allow-scripts.json and reinstalls with --allow-scripts.

SCRIPT="$BATS_TEST_DIRNAME/../bin/dotfiles-npm-global-scripts"
TOPGRADE_CFG="$BATS_TEST_DIRNAME/../dot_config/topgrade.toml.tmpl"

setup() {
  FIXTURE="$(mktemp -d)"
  mkdir -p "$FIXTURE/prefix/bin" "$FIXTURE/stub"
  export NPM_LOG="$FIXTURE/npm.log"
  : > "$NPM_LOG"
  export STUB_PREFIX="$FIXTURE/prefix"
  export STUB_INSTALLED='{"dependencies":{"@railway/cli":{"version":"5.63.4"},"other":{"version":"1.0.0"}}}'
  export STUB_OUTDATED='{}'
  export DOTFILES_NPM_BIN="$FIXTURE/stub/npm"
  export DOTFILES_NPM_ALLOW_SCRIPTS_DATA="$FIXTURE/list.json"
  echo '[{"package":"@railway/cli","bin":"railway"}]' > "$DOTFILES_NPM_ALLOW_SCRIPTS_DATA"
  cat > "$DOTFILES_NPM_BIN" <<'STUB'
#!/bin/sh
echo "$*" >> "$NPM_LOG"
case "$1 $2" in
  "prefix -g") echo "$STUB_PREFIX" ;;
  "ls -g") echo "$STUB_INSTALLED" ;;
  "outdated -g") echo "$STUB_OUTDATED"; exit 1 ;;
  "install -g") [ -n "${STUB_FIX_BIN:-}" ] && printf '#!/bin/sh\necho 5.66.0\n' > "$STUB_PREFIX/bin/$STUB_FIX_BIN" && chmod +x "$STUB_PREFIX/bin/$STUB_FIX_BIN"; exit 0 ;;
esac
STUB
  chmod +x "$DOTFILES_NPM_BIN"
}

teardown() { rm -rf "$FIXTURE"; }

_good_bin() { printf '#!/bin/sh\necho 5.66.0\n' > "$STUB_PREFIX/bin/railway"; chmod +x "$STUB_PREFIX/bin/railway"; }
_broken_bin() { printf '#!/bin/sh\necho "could not find the CLI binary" >&2\nexit 1\n' > "$STUB_PREFIX/bin/railway"; chmod +x "$STUB_PREFIX/bin/railway"; }

@test "shipped list declares @railway/cli with its bin" {
  run jq -e '.[] | select(.package=="@railway/cli" and .bin=="railway")' \
    "$BATS_TEST_DIRNAME/../data/npm-global-allow-scripts.json"
  [ "$status" -eq 0 ]
}

@test "outdated declared CLI is installed with --allow-scripts" {
  _good_bin
  export STUB_OUTDATED='{"@railway/cli":{"current":"5.63.4","latest":"5.66.0"}}'
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qx 'install -g --allow-scripts=@railway/cli @railway/cli@latest' "$NPM_LOG"
}

@test "up-to-date working CLI triggers no install" {
  _good_bin
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  ! grep -q '^install' "$NPM_LOG"
}

@test "up-to-date but broken CLI is repaired by reinstall" {
  _broken_bin
  export STUB_FIX_BIN=railway
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qx 'install -g --allow-scripts=@railway/cli @railway/cli@latest' "$NPM_LOG"
}

@test "CLI still broken after install exits 1 with a clear message" {
  _broken_bin
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"railway --version failed"* ]]
}

@test "declared CLI that is not installed is skipped" {
  export STUB_INSTALLED='{"dependencies":{"other":{"version":"1.0.0"}}}'
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  ! grep -q '^install' "$NPM_LOG"
}

@test "--dry-run prints the npm command and does not run it" {
  _good_bin
  export STUB_OUTDATED='{"@railway/cli":{"current":"5.63.4","latest":"5.66.0"}}'
  run "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"npm install -g --allow-scripts=@railway/cli @railway/cli@latest"* ]]
  ! grep -q '^install' "$NPM_LOG"
}

@test "topgrade [commands] wires the helper" {
  grep -q 'dotfiles-npm-global-scripts' "$TOPGRADE_CFG"
}
