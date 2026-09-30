#!/usr/bin/env bats
# Tests for lib/output.sh shared output helpers

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export DOTFILES_DIR="$BATS_TEST_DIRNAME/.."
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── Normal mode (default) ──

@test "pass prints green checkmark in normal mode" {
  run bash -c 'DOTFILES_DIR="'"$DOTFILES_DIR"'" source "$DOTFILES_DIR/lib/output.sh"; pass "test passed"'
  [[ "$output" == *"✓"* ]]
  [[ "$output" == *"test passed"* ]]
}

@test "fail prints red cross in normal mode" {
  run bash -c 'DOTFILES_DIR="'"$DOTFILES_DIR"'" source "$DOTFILES_DIR/lib/output.sh"; fail "test failed"'
  [[ "$output" == *"✗"* ]]
  [[ "$output" == *"test failed"* ]]
}

@test "fixed prints lightning bolt in normal mode" {
  run bash -c 'DOTFILES_DIR="'"$DOTFILES_DIR"'" source "$DOTFILES_DIR/lib/output.sh"; fixed "auto-repaired"'
  [[ "$output" == *"⚡"* ]]
  [[ "$output" == *"auto-repaired"* ]]
  [[ "$output" == *"auto-fixed"* ]]
}

@test "skipped prints skip marker in normal mode" {
  run bash -c 'DOTFILES_DIR="'"$DOTFILES_DIR"'" source "$DOTFILES_DIR/lib/output.sh"; skipped "not applicable"'
  [[ "$output" == *"⊘"* ]]
  [[ "$output" == *"not applicable"* ]]
}

@test "audit_warn prints warning in normal mode" {
  run bash -c 'DOTFILES_DIR="'"$DOTFILES_DIR"'" source "$DOTFILES_DIR/lib/output.sh"; audit_warn "something iffy"'
  [[ "$output" == *"⚠"* ]]
  [[ "$output" == *"something iffy"* ]]
}

@test "audit_warn prints remediation in normal mode" {
  run bash -c 'DOTFILES_DIR="'"$DOTFILES_DIR"'" source "$DOTFILES_DIR/lib/output.sh"; audit_warn "something iffy" "chmod 600 ~/.netrc"'
  [[ "$output" == *"⚠"* ]]
  [[ "$output" == *"something iffy"* ]]
  [[ "$output" == *"fix: chmod 600 ~/.netrc"* ]]
}

# ── Report mode ──

@test "pass prints markdown in report mode" {
  run bash -c 'REPORT_MODE=true DOTFILES_DIR="'"$DOTFILES_DIR"'" source "$DOTFILES_DIR/lib/output.sh"; pass "looks good"'
  [[ "$output" == "- ✅ looks good" ]]
}

@test "fail prints markdown in report mode" {
  run bash -c 'REPORT_MODE=true DOTFILES_DIR="'"$DOTFILES_DIR"'" source "$DOTFILES_DIR/lib/output.sh"; fail "broken"'
  [[ "$output" == "- ❌ broken" ]]
}

@test "fixed prints markdown in report mode" {
  run bash -c 'REPORT_MODE=true DOTFILES_DIR="'"$DOTFILES_DIR"'" source "$DOTFILES_DIR/lib/output.sh"; fixed "repaired"'
  [[ "$output" == "- ⚡ repaired (auto-fixed)" ]]
}

@test "audit_warn prints remediation in report mode" {
  run bash -c 'REPORT_MODE=true DOTFILES_DIR="'"$DOTFILES_DIR"'" source "$DOTFILES_DIR/lib/output.sh"; audit_warn "iffy" "chmod 600 ~/.netrc"'
  [[ "$output" == "- ⚠️ iffy — Fix: chmod 600 ~/.netrc" ]]
}

# ── Quiet mode ──

@test "pass produces no output in quiet mode" {
  run bash -c 'QUIET_MODE=true DOTFILES_DIR="'"$DOTFILES_DIR"'" source "$DOTFILES_DIR/lib/output.sh"; pass "silent"'
  [[ -z "$output" ]]
}

@test "fail produces no output in quiet mode" {
  run bash -c 'QUIET_MODE=true DOTFILES_DIR="'"$DOTFILES_DIR"'" source "$DOTFILES_DIR/lib/output.sh"; fail "silent"'
  [[ -z "$output" ]]
}

# ── Counters ──

@test "counters increment correctly" {
  run bash -c '
    QUIET_MODE=true DOTFILES_DIR="'"$DOTFILES_DIR"'" source "$DOTFILES_DIR/lib/output.sh"
    pass "a"; pass "b"; fail "c"; fixed "d"; skipped "e"; audit_warn "f"
    echo "pass=$pass_count fail=$fail_count fix=$fix_count skip=$skip_count warn=$warn_count"
  '
  [[ "$output" == "pass=2 fail=1 fix=1 skip=1 warn=1" ]]
}

@test "counters start at zero" {
  run bash -c '
    QUIET_MODE=true DOTFILES_DIR="'"$DOTFILES_DIR"'" source "$DOTFILES_DIR/lib/output.sh"
    echo "pass=$pass_count fail=$fail_count fix=$fix_count skip=$skip_count warn=$warn_count"
  '
  [[ "$output" == "pass=0 fail=0 fix=0 skip=0 warn=0" ]]
}

@test "report_failures array tracks fail messages" {
  run bash -c '
    REPORT_MODE=true DOTFILES_DIR="'"$DOTFILES_DIR"'" source "$DOTFILES_DIR/lib/output.sh"
    fail "first problem"
    fail "second problem"
    echo "count=${#report_failures[@]}"
  ' 2>&1
  [[ "$output" == *"count=2"* ]]
}
