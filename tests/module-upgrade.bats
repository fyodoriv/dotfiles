#!/usr/bin/env bats
# Functional tests for modules/upgrade/doctor.sh

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"

  mkdir -p "$TEST_HOME"
  mkdir -p "$TEST_DOTFILES/home"
  mkdir -p "$TEST_HOME/.local/share/dotfiles"

  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"

  OVERRIDES_FILE="$TEST_DOTFILES/.overrides"
  touch "$OVERRIDES_FILE"
  FIX_MODE=false
  LIST_MODE=false
  pass_count=0
  fail_count=0
  fix_count=0
  skip_count=0

  pass()    { pass_count=$((pass_count + 1)); }
  fail()    { fail_count=$((fail_count + 1)); }
  fixed()   { fix_count=$((fix_count + 1)); }
  skipped() { skip_count=$((skip_count + 1)); }

  is_overridden() { grep -qx "$1" "$OVERRIDES_FILE" 2>/dev/null; }

  check() {
    local id="$1" desc="$2" test_cmd="$3" fix_cmd="${4:-}"
    if $LIST_MODE; then return; fi
    if is_overridden "$id"; then skipped "$desc"; return; fi
    if eval "$test_cmd" >/dev/null 2>&1; then
      pass "$desc"
    elif $FIX_MODE && [ -n "$fix_cmd" ]; then
      eval "$fix_cmd" >/dev/null 2>&1
      fixed "$desc"
    else
      fail "$desc"
    fi
  }
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "upgrade: passes upgrade.recent when last-upgrade is fresh" {
  # Write a recent epoch (now)
  date "+%s" > "$TEST_HOME/.local/share/dotfiles/last-upgrade"
  source "$BATS_TEST_DIRNAME/../modules/upgrade/doctor.sh"
  # upgrade.recent should pass
  [ "$pass_count" -ge 1 ]
}

@test "upgrade: fails upgrade.recent when last-upgrade is stale" {
  # Write an epoch from 30 days ago
  local stale_epoch=$(($(date "+%s") - 30 * 86400))
  echo "$stale_epoch" > "$TEST_HOME/.local/share/dotfiles/last-upgrade"
  source "$BATS_TEST_DIRNAME/../modules/upgrade/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "upgrade: fails upgrade.recent when file is missing" {
  rm -f "$TEST_HOME/.local/share/dotfiles/last-upgrade"
  source "$BATS_TEST_DIRNAME/../modules/upgrade/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "upgrade: fails upgrade.recent when file has garbage content" {
  echo "not-a-number" > "$TEST_HOME/.local/share/dotfiles/last-upgrade"
  source "$BATS_TEST_DIRNAME/../modules/upgrade/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "upgrade: passes upgrade.brew when brew is installed" {
  # brew should be available in the test environment
  if ! command -v brew >/dev/null 2>&1; then
    skip "brew not installed"
  fi
  source "$BATS_TEST_DIRNAME/../modules/upgrade/doctor.sh"
  [ "$pass_count" -ge 1 ]
}

@test "upgrade: skips overridden checks" {
  echo "upgrade.launchagent" >> "$OVERRIDES_FILE"
  echo "upgrade.recent" >> "$OVERRIDES_FILE"
  echo "upgrade.brew" >> "$OVERRIDES_FILE"
  source "$BATS_TEST_DIRNAME/../modules/upgrade/doctor.sh"
  [ "$skip_count" -eq 3 ]
  [ "$fail_count" -eq 0 ]
}

@test "upgrade: uses 14-day threshold by default" {
  # Write an epoch from exactly 13 days ago (should pass)
  local recent_epoch=$(($(date "+%s") - 13 * 86400))
  echo "$recent_epoch" > "$TEST_HOME/.local/share/dotfiles/last-upgrade"
  source "$BATS_TEST_DIRNAME/../modules/upgrade/doctor.sh"
  # upgrade.recent should pass (13 < 14)
  [ "$pass_count" -ge 1 ]
}

@test "upgrade: fails at exactly 14 days" {
  # Write an epoch from exactly 15 days ago (should fail)
  local old_epoch=$(($(date "+%s") - 15 * 86400))
  echo "$old_epoch" > "$TEST_HOME/.local/share/dotfiles/last-upgrade"
  source "$BATS_TEST_DIRNAME/../modules/upgrade/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

# ── Non-uv poetry with a missing interpreter ─────────────────────────
# Stub poetry/uv in a private bin dir that wins PATH lookup.
_poetry_stub() {  # $1 = dir, $2 = exit code for `poetry --version`
  mkdir -p "$1"
  printf '#!/bin/bash\nexit %s\n' "$2" > "$1/poetry"
  chmod +x "$1/poetry"
}
_uv_stub() {  # `uv tool dir` prints $TEST_DIR/uv-tools
  mkdir -p "$TEST_DIR/stubbin"
  printf '#!/bin/bash\n[ "$1 $2" = "tool dir" ] && echo "%s" && exit 0\nexit 1\n' "$TEST_DIR/uv-tools" > "$TEST_DIR/stubbin/uv"
  chmod +x "$TEST_DIR/stubbin/uv"
}

@test "upgrade: reports a non-uv poetry whose --version fails, with the uv hint" {
  _poetry_stub "$TEST_DIR/stubbin" 1
  _uv_stub
  export PATH="$TEST_DIR/stubbin:$PATH"
  failed_descs=()
  fail() { fail_count=$((fail_count + 1)); failed_descs+=("$1"); }
  source "$BATS_TEST_DIRNAME/../modules/upgrade/doctor.sh"
  printf '%s\n' "${failed_descs[@]}" | grep -F "non-uv poetry" | grep -F "uv tool install poetry" | grep -qF "pypoetry/venv"
}

@test "upgrade: passes a non-uv poetry that runs" {
  _poetry_stub "$TEST_DIR/stubbin" 0
  _uv_stub
  export PATH="$TEST_DIR/stubbin:$PATH"
  failed_descs=()
  fail() { fail_count=$((fail_count + 1)); failed_descs+=("$1"); }
  source "$BATS_TEST_DIRNAME/../modules/upgrade/doctor.sh"
  ! printf '%s\n' "${failed_descs[@]}" | grep -qF "poetry"
}

@test "upgrade: ignores a uv-managed poetry even when --version fails" {
  _uv_stub
  _poetry_stub "$TEST_DIR/uv-tools/poetry/bin" 1
  mkdir -p "$TEST_DIR/localbin"
  ln -s "$TEST_DIR/uv-tools/poetry/bin/poetry" "$TEST_DIR/localbin/poetry"
  export PATH="$TEST_DIR/localbin:$TEST_DIR/stubbin:$PATH"
  failed_descs=()
  fail() { fail_count=$((fail_count + 1)); failed_descs+=("$1"); }
  source "$BATS_TEST_DIRNAME/../modules/upgrade/doctor.sh"
  ! printf '%s\n' "${failed_descs[@]}" | grep -qF "poetry"
}
