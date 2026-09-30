#!/usr/bin/env bats
# Tests for bootstrap sed escaping — special characters in git name/email.

load test_helper

SCRIPT="$BATS_TEST_DIRNAME/../.chezmoiscripts/run_once_bootstrap.sh"
EXAMPLE="$BATS_TEST_DIRNAME/../gitconfig.local.example"

# Extract the _sed_escape function for unit testing
_sed_escape() { printf '%s' "$1" | sed 's/[\\&|]/\\&/g'; }

# Helper: simulate the bootstrap sed replacement on a temp gitconfig
_run_bootstrap_sed() {
  local git_name="$1" git_email="$2"
  local config_file="$TEST_DIR/gitconfig.local"
  cp "$EXAMPLE" "$config_file"
  sed -i.bak "s|Your Name|$(_sed_escape "$git_name")|" "$config_file" && rm -f "$config_file.bak"
  sed -i.bak "s|your@email.com|$(_sed_escape "$git_email")|" "$config_file" && rm -f "$config_file.bak"
  cat "$config_file"
}

# ── Normal names work ──────────────────────────────────────────────

@test "bootstrap sed: normal name and email" {
  run _run_bootstrap_sed "John Doe" "john@example.com"
  [ "$status" -eq 0 ]
  [[ "$output" == *"name = John Doe"* ]]
  [[ "$output" == *"email = john@example.com"* ]]
}

# ── Special characters in name ─────────────────────────────────────

@test "bootstrap sed: name with apostrophe (O'Brien)" {
  run _run_bootstrap_sed "John O'Brien" "john@example.com"
  [ "$status" -eq 0 ]
  [[ "$output" == *"name = John O'Brien"* ]]
}

@test "bootstrap sed: name with slash (corp/dept)" {
  run _run_bootstrap_sed "John/Smith" "john@example.com"
  [ "$status" -eq 0 ]
  [[ "$output" == *"name = John/Smith"* ]]
}

@test "bootstrap sed: name with backslash" {
  run _run_bootstrap_sed 'John\Smith' "john@example.com"
  [ "$status" -eq 0 ]
  [[ "$output" == *'name = John\Smith'* ]]
}

@test "bootstrap sed: name with ampersand" {
  run _run_bootstrap_sed "Smith & Sons" "john@example.com"
  [ "$status" -eq 0 ]
  [[ "$output" == *"name = Smith & Sons"* ]]
}

# ── Special characters in email ────────────────────────────────────

@test "bootstrap sed: email with plus addressing" {
  run _run_bootstrap_sed "John Doe" "john+dev@example.com"
  [ "$status" -eq 0 ]
  [[ "$output" == *"email = john+dev@example.com"* ]]
}

@test "bootstrap sed: email with ampersand (a&b@c.com)" {
  run _run_bootstrap_sed "John Doe" "a&b@c.com"
  [ "$status" -eq 0 ]
  [[ "$output" == *"email = a&b@c.com"* ]]
}

@test "bootstrap sed: email with slash (user@corp/dept)" {
  run _run_bootstrap_sed "John Doe" "user@corp/dept"
  [ "$status" -eq 0 ]
  [[ "$output" == *"email = user@corp/dept"* ]]
}

# ── Combined edge case from acceptance criteria ────────────────────

@test "bootstrap sed: O'Brien name + a&b@c.com email" {
  run _run_bootstrap_sed "John/O'Brien" "a&b@c.com"
  [ "$status" -eq 0 ]
  [[ "$output" == *"name = John/O'Brien"* ]]
  [[ "$output" == *"email = a&b@c.com"* ]]
}

# ── _sed_escape unit tests ─────────────────────────────────────────

@test "_sed_escape: passes through normal text" {
  result="$(_sed_escape "hello world")"
  [ "$result" = "hello world" ]
}

@test "_sed_escape: escapes ampersand" {
  result="$(_sed_escape "a&b")"
  [ "$result" = 'a\&b' ]
}

@test "_sed_escape: escapes pipe delimiter" {
  result="$(_sed_escape "a|b")"
  [ "$result" = 'a\|b' ]
}

@test "_sed_escape: escapes backslash" {
  result="$(_sed_escape 'a\b')"
  [ "$result" = 'a\\b' ]
}
