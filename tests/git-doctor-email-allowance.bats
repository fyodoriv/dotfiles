#!/usr/bin/env bats

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home" GH_CONFIG_DIR="$TEST_DIR/gh"
  export OSS_READINESS_ENV_FILE="$TEST_DIR/patterns.env"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 DOTFILES_DOCTOR_NOTIFY=0
  REPO="$TEST_DIR/repo"
  mkdir -p "$HOME" "$REPO/bin" "$REPO/modules" "$TEST_DIR/bin" "$TEST_DIR/no-hooks"
  cp -R "$BATS_TEST_DIRNAME/../lib" "$REPO/lib"
  cp -R "$BATS_TEST_DIRNAME/../modules/git" "$REPO/modules/git"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor" "$REPO/bin/dotfiles-doctor"
  cat > "$TEST_DIR/bin/chezmoi" <<'SH'
#!/bin/sh
case "$1" in source-path) printf '%s\n' "$REPO" ;; execute-template) printf 'false\n' ;; *) exit 1 ;; esac
SH
  chmod +x "$TEST_DIR/bin/chezmoi"
  export PATH="$TEST_DIR/bin:$PATH" REPO
  local version
  version="$(cat "$BATS_TEST_DIRNAME/../config/oss-readiness-min-version")"
  printf "OSS_READINESS_PRIVATE_EMAIL_PATTERN='@private\\.example$'\nOSS_READINESS_INTERNAL_PATTERN='zz-fixture-never-matches'\nOSS_READINESS_PATTERN_VERSION=%s\n" "$version" > "$OSS_READINESS_ENV_FILE"
  git init --quiet "$REPO"
  git -C "$REPO" config core.hooksPath "$TEST_DIR/no-hooks"
  git -C "$REPO" config commit.gpgsign false
  git -C "$REPO" config user.name "Fixture"
  git -C "$REPO" config user.email "fixture@private.example"
  printf 'fixture\n' > "$REPO/README.md"
  git -C "$REPO" add README.md
  git -C "$REPO" commit --quiet -m 'test: fixture'
}

teardown() { rm -rf "$TEST_DIR"; }

@test "a machine-local doctor opt-out does not weaken the public push guard" {
  run bash "$REPO/bin/dotfiles-doctor" --module git --json
  [ "$(printf '%s' "$output" | jq -r '.[] | select(.id == "git.user_email_is_public_safe") | .status')" = fail ]
  [[ "$output" != *"fixture@private.example"* ]]
  run bash "$REPO/bin/dotfiles-doctor" --skip git.user_email_is_public_safe
  [ "$status" -eq 0 ]
  [ -f "$HOME/.config/dotfiles/overrides" ]
  run bash "$REPO/bin/dotfiles-doctor" --module git --json
  [ "$(printf '%s' "$output" | jq -r '.[] | select(.id == "git.user_email_is_public_safe") | .status')" = skip ]
  [[ "$output" != *"fixture@private.example"* ]]
  local sha hook
  sha="$(git -C "$REPO" rev-parse HEAD)"
  hook="$BATS_TEST_DIRNAME/../git-hooks/pre-push"
  run bash -c 'cd "$1" && printf "refs/heads/main %s refs/heads/main %040d\n" "$3" 0 | "$2" origin https://github.com/fyodoriv/dotfiles.git' _ "$REPO" "$hook" "$sha"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Private author or committer emails cannot reach GitHub.com"* ]]
}
