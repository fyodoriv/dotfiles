#!/usr/bin/env bats
# Tests for modules/resilience/doctor.sh

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"
  mkdir -p "$TEST_HOME" "$TEST_DOTFILES/modules/resilience" "$TEST_DOTFILES/bin" "$TEST_DOTFILES/lib"
  cp "$BATS_TEST_DIRNAME/../modules/resilience/doctor.sh" "$TEST_DOTFILES/modules/resilience/"
  # doctor.sh sources this helper at load time.
  cp "$BATS_TEST_DIRNAME/../lib/agent-keepawake.sh" "$TEST_DOTFILES/lib/"
  cp "$BATS_TEST_DIRNAME/../lib/run-with-timeout.sh" "$TEST_DOTFILES/lib/"
  cp "$BATS_TEST_DIRNAME/../lib/dotfiles-arch.sh" "$TEST_DOTFILES/lib/"
  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"

  OVERRIDES_FILE="$TEST_DOTFILES/.overrides"; touch "$OVERRIDES_FILE"
  FIX_MODE=false; LIST_MODE=false
  pass_count=0; fail_count=0; fix_count=0; skip_count=0; warn_count=0
  pass()    { pass_count=$((pass_count + 1)); }
  fail()    { fail_count=$((fail_count + 1)); }
  fixed()   { fix_count=$((fix_count + 1)); }
  skipped() { skip_count=$((skip_count + 1)); }
  audit_warn() { warn_count=$((warn_count + 1)); }
  is_overridden() { grep -qx "$1" "$OVERRIDES_FILE" 2>/dev/null; }
  check_advisory() {
    local id="$1" desc="$2" test_cmd="$3" fix_cmd="${4:-}"
    $LIST_MODE && return; is_overridden "$id" && { skipped "$desc"; return; }
    if eval "$test_cmd" >/dev/null 2>&1; then pass "$desc"
    else audit_warn "$desc"; fi
  }
  check() {
    local id="$1" desc="$2" test_cmd="$3" fix_cmd="${4:-}"
    $LIST_MODE && return; is_overridden "$id" && { skipped "$desc"; return; }
    if eval "$test_cmd" >/dev/null 2>&1; then pass "$desc"
    elif $FIX_MODE && [ -n "$fix_cmd" ]; then eval "$fix_cmd" >/dev/null 2>&1 && fixed "$desc" || fail "$desc"
    else fail "$desc"; fi
  }
}

teardown() { rm -rf "$TEST_DIR"; }

@test "resilience: module file exists" {
  [ -f "$TEST_DOTFILES/modules/resilience/doctor.sh" ]
}

@test "missing App Store app is an advisory with a person-owned step and no UI launch" {
  export AMPHETAMINE_APP_PATH="$TEST_DIR/missing.app" KEEP_AWAKE_TOOLS=true
  FIX_MODE=true
  check() { [ "$1" != resilience.amphetamine_installed ] || printf 'fail\n' >> "$TEST_DIR/result"; }
  check_advisory() {
    [ "$1" = resilience.amphetamine_installed ] || return 0
    if eval "$3"; then printf 'pass\n' >> "$TEST_DIR/result"
    else printf 'warn %s\n' "$4" >> "$TEST_DIR/result"; fi
  }
  open() { touch "$TEST_DIR/opened"; }
  source "$TEST_DOTFILES/modules/resilience/doctor.sh"
  grep -q '^warn .*You:.*App Store' "$TEST_DIR/result"
  [ ! -e "$TEST_DIR/opened" ]
}

@test "installed App Store app keeps a passing advisory" {
  export AMPHETAMINE_APP_PATH="$TEST_DIR/installed.app" KEEP_AWAKE_TOOLS=true
  mkdir -p "$AMPHETAMINE_APP_PATH"
  check() { [ "$1" != resilience.amphetamine_installed ] || printf 'wrong-kind\n' >> "$TEST_DIR/result"; }
  check_advisory() {
    [ "$1" = resilience.amphetamine_installed ] || return 0
    if eval "$3"; then printf 'pass\n' >> "$TEST_DIR/result"
    else printf 'warn\n' >> "$TEST_DIR/result"; fi
  }
  source "$TEST_DOTFILES/modules/resilience/doctor.sh"
  grep -qx pass "$TEST_DIR/result"
}

