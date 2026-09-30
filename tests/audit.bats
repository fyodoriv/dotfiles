#!/usr/bin/env bats
# Tests for dotfiles-audit security checks

load test_helper

AUDIT_CMD="$BATS_TEST_DIRNAME/../bin/dotfiles-audit"
GITIGNORE="$BATS_TEST_DIRNAME/../.gitignore"

# Build the fake dotfiles repo (with .git already initialized) ONCE per
# file. Each test then copies it via cp -r — saves ~3s per test on the
# `git init && git commit` operations.
setup_file() {
  export FILE_TMPDIR="$BATS_FILE_TMPDIR"
  local tmpl="$FILE_TMPDIR/dotfiles-template"
  mkdir -p "$tmpl/lib" "$tmpl/bin" "$tmpl/modules/security"
  cp "$BATS_TEST_DIRNAME/../lib/colors.sh" "$tmpl/lib/colors.sh"
  cp "$BATS_TEST_DIRNAME/../lib/stats.sh" "$tmpl/lib/stats.sh"
  cp "$BATS_TEST_DIRNAME/../lib/output.sh" "$tmpl/lib/output.sh"
  cp "$BATS_TEST_DIRNAME/../lib/secret-scan.sh" "$tmpl/lib/secret-scan.sh"
  cp "$BATS_TEST_DIRNAME/../modules/security/doctor.sh" "$tmpl/modules/security/doctor.sh"
  cp "$AUDIT_CMD" "$tmpl/bin/dotfiles-audit"
  chmod +x "$tmpl/bin/dotfiles-audit"
  # Pin HOME so git doesn't pick up the user's global config (incl.
  # core.hooksPath -> dotfiles git-hooks, which would reject "init"
  # as a non-conventional commit message and fail this setup).
  (cd "$tmpl" \
    && HOME="$FILE_TMPDIR/_home_for_init" git init -q \
    && HOME="$FILE_TMPDIR/_home_for_init" git config user.email "test@test" \
    && HOME="$FILE_TMPDIR/_home_for_init" git config user.name "test" \
    && HOME="$FILE_TMPDIR/_home_for_init" git add -A \
    && HOME="$FILE_TMPDIR/_home_for_init" git commit -q -m "init")
}

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  mkdir -p "$TEST_HOME"
  export HOME="$TEST_HOME"

  # Fast copy of the prebuilt template (saves ~3s/test vs git init+commit)
  FAKE_DOTFILES="$TEST_DIR/dotfiles"
  cp -r "$FILE_TMPDIR/dotfiles-template" "$FAKE_DOTFILES"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "dotfiles-audit runs without errors" {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  run bash "$FAKE_DOTFILES/bin/dotfiles-audit"
  # May exit 0 or 1 depending on git config — just verify it ran
  [[ "$status" -eq 0 || "$status" -eq 1 ]]
  [[ "$output" == *"passed"* ]]
}

@test "dotfiles-audit detects correct .ssh directory permissions" {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  run bash "$FAKE_DOTFILES/bin/dotfiles-audit"
  [[ "$output" == *".ssh directory permissions"* ]]
}

@test "dotfiles-audit detects wrong .ssh directory permissions" {
  mkdir -p "$HOME/.ssh"
  chmod 755 "$HOME/.ssh"
  run bash "$FAKE_DOTFILES/bin/dotfiles-audit"
  [[ "$output" == *".ssh directory permissions"* ]]
  [[ "$output" == *"failed"* ]]
}

@test "dotfiles-audit checks private key permissions" {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  echo "-----BEGIN OPENSSH PRIVATE KEY-----" > "$HOME/.ssh/id_test"
  chmod 600 "$HOME/.ssh/id_test"
  run bash "$FAKE_DOTFILES/bin/dotfiles-audit"
  [[ "$output" == *"id_test permissions"* ]]
}

@test "dotfiles-audit flags world-readable private key" {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  echo "-----BEGIN OPENSSH PRIVATE KEY-----" > "$HOME/.ssh/id_test"
  chmod 644 "$HOME/.ssh/id_test"
  run bash "$FAKE_DOTFILES/bin/dotfiles-audit"
  [[ "$output" == *"id_test permissions"* ]]
  [[ "$output" == *"failed"* ]]
}

@test "dotfiles-audit skips public keys" {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  echo "ssh-rsa AAAA..." > "$HOME/.ssh/id_test.pub"
  chmod 644 "$HOME/.ssh/id_test.pub"
  run bash "$FAKE_DOTFILES/bin/dotfiles-audit"
  # Public key should not appear in output as a failure
  [[ "$output" != *"id_test.pub permissions"* ]]
}

@test "dotfiles-audit warns when .ssh directory is missing" {
  # No .ssh directory created
  run bash "$FAKE_DOTFILES/bin/dotfiles-audit"
  [[ "$output" == *".ssh directory exists"* ]]
}

@test "dotfiles-audit --report outputs markdown format" {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  run bash "$FAKE_DOTFILES/bin/dotfiles-audit" --report
  # Report mode uses markdown bullets (- ✅) instead of ANSI colors
  [[ "$output" == *"- ✅"* ]] || [[ "$output" == *"- ❌"* ]] || [[ "$output" == *"- ⚠️"* ]]
  [[ "$output" == *"**Total**"* ]]
}

