#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../bin/learn-repos-source-fingerprint"

setup() {
  TEST_DIR="$(mktemp -d)"
  REPO="$TEST_DIR/repo"
  mkdir -p "$REPO/docs" "$REPO/src" "$REPO/node_modules/pkg"
  git -C "$TEST_DIR" init -q repo
  printf '# Repo\n' > "$REPO/README.md"
  printf '# Runbook\n' > "$REPO/docs/runbook.md"
  printf '# Not source\n' > "$REPO/src/internal.md"
  printf '# Dependency\n' > "$REPO/node_modules/pkg/README.md"
  printf 'node_modules/\n' > "$REPO/.gitignore"
  git -C "$REPO" add README.md docs/runbook.md src/internal.md .gitignore
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "fingerprint uses the canonical sorted source-document set" {
  run "$SCRIPT" "$REPO"

  [ "$status" -eq 0 ]
  [[ "$output" == source_fingerprint$'\t'* ]]
  [[ "$output" == *$'source_path\tREADME.md'* ]]
  [[ "$output" == *$'source_path\tdocs/runbook.md'* ]]
  [[ "$output" != *"src/internal.md"* ]]
  [[ "$output" != *"node_modules"* ]]
  [ "$(printf '%s\n' "$output" | grep '^source_path' | cut -f2-)" = $'README.md\ndocs/runbook.md' ]
}

@test "fingerprint detects uncommitted document edits at the same revision" {
  before="$("$SCRIPT" "$REPO" | awk -F '\t' '$1 == "source_fingerprint" { print $2 }')"
  printf 'changed\n' >> "$REPO/docs/runbook.md"
  after="$("$SCRIPT" "$REPO" | awk -F '\t' '$1 == "source_fingerprint" { print $2 }')"

  [ "$before" != "$after" ]
}

@test "fingerprint includes untracked human-authored root documents" {
  printf '# Notes\n' > "$REPO/NOTES.md"

  run "$SCRIPT" "$REPO"

  [ "$status" -eq 0 ]
  [[ "$output" == *$'source_path\tNOTES.md'* ]]
}
