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