@test "dotfiles-audit --report includes advisory remediation" {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  echo "machine github.com" > "$HOME/.netrc"
  chmod 644 "$HOME/.netrc"

  run bash "$FAKE_DOTFILES/bin/dotfiles-audit" --report

  [[ "$output" == *"- ⚠️ .netrc not world-readable — Fix: chmod 600 ~/.netrc"* ]]
}

@test "dotfiles-audit reports no secrets in clean repo" {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  run bash "$FAKE_DOTFILES/bin/dotfiles-audit"
  [[ "$output" == *"No secrets detected in tracked files"* ]]
}

@test "dotfiles-audit ignores intentional test secret fixtures" {
  mkdir -p "$HOME/.ssh" "$FAKE_DOTFILES/tests"
  chmod 700 "$HOME/.ssh"
  echo 'API_KEY="sk_live_intentionaltestfixture"' > "$FAKE_DOTFILES/tests/audit_fixture.bats" # dotfiles-secret-allowlist: writes an explicit fixture-path secret
  (cd "$FAKE_DOTFILES" && git add tests/audit_fixture.bats && git commit -q -m "add test fixture" --author="test <test@test>")
  run bash "$FAKE_DOTFILES/bin/dotfiles-audit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No secrets detected in tracked files"* ]]
  [[ "$output" != *"tests/audit_fixture.bats"* ]]
}

@test "dotfiles-audit detects secrets in tracked files" {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  # Add a file with a secret pattern to the fake dotfiles repo
  echo 'API_KEY="sk_live_abcdefghijklmn"' > "$FAKE_DOTFILES/leaked.sh" # dotfiles-secret-allowlist: writes a fixture that the scanner must catch
  (cd "$FAKE_DOTFILES" && git add leaked.sh && git commit -q -m "add leaked" --author="test <test@test>")
  run bash "$FAKE_DOTFILES/bin/dotfiles-audit"
  [[ "$output" == *"No secrets in"* ]]
  [[ "$output" == *"failed"* ]]
}

@test "dotfiles-audit reports no .env files in clean repo" {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  run bash "$FAKE_DOTFILES/bin/dotfiles-audit"
  [[ "$output" == *"No .env files tracked in git"* ]]
}

@test ".gitignore hides root pip redirect artifacts" {
  grep -Fxq '=[0-9]*' "$GITIGNORE"
}

@test "dotfiles-audit flags root pip redirect artifacts" {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  touch "$FAKE_DOTFILES/=5.5.0"

  run bash "$FAKE_DOTFILES/bin/dotfiles-audit"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Stray root-level pip redirect artifact: =5.5.0"* ]]
  [[ "$output" == *"remove with: rm =5.5.0"* ]]
}

@test "dotfiles-audit flags root absolute symlink artifacts" {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  ln -s /usr/local/bin/fd "$FAKE_DOTFILES/fd"

  run bash "$FAKE_DOTFILES/bin/dotfiles-audit"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Stray root-level absolute symlink: fd -> /usr/local/bin/fd"* ]]
  [[ "$output" == *"remove with: rm fd"* ]]
}

@test "dotfiles-audit passes root artifact check in clean repo" {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  run bash "$FAKE_DOTFILES/bin/dotfiles-audit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No stray root-level agent artifacts"* ]]
}

@test "dotfiles-audit warns about world-readable sensitive files" {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  echo "machine github.com" > "$HOME/.netrc"
  chmod 644 "$HOME/.netrc"
  run bash "$FAKE_DOTFILES/bin/dotfiles-audit"
  [[ "$output" == *"netrc"*"world-readable"* ]]
  [[ "$output" == *"fix: chmod 600 ~/.netrc"* ]]
}

@test "dotfiles-audit warns with GPG signing remediation" {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  run bash "$FAKE_DOTFILES/bin/dotfiles-audit"

  [[ "$output" == *"Git commits GPG signed"* ]]
  [[ "$output" == *"git config --global commit.gpgsign true"* ]]
  [[ "$output" == *"skip only if your team does not require signed commits"* ]]
}

@test "dotfiles-audit passes for restricted sensitive files" {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  echo "machine github.com" > "$HOME/.netrc"
  chmod 600 "$HOME/.netrc"
  run bash "$FAKE_DOTFILES/bin/dotfiles-audit"
  [[ "$output" == *"netrc not world-readable"* ]]
}

@test "dotfiles-audit shows summary counts" {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  run bash "$FAKE_DOTFILES/bin/dotfiles-audit"
  [[ "$output" == *"passed"* ]]
  [[ "$output" == *"failed"* ]]
  [[ "$output" == *"warnings"* ]]
  [[ "$output" == *"total"* ]]
}

@test "dotfiles-audit exits 1 when failures found" {
  mkdir -p "$HOME/.ssh"
  chmod 755 "$HOME/.ssh"
  echo "-----BEGIN OPENSSH PRIVATE KEY-----" > "$HOME/.ssh/id_test"
  chmod 644 "$HOME/.ssh/id_test"
  run bash "$FAKE_DOTFILES/bin/dotfiles-audit"
  [ "$status" -eq 1 ]
}

@test "dotfiles-audit exits 0 when no failures" {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  run bash "$FAKE_DOTFILES/bin/dotfiles-audit"
  [ "$status" -eq 0 ]
}
