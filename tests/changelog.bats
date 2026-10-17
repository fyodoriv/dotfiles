#!/usr/bin/env bats
# scripts/changelog.sh: CHANGELOG.md is generated from conventional commits.

REPO_ROOT="$BATS_TEST_DIRNAME/.."
GEN="$REPO_ROOT/scripts/changelog.sh"

setup() { TEST_DIR="$(mktemp -d)"; }
teardown() { rm -rf "$TEST_DIR"; }

@test "CHANGELOG.md is exactly what the generator prints for its recorded commit" {
  local sha
  sha="$(sed -nE 's/.*up to commit ([0-9a-f]{12})\. Do not edit by hand.*/\1/p' "$REPO_ROOT/CHANGELOG.md")"
  [ -n "$sha" ] || { echo "CHANGELOG.md does not name its source commit"; return 1; }
  git -C "$REPO_ROOT" cat-file -e "$sha^{commit}" 2>/dev/null || skip "commit $sha is not in this clone"
  run bash -c "cd '$REPO_ROOT' && '$GEN' '$sha'"
  [ "$status" -eq 0 ]
  diff <(printf '%s\n' "$output") "$REPO_ROOT/CHANGELOG.md" || { echo "CHANGELOG.md was edited by hand; run make changelog"; return 1; }
}

@test "the generator lists feat, fix, perf, and refactor newest first and skips the rest" {
  command -v git-cliff >/dev/null || skip "git-cliff is not installed"
  local repo="$TEST_DIR/repo" c
  git init -q "$repo"
  c() { GIT_CONFIG_GLOBAL=/dev/null git -C "$repo" -c user.name=t -c user.email=t@example.com commit -q --allow-empty --no-verify -m "$1"; }
  c "chore: initial"
  c "feat(x): old feature"
  c "fix: a bug (#2)"
  c "chore: not listed"
  c "Merge branch without a type"
  c "feat!: breaking feature"
  cp "$REPO_ROOT/cliff.toml" "$repo/"
  run bash -c "cd '$repo' && '$GEN' HEAD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"### Features"*"- breaking feature"*"- old feature"*"### Fixes"*"- a bug (#2)"* ]]
  [[ "$output" != *"not listed"* ]]
  [[ "$output" != *"without a type"* ]]
}
