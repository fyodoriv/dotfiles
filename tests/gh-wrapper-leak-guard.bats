#!/usr/bin/env bats
# Leak guard in bin/gh: text posted to a PUBLIC github.com repository must not
# carry private references (overlay pattern, $HOME paths, enterprise hosts,
# secrets). Enterprise hosts and private repositories are left alone.

load test_helper

GH_WRAPPER="$BATS_TEST_DIRNAME/../bin/gh"

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME"
  export USER="leakguarduser"

  # Fixture overlay pattern. Never the real one.
  export OSS_READINESS_ENV_FILE="$TEST_DIR/oss-readiness.env"
  cat > "$OSS_READINESS_ENV_FILE" <<'ENV'
OSS_READINESS_INTERNAL_PATTERN='acme-internal|widgetcorp'
OSS_READINESS_PRIVATE_EMAIL_PATTERN='@widgetcorp[.]example$'
ENV

  # gh is signed in to github.com and to one enterprise host.
  export GH_CONFIG_DIR="$TEST_DIR/gh-config"
  mkdir -p "$GH_CONFIG_DIR"
  cat > "$GH_CONFIG_DIR/hosts.yml" <<'YML'
github.com:
    user: octo
    git_protocol: ssh
github.acme.example:
    user: octo-corp
    git_protocol: https
YML

  GH_STUB="$TEST_DIR/real-gh"
  GH_POSTED="$TEST_DIR/gh-posted.txt"
  cat > "$GH_STUB" <<'STUB'
#!/bin/bash
# Visibility lookups answer from $STUB_VISIBILITY and are not recorded.
if [ "$1" = "api" ] && [[ "$*" == *"--jq .visibility"* ]]; then
  printf '%s\n' "${STUB_VISIBILITY:-public}"
  exit 0
fi
printf '%s\n' "$*" > "$GH_POSTED"
exit 0
STUB
  chmod +x "$GH_STUB"
  export DOTFILES_REAL_GH="$GH_STUB"
  export GH_POSTED
  unset GH_HOST GH_REPO DOTFILES_GH_ALLOW_PRIVATE_REFS MINSKY_PIPELINE \
    XDG_CONFIG_HOME EXTRA_OVERLAY_ROOT DOTFILES_REPOS_DIR
  # Human context: no footer or PR-create approval rules in the way.
  unset AGENT_PUBLIC_WRITE_GUARD DEVIN_MODEL DEVIN_SESSION_ID \
    CLAUDE_CODE_SSE_PORT CURSOR_AGENT WINDSURF_AGENT CODEX_AGENT
  cd "$TEST_DIR"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "blocks a PR body with an overlay-pattern term on a public repo" {
  run "$GH_WRAPPER" pr edit 8 --repo octo/tool --body "Set up the acme-internal overlay first."
  [ "$status" -ne 0 ]
  [[ "$output" == *"private reference"* ]]
  [ ! -f "$GH_POSTED" ]
}

@test "blocks a PR comment that pastes the local home path" {
  run "$GH_WRAPPER" pr comment 8 --repo octo/tool --body "Indexing $HOME/.config/tool/skills"
  [ "$status" -ne 0 ]
  [[ "$output" == *"home path"* ]]
  [ ! -f "$GH_POSTED" ]
}

@test "blocks a body naming an enterprise host gh is signed in to" {
  run "$GH_WRAPPER" issue comment 3 --repo octo/tool --body "team set git@github.acme.example:org/overlay.git"
  [ "$status" -ne 0 ]
  [[ "$output" == *"enterprise host"* ]]
  [ ! -f "$GH_POSTED" ]
}

@test "blocks a private term in a title" {
  run "$GH_WRAPPER" issue create --repo octo/tool --title "Port the widgetcorp hooks" --body "Plain body."
  [ "$status" -ne 0 ]
  [ ! -f "$GH_POSTED" ]
}

@test "blocks a private term in a --body-file" {
  printf 'Notes from the acme-internal rollout.\n' > "$TEST_DIR/body.md"
  run "$GH_WRAPPER" pr edit 8 --repo octo/tool --body-file "$TEST_DIR/body.md"
  [ "$status" -ne 0 ]
  [ ! -f "$GH_POSTED" ]
}

