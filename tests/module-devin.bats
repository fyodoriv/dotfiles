#!/usr/bin/env bats
# Functional tests for modules/devin/doctor.sh

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"

  mkdir -p "$TEST_HOME/.config/devin"
  mkdir -p "$TEST_HOME/.local/share/devin/cli/_versions/current/bin"
  mkdir -p "$TEST_DOTFILES/home"
  mkdir -p "$TEST_DOTFILES/bin"

  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"
  export DOTFILES_REPOS_DIR="$TEST_DIR/repos"
  mkdir -p "$DOTFILES_REPOS_DIR"

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
    local id="$1" desc="$2" test_cmd="$3" fix_cmd="$4"
    if $LIST_MODE; then return; fi
    if is_overridden "$id"; then skipped "$desc"; return; fi
    if eval "$test_cmd" >/dev/null 2>&1; then
      pass "$desc"
    elif $FIX_MODE && [ -n "$fix_cmd" ]; then
      if eval "$fix_cmd" >/dev/null 2>&1; then fixed "$desc"; else fail "$desc"; fi
    else
      fail "$desc"
    fi
  }

  # Create network-watchdog as executable
  echo '#!/bin/bash' > "$TEST_DOTFILES/bin/network-watchdog"
  chmod +x "$TEST_DOTFILES/bin/network-watchdog"

  # Create devin binary with Mach-O magic bytes so binary_not_stub passes
  printf '\xcf\xfa\xed\xfe' > "$TEST_HOME/.local/share/devin/cli/_versions/current/bin/devin"
  chmod +x "$TEST_HOME/.local/share/devin/cli/_versions/current/bin/devin"

  # Create zshrc
  echo 'export DEVIN_MODEL=gpt-5-5-xhigh-priority' > "$TEST_DOTFILES/home/zshrc"

  # Clean config with the expected default model
  echo '{"agent":{"model":"gpt-5-5-xhigh-priority"}}' > "$TEST_HOME/.config/devin/config.json"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "devin: passes when all checks satisfied" {
  source "$BATS_TEST_DIRNAME/../modules/devin/doctor.sh"
  # network + binary + model checks
  [ "$pass_count" -ge 3 ]
  [ "$fail_count" -eq 0 ]
}

@test "devin: fails when executables missing" {
  rm -f "$TEST_DOTFILES/bin/network-watchdog"
  rm -f "$TEST_HOME/.local/share/devin/cli/_versions/current/bin/devin"
  # Restrict PATH to prevent finding real system binaries
  export PATH="$TEST_DIR/bin:/usr/bin:/bin"
  source "$BATS_TEST_DIRNAME/../modules/devin/doctor.sh"
  [ "$fail_count" -ge 2 ]
}

@test "devin: fails when devin config model is not GPT-5.5 XHigh Thinking Fast" {
  echo '{"model":"claude-sonnet"}' > "$TEST_HOME/.config/devin/config.json"
  source "$BATS_TEST_DIRNAME/../modules/devin/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "devin: fix mode makes network-watchdog executable" {
  chmod -x "$TEST_DOTFILES/bin/network-watchdog"
  FIX_MODE=true
  source "$BATS_TEST_DIRNAME/../modules/devin/doctor.sh"
  [ "$fix_count" -ge 1 ]
  [ -x "$TEST_DOTFILES/bin/network-watchdog" ]
}

@test "devin: fix mode rolls back stub current binary to newest real version" {
  local versions_dir="$TEST_HOME/.local/share/devin/cli/_versions"
  rm -rf "$versions_dir/current"
  mkdir -p "$versions_dir/2026.5.1-1/bin" "$versions_dir/2026.5.2-1/bin" "$versions_dir/2026.5.3-1/bin"
  printf '\xcf\xfa\xed\xfe' > "$versions_dir/2026.5.1-1/bin/devin"
  printf '\xcf\xfa\xed\xfe' > "$versions_dir/2026.5.2-1/bin/devin"
  cat > "$versions_dir/2026.5.3-1/bin/devin" <<'STUB'
#!/bin/bash
echo "stub devin"
STUB
  chmod +x "$versions_dir"/2026.5.{1,2,3}-1/bin/devin
  touch -t 202605010101 "$versions_dir/2026.5.1-1"
  touch -t 202605020101 "$versions_dir/2026.5.2-1"
  touch -t 202605030101 "$versions_dir/2026.5.3-1"
  ln -sfn "$versions_dir/2026.5.3-1" "$versions_dir/current"

  FIX_MODE=true
  source "$BATS_TEST_DIRNAME/../modules/devin/doctor.sh"

  [ "$fix_count" -ge 1 ]
  [ "$(readlink "$versions_dir/current")" = "$versions_dir/2026.5.2-1" ]
}

@test "devin: fix mode reports failure when no real binary can replace a stub" {
  local versions_dir="$TEST_HOME/.local/share/devin/cli/_versions"
  rm -rf "$versions_dir/current"
  mkdir -p "$versions_dir/2026.5.3-1/bin"
  cat > "$versions_dir/2026.5.3-1/bin/devin" <<'STUB'
#!/bin/bash
echo "stub devin"
STUB
  chmod +x "$versions_dir/2026.5.3-1/bin/devin"
  ln -sfn "$versions_dir/2026.5.3-1" "$versions_dir/current"

  FIX_MODE=true
  source "$BATS_TEST_DIRNAME/../modules/devin/doctor.sh"

  [ "$fail_count" -ge 1 ]
  [ "$(readlink "$versions_dir/current")" = "$versions_dir/2026.5.3-1" ]
}

@test "devin: overrides skip checks" {
  echo "devin.binary_exists" >> "$OVERRIDES_FILE"
  echo "devin.model_default" >> "$OVERRIDES_FILE"
  source "$BATS_TEST_DIRNAME/../modules/devin/doctor.sh"
  [ "$skip_count" -ge 2 ]
}
