#!/usr/bin/env bats
# Tests for the topgrade [post_commands] uv-python re-signing helper
# (bin/dotfiles-adhoc-sign-uv-pythons).
#
# Closes the endpoint agent gap: `dotfiles upgrade`'s `uv` step runs
# `uv python upgrade`, which re-extracts python-build-standalone binaries
# UNSIGNED on a patch bump. Nothing else in the upgrade flow re-signs them
# (run_after_uv-python-setup.sh only fires on `dotfiles apply`), so endpoint agent
# would fire the policy dialog on every python3.1x spawn until the next apply.
# The post_command runs this helper to re-sign them every upgrade.

SIGNER="$BATS_TEST_DIRNAME/../bin/dotfiles-adhoc-sign-uv-pythons"
TOPGRADE_CFG="$BATS_TEST_DIRNAME/../dot_config/topgrade.toml"

setup() {
  FIXTURE="$(mktemp -d)"
}

teardown() {
  rm -rf "$FIXTURE"
}

# Drop an UNSIGNED Mach-O named like a uv python into the fixture root.
# /bin/echo is a real Mach-O; removing its signature yields "not signed".
_make_unsigned_python() {
  local dest="$FIXTURE/$1"
  mkdir -p "$(dirname "$dest")"
  cp /bin/echo "$dest"
  codesign --remove-signature "$dest" 2>/dev/null || true
  chmod +x "$dest"
}

@test "signer exists and is executable" {
  [ -x "$SIGNER" ]
}

@test "topgrade [post_commands] wires the uv-python re-sign helper" {
  grep -q 'dotfiles-adhoc-sign-uv-pythons' "$TOPGRADE_CFG"
}

@test "topgrade [post_commands] still wires the bottle re-sign helper" {
  # Regression guard: adding the uv-python entry must not drop the bottle one.
  grep -q 'dotfiles-adhoc-sign-bottles' "$TOPGRADE_CFG"
}

@test "topgrade [post_commands] refreshes endpoint shims after upgrade" {
  grep -q 'run_after_endpoint-security.sh' "$TOPGRADE_CFG"
}

@test "signs an unsigned uv python (-> Signature=adhoc)" {
  _make_unsigned_python "cpython-3.13.13-macos-aarch64-none/bin/python3.13"
  local py="$FIXTURE/cpython-3.13.13-macos-aarch64-none/bin/python3.13"
  codesign -dvv "$py" 2>&1 | grep -q "not signed"          # precondition
  DOTFILES_ADHOC_SIGN_QUIET=1 "$SIGNER" "$FIXTURE"
  codesign -dvv "$py" 2>&1 | grep -q "Signature=adhoc"     # postcondition
}

@test "idempotent — an already-signed python is skipped, not re-signed" {
  _make_unsigned_python "cpython-3.13.13-macos-aarch64-none/bin/python3.13"
  "$SIGNER" "$FIXTURE" >/dev/null
  run "$SIGNER" "$FIXTURE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already-signed"* ]]
  [[ "$output" == *"signed 0"* ]] || [[ "$output" == *"Ad-hoc signed 0"* ]]
}

@test "missing uv python root is a clean no-op (exit 0)" {
  run "$SIGNER" "$FIXTURE/does-not-exist"
  [ "$status" -eq 0 ]
}

@test "matches python3.12 and python3.13 (the python3.1? glob)" {
  _make_unsigned_python "a/bin/python3.13"
  _make_unsigned_python "b/bin/python3.12"
  DOTFILES_ADHOC_SIGN_QUIET=1 "$SIGNER" "$FIXTURE"
  codesign -dvv "$FIXTURE/a/bin/python3.13" 2>&1 | grep -q "Signature=adhoc"
  codesign -dvv "$FIXTURE/b/bin/python3.12" 2>&1 | grep -q "Signature=adhoc"
}
