#!/usr/bin/env bats
# Focused tests for lib/secret-scan.sh.

LIB="$BATS_TEST_DIRNAME/../lib/secret-scan.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  REPO="$TEST_DIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
}

teardown() {
  rm -rf "$TEST_DIR"
}

track_text() {
  local rel="$1" content="$2"
  mkdir -p "$(dirname "$REPO/$rel")"
  printf '%s\n' "$content" > "$REPO/$rel"
  git -C "$REPO" add -f "$rel"
}

track_binary() {
  local rel="$1" name="$2"
  mkdir -p "$(dirname "$REPO/$rel")"
  printf '\000%s="%s"\000\n' "$name" "fixturevalue123456" > "$REPO/$rel"
  git -C "$REPO" add -f "$rel"
}

secret_line() {
  local name="$1"
  printf '%s="%s"' "$name" "fixturevalue123456"
}

scan_repo() {
  run bash -c '. "$1"; dotfiles_scan_tracked_secrets "$2"' _ "$LIB" "$REPO"
}

@test "secret scan detects every supported secret pattern in tracked text files" {
  local name rel
  for name in API_KEY SECRET_KEY PRIVATE_KEY ACCESS_TOKEN AUTH_TOKEN PASSWORD CLIENT_SECRET; do
    rel="leaks/$name.env"
    track_text "$rel" "$(secret_line "$name")"
  done

  scan_repo

  [ "$status" -eq 0 ]
  for name in API_KEY SECRET_KEY PRIVATE_KEY ACCESS_TOKEN AUTH_TOKEN PASSWORD CLIENT_SECRET; do
    [[ "$output" == *"leaks/$name.env"* ]]
  done
}

@test "secret scan allows lines with structured allowlist comments" {
  track_text "allowlisted.env" "$(secret_line API_KEY) # dotfiles-secret-allowlist: fake credential fixture"

  scan_repo

  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "secret scan requires an allowlist reason after the marker" {
  track_text "missing-reason.env" "$(secret_line SECRET_KEY) # dotfiles-secret-allowlist:"

  scan_repo

  [ "$status" -eq 0 ]
  [ "$output" = "missing-reason.env" ]
}

@test "secret scan reports a file when only one matching line is not allowlisted" {
  local allowed blocked
  allowed="$(secret_line API_KEY) # dotfiles-secret-allowlist: fixture"
  blocked="$(secret_line CLIENT_SECRET)"
  track_text "mixed.env" "$allowed
$blocked"

  scan_repo

  [ "$status" -eq 0 ]
  [ "$output" = "mixed.env" ]
}

@test "secret scan ignores intentional fixture paths" {
  track_text "tests/audit_fixture.bats" "$(secret_line ACCESS_TOKEN)"

  scan_repo

  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "secret scan only scans git-tracked files" {
  printf '%s\n' "$(secret_line AUTH_TOKEN)" > "$REPO/untracked.env"
  track_text "clean.txt" "no secrets here"

  scan_repo

  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "secret scan skips binary files safely" {
  track_binary "binary.dat" API_KEY

  scan_repo

  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "secret scan ignores representative non-secret lookalikes" {
  track_text "lookalikes.env" 'API_KEY_NAME="production"
PASSWORD_LENGTH=32
ACCESS_TOKEN_FILE="$HOME/.token"
CLIENT_SECRET_ROTATION_DAYS=90
PRIVATE_KEY_PATH="$HOME/.ssh/id_ed25519"'

  scan_repo

  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

# ── Agent-config backup bearer scan ──

fake_bearer() {
  printf 'Bearer %s' "$(printf 'x%.0s' $(seq 1 32))"
}

@test "agent-config scan flags a plaintext bearer in a ~/.claude.json backup" {
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME/.config/agentbrew/backups/manual"
  printf '{"args":["--header","Authorization: %s"]}\n' "$(fake_bearer)" > "$HOME/.claude.json.backup"
  printf '{"args":["Authorization: Bearer ${SPLUNK_TOKEN}"]}\n' > "$HOME/.config/agentbrew/backups/manual/claude.json.1.bak"
  printf '{"args":["--header","Authorization: %s"]}\n' "$(fake_bearer)" > "$HOME/.claude.json"
  source "$LIB"

  run dotfiles_agent_config_bearer_leaks
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.claude.json.backup" ]
}

@test "agent-config repair redacts bearer tokens and keeps JSON valid" {
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME/.config/agentbrew/backups/manual"
  printf '{"args":["--header","Authorization: %s"]}\n' "$(fake_bearer)" > "$HOME/.config/agentbrew/backups/manual/claude.json.2.bak"
  source "$LIB"

  dotfiles_redact_agent_config_bearer_leaks
  run dotfiles_agent_config_bearer_leaks
  [ -z "$output" ]
  grep -q 'Authorization: Bearer REDACTED' "$HOME/.config/agentbrew/backups/manual/claude.json.2.bak"
  plutil -convert xml1 -o /dev/null "$HOME/.config/agentbrew/backups/manual/claude.json.2.bak"
}

@test "agent-config scan ignores already-redacted bearer markers" {
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME"
  printf '{"args":["Authorization: Bearer REDACTED-ROTATE-IN-SPLUNK"]}\n' > "$HOME/.claude.json.backup"
  source "$LIB"

  run dotfiles_agent_config_bearer_leaks
  [ -z "$output" ]
}

@test "secret scan spawns grep a bounded number of times, not once per file" {
  # The doctor scans every tracked file. One grep per file cost about 50s
  # on a busy Mac (668 files, two spawns each).
  local i real_grep
  for i in $(seq 1 20); do track_text "src/file$i.sh" "echo $i"; done
  track_text "leaks/one.env" "$(secret_line API_KEY)"
  real_grep="$(command -v grep)"
  mkdir -p "$TEST_DIR/bin"
  cat > "$TEST_DIR/bin/grep" <<STUB
#!/bin/bash
echo x >> "$TEST_DIR/grep-calls"
exec "$real_grep" "\$@"
STUB
  chmod +x "$TEST_DIR/bin/grep"
  run env -u BASH_ENV -u ENV PATH="$TEST_DIR/bin:$PATH" bash -c '. "$1"; dotfiles_scan_tracked_secrets "$2"' _ "$LIB" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "leaks/one.env" ]
  [ "$(wc -l < "$TEST_DIR/grep-calls")" -le 3 ]
}