@test "doctor --fix reports the App Store advisory without opening UI" {
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor" "$TEST_DOTFILES/bin/"
  cp -R "$BATS_TEST_DIRNAME/../lib/." "$TEST_DOTFILES/lib/"
  # Run the production check through the real doctor without running other fixes.
  awk '/resilience\.amphetamine_installed/ { print previous; print; remaining=3; next }
       remaining > 0 { print; remaining--; next }
       { previous=$0 }' "$BATS_TEST_DIRNAME/../modules/resilience/doctor.sh" > "$TEST_DOTFILES/modules/resilience/doctor.sh"
  [ "$(grep -c 'resilience.amphetamine_installed' "$TEST_DOTFILES/modules/resilience/doctor.sh")" -eq 1 ]
  printf 'check "test.fix_mode" "fix mode control" "[ -e %s/fix-ran ]" "touch %s/fix-ran"\n' "$TEST_DIR" "$TEST_DIR" >> "$TEST_DOTFILES/modules/resilience/doctor.sh"
  printf '#!/bin/sh\n[ "$1" = source-path ] && printf "%%s\\n" "%s"\nexit 0\n' "$TEST_DOTFILES" > "$TEST_DOTFILES/bin/chezmoi"
  chmod +x "$TEST_DOTFILES/bin/chezmoi"
  for command in open dotfiles-resilience-setup; do
    printf '#!/bin/sh\ntouch "%s/launched"\n' "$TEST_DIR" > "$TEST_DOTFILES/bin/$command"
    chmod +x "$TEST_DOTFILES/bin/$command"
  done
  export DOTFILES_KEEP_AWAKE_TOOLS=true AMPHETAMINE_APP_PATH="$TEST_DIR/missing.app"
  export DOTFILES_LOCAL_OVERRIDES="$TEST_DIR/overrides" DOTFILES_DOCTOR_NOTIFY=0
  export XDG_CONFIG_HOME="$TEST_HOME/.config" XDG_CACHE_HOME="$TEST_HOME/.cache" XDG_STATE_HOME="$TEST_HOME/.local/state"
  export PATH="$TEST_DOTFILES/bin:$PATH"
  run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --fix --json --module resilience
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e '[.[] | select(.id == "resilience.amphetamine_installed")] | length == 1 and .[0].status == "warn" and (.[0].fix | contains("You:") and contains("App Store"))' >/dev/null
  [ -e "$TEST_DIR/fix-ran" ]
  [ ! -e "$TEST_DIR/launched" ]
}

@test "resilience: fails when tmux is not installed" {
  mkdir -p "$TEST_DIR/empty_bin"
  export PATH="$TEST_DIR/empty_bin:/usr/bin:/bin:/usr/sbin:/sbin"
  touch "$TEST_DOTFILES/bin/agent-tmux"
  source "$TEST_DOTFILES/modules/resilience/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "resilience: passes tmux check when tmux exists" {
  mkdir -p "$TEST_DIR/mock_bin"
  cat > "$TEST_DIR/mock_bin/tmux" << 'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "$TEST_DIR/mock_bin/tmux"
  export PATH="$TEST_DIR/mock_bin:$PATH"
  touch "$TEST_DOTFILES/bin/agent-tmux"
  chmod +x "$TEST_DOTFILES/bin/agent-tmux"
  source "$TEST_DOTFILES/modules/resilience/doctor.sh"
  [ "$pass_count" -ge 2 ]
}

@test "resilience: doctor declares the headless Chrome lock check" {
  grep -q 'resilience.headless_chrome_under_heavy_run' "$BATS_TEST_DIRNAME/../modules/resilience/doctor.sh"
  [ -x "$BATS_TEST_DIRNAME/../bin/headless-chrome-unlocked" ]
}