@test "blocks a private term in gh api -f body=" {
  run "$GH_WRAPPER" api -X POST repos/octo/tool/issues/3/comments -f "body=See acme-internal docs"
  [ "$status" -ne 0 ]
  [ ! -f "$GH_POSTED" ]
}

@test "blocks a private term in gh api --input JSON" {
  printf '{"body":"widgetcorp only"}\n' > "$TEST_DIR/in.json"
  run "$GH_WRAPPER" api -X POST repos/octo/tool/issues/3/comments --input "$TEST_DIR/in.json"
  [ "$status" -ne 0 ]
  [ ! -f "$GH_POSTED" ]
}

@test "blocks a private term in a squash-merge commit body" {
  run "$GH_WRAPPER" pr merge 8 --repo octo/tool --squash --body "Tested on the acme-internal laptop."
  [ "$status" -ne 0 ]
  [ ! -f "$GH_POSTED" ]
}

@test "blocks a token-shaped secret in a body" {
  local fake_token
  fake_token="ghp_$(printf 'x%.0s' {1..36})"
  run "$GH_WRAPPER" pr comment 8 --repo octo/tool --body "token $fake_token"
  [ "$status" -ne 0 ]
  [[ "$output" == *"secret"* ]]
  [ ! -f "$GH_POSTED" ]
}

@test "blocks a private term in a public gist file" {
  printf 'acme-internal runbook\n' > "$TEST_DIR/notes.md"
  run "$GH_WRAPPER" gist create --public "$TEST_DIR/notes.md"
  [ "$status" -ne 0 ]
  [ ! -f "$GH_POSTED" ]
}

@test "allows a secret gist with private terms" {
  printf 'acme-internal runbook\n' > "$TEST_DIR/notes.md"
  run "$GH_WRAPPER" gist create "$TEST_DIR/notes.md"
  [ "$status" -eq 0 ]
  [ -f "$GH_POSTED" ]
}

@test "allows private terms when the target is the enterprise host" {
  run "$GH_WRAPPER" pr edit 8 --repo github.acme.example/org/overlay --body "Set up the acme-internal overlay in $HOME/apps."
  [ "$status" -eq 0 ]
  [ -f "$GH_POSTED" ]
}

@test "allows private terms when the github.com repo is private" {
  STUB_VISIBILITY=private run "$GH_WRAPPER" pr edit 8 --repo octo/private-notes --body "acme-internal notes"
  [ "$status" -eq 0 ]
  [ -f "$GH_POSTED" ]
}

@test "listed public repos are guarded even when the lookup says private" {
  STUB_VISIBILITY=private run "$GH_WRAPPER" pr edit 8 --repo fyodoriv/agentbrew --body "acme-internal notes"
  [ "$status" -ne 0 ]
  [ ! -f "$GH_POSTED" ]
}

@test "guards when the visibility lookup fails" {
  STUB_VISIBILITY="" run "$GH_WRAPPER" pr edit 8 --repo octo/tool --body "acme-internal notes"
  [ "$status" -ne 0 ]
  [ ! -f "$GH_POSTED" ]
}

@test "a clean body to a public repo goes through unchanged" {
  run "$GH_WRAPPER" pr edit 8 --repo octo/tool --body "Run it from ~/apps/tool with github.example.com as the host."
  [ "$status" -eq 0 ]
  [ -f "$GH_POSTED" ]
}

@test "DOTFILES_GH_ALLOW_PRIVATE_REFS=1 lets a deliberate post through" {
  DOTFILES_GH_ALLOW_PRIVATE_REFS=1 run "$GH_WRAPPER" pr edit 8 --repo octo/tool --body "acme-internal notes"
  [ "$status" -eq 0 ]
  [ -f "$GH_POSTED" ]
}

@test "read-only commands are not scanned" {
  run "$GH_WRAPPER" pr view 8 --repo octo/tool
  [ "$status" -eq 0 ]
  [ -f "$GH_POSTED" ]
}

@test "the guard works without the overlay pattern file" {
  rm -f "$OSS_READINESS_ENV_FILE"
  run "$GH_WRAPPER" pr comment 8 --repo octo/tool --body "Indexing $HOME/.config/tool"
  [ "$status" -ne 0 ]
  run "$GH_WRAPPER" pr comment 8 --repo octo/tool --body "acme-internal is just a word here"
  [ "$status" -eq 0 ]
}
