#!/usr/bin/env bats
# Leak guard in bin/gh (lib/gh-public-leak.sh): text posted to a PUBLIC
# github.com target must not carry private references. Enterprise hosts and
# private repositories are left alone. Every fixture term here is fake.

load test_helper

GH_WRAPPER="$BATS_TEST_DIRNAME/../bin/gh"
REPO_ROOT="$BATS_TEST_DIRNAME/.."

setup() {
  TEST_DIR="$(mktemp -d)"
  # Keep git from finding a checkout above the temp dir.
  export GIT_CEILING_DIRECTORIES
  GIT_CEILING_DIRECTORIES="$(dirname "$TEST_DIR")"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME"

  # Fixture private patterns. Never the real ones.
  export OSS_READINESS_ENV_FILE="$TEST_DIR/oss-readiness.env"
  cat > "$OSS_READINESS_ENV_FILE" <<'ENV'
OSS_READINESS_INTERNAL_PATTERN='zzwidgetcorp|zz-internal-tool'
OSS_READINESS_PRIVATE_EMAIL_PATTERN='@corp-mail[.]test$'
ENV

  # gh is signed in to github.com and to one enterprise host.
  export GH_CONFIG_DIR="$TEST_DIR/gh-config"
  mkdir -p "$GH_CONFIG_DIR"
  cat > "$GH_CONFIG_DIR/hosts.yml" <<'YML'
github.com:
    user: octo
    git_protocol: ssh
code.widgetco-sso.net:
    user: octo-corp
    git_protocol: https
YML

  GH_STUB="$TEST_DIR/real-gh"
  export GH_POSTED="$TEST_DIR/gh-posted.txt"
  export GH_CALLS="$TEST_DIR/gh-calls.txt"
  export GH_STDIN="$TEST_DIR/gh-stdin.txt"
  export GH_BODY="$TEST_DIR/gh-body.txt"
  cat > "$GH_STUB" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$GH_CALLS"
# Visibility lookups answer from the STUB_* variables.
if [ "$1" = "api" ] && [ "$2" = "--hostname" ] && [[ "$*" == *"--jq .visibility"* ]]; then
  [ -z "${STUB_LOOKUP_FAIL:-}" ] || exit 1
  slug="${4#repos/}"
  case " ${STUB_PRIVATE_SLUGS:-} " in *" $slug "*) echo private; exit 0 ;; esac
  printf '%s\n' "${STUB_VISIBILITY-public}"
  exit 0
fi
printf '%s\n' "$*" > "$GH_POSTED"
prev=""
for a in "$@"; do
  case "$a" in *=@-|-) cat > "$GH_STDIN" ;; esac
  case "$prev" in --body-file|--notes-file) cat "$a" > "$GH_BODY" ;; esac
  prev="$a"
done
exit 0
STUB
  chmod +x "$GH_STUB"
  export DOTFILES_REAL_GH="$GH_STUB"
  unset GH_HOST GH_REPO GH_TOKEN GITHUB_TOKEN MINSKY_PIPELINE \
    DOTFILES_ALLOW_GH_PRIVATE_REFS DOTFILES_GH_ALLOW_PRIVATE_REFS \
    XDG_CONFIG_HOME EXTRA_OVERLAY_ROOT DOTFILES_REPOS_DIR \
    STUB_VISIBILITY STUB_PRIVATE_SLUGS STUB_LOOKUP_FAIL
  # Human context: no footer or PR-create approval rules in the way.
  unset AGENT_PUBLIC_WRITE_GUARD DEVIN_MODEL DEVIN_SESSION_ID \
    CLAUDE_CODE_SSE_PORT CURSOR_AGENT WINDSURF_AGENT CODEX_AGENT
  cd "$TEST_DIR"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# The call was blocked, named "$1" (field: class), and leaked no fixture term.
assert_blocked() {
  echo "$output"
  [ "$status" -eq 1 ]
  [[ "$output" == *"$1"* ]]
  [[ "$output" != *zzwidgetcorp* ]]
  [[ "$output" != *zz-internal-tool* ]]
  [[ "$output" != *corp-mail* ]]
  [ ! -f "$GH_POSTED" ]
}

assert_posted() {
  echo "$output"
  [ "$status" -eq 0 ]
  [ -f "$GH_POSTED" ]
}

no_visibility_lookup() {
  ! grep -q -- '--jq .visibility' "$GH_CALLS" 2>/dev/null
}

make_checkout() {
  local dir="$TEST_DIR/checkout" name url
  git init -q "$dir"
  while [ "$#" -gt 0 ]; do
    name="$1" url="$2"
    shift 2
    git -C "$dir" remote add "$name" "$url"
  done
  printf '%s' "$dir"
}

# ── Text fields ──────────────────────────────────────────────────────

@test "blocks a private term in a PR title" {
  run "$GH_WRAPPER" pr create -R octo/tool --title "Port zzwidgetcorp hooks" --body "Plain body."
  assert_blocked "title: private-pattern match"
  [[ "$output" == *"github.com/octo/tool"* ]]
}

@test "blocks a private term in --body" {
  run "$GH_WRAPPER" pr edit 8 --repo octo/tool --body "Set up the zzwidgetcorp overlay first."
  assert_blocked "body: private-pattern match"
}

@test "blocks a private term in -b and its attached and equals forms" {
  run "$GH_WRAPPER" pr comment 8 -R octo/tool -b "zzwidgetcorp notes"
  assert_blocked "body: private-pattern match"
  run "$GH_WRAPPER" pr comment 8 -R octo/tool "-bzzwidgetcorp notes"
  assert_blocked "body: private-pattern match"
  run "$GH_WRAPPER" pr comment 8 -R octo/tool "--body=zzwidgetcorp notes"
  assert_blocked "body: private-pattern match"
}

@test "blocks a private term in a --body-file" {
  printf 'Notes from the zzwidgetcorp rollout.\n' > "$TEST_DIR/body.md"
  run "$GH_WRAPPER" pr edit 8 --repo octo/tool --body-file "$TEST_DIR/body.md"
  assert_blocked "body: private-pattern match"
}

@test "blocks a private term in a short -F body file" {
  printf 'zz-internal-tool notes\n' > "$TEST_DIR/body.md"
  run "$GH_WRAPPER" issue comment 3 -R octo/tool -F "$TEST_DIR/body.md"
  assert_blocked "body: private-pattern match"
}

@test "blocks a private term in a body read from stdin" {
  run bash -c 'printf "zzwidgetcorp notes" | "$0" issue comment 3 -R octo/tool --body-file -' "$GH_WRAPPER"
  assert_blocked "body: private-pattern match"
}

@test "blocks a private term in release -n notes and -F notes file" {
  run "$GH_WRAPPER" release create v1.0.0 -R octo/tool -n "zzwidgetcorp build"
  assert_blocked "notes: private-pattern match"
  printf 'zzwidgetcorp build\n' > "$TEST_DIR/notes.md"
  run "$GH_WRAPPER" release edit v1.0.0 -R octo/tool -F "$TEST_DIR/notes.md"
  assert_blocked "notes: private-pattern match"
}

@test "blocks a private term in a release asset name" {
  printf 'binary\n' > "$TEST_DIR/zzwidgetcorp-build.tar.gz"
  run "$GH_WRAPPER" release upload v1.0.0 -R octo/tool "$TEST_DIR/zzwidgetcorp-build.tar.gz"
  assert_blocked "asset name: private-pattern match"
}

@test "blocks a private term in a squash-merge subject and body" {
  run "$GH_WRAPPER" pr merge 8 -R octo/tool --squash --subject "Port zzwidgetcorp hooks"
  assert_blocked "subject: private-pattern match"
  run "$GH_WRAPPER" pr merge 8 -R octo/tool --squash -b "Tested on the zzwidgetcorp laptop."
  assert_blocked "body: private-pattern match"
}

@test "blocks a private term in a close comment" {
  run "$GH_WRAPPER" issue close 3 -R octo/tool -c "Moved to zzwidgetcorp tracker."
  assert_blocked "comment: private-pattern match"
}

@test "blocks a private term in a secret gist file" {
  printf 'zzwidgetcorp runbook\n' > "$TEST_DIR/notes.md"
  run "$GH_WRAPPER" gist create "$TEST_DIR/notes.md"
  assert_blocked "gist file: private-pattern match"
}

@test "blocks a private term in a gist file name" {
  printf 'clean text\n' > "$TEST_DIR/zzwidgetcorp-notes.md"
  run "$GH_WRAPPER" gist create --public "$TEST_DIR/zzwidgetcorp-notes.md"
  assert_blocked "gist file name: private-pattern match"
}

@test "blocks a private term in gist edit --desc" {
  run "$GH_WRAPPER" gist edit abc123 --desc "zzwidgetcorp notes"
  assert_blocked "description: private-pattern match"
}

@test "blocks a private term in repo edit -d" {
  run "$GH_WRAPPER" repo edit octo/tool -d "Mirror of zzwidgetcorp tooling"
  assert_blocked "description: private-pattern match"
}

@test "repo create checks public repos only" {
  run "$GH_WRAPPER" repo create octo/new-tool --public -d "zzwidgetcorp tooling"
  assert_blocked "description: private-pattern match"
  run "$GH_WRAPPER" repo create octo/new-tool --private -d "zzwidgetcorp tooling"
  assert_posted
  no_visibility_lookup
}

@test "blocks a private term in a label description and a label name" {
  run "$GH_WRAPPER" label create bug -R octo/tool -d "zzwidgetcorp triage"
  assert_blocked "description: private-pattern match"
  run "$GH_WRAPPER" label create zzwidgetcorp-bug -R octo/tool
  assert_blocked "label name: private-pattern match"
}

@test "blocks a subcommand after a leading -R flag and the new alias" {
  run "$GH_WRAPPER" pr -R octo/tool comment 8 --body "zzwidgetcorp notes"
  assert_blocked "body: private-pattern match"
  run "$GH_WRAPPER" pr new -R octo/tool --title "zzwidgetcorp" --body "x"
  assert_blocked "title: private-pattern match"
}

# ── gh api ───────────────────────────────────────────────────────────

@test "blocks a private term in gh api -f body=" {
  run "$GH_WRAPPER" api -X POST repos/octo/tool/issues/3/comments -f "body=See zzwidgetcorp docs"
  assert_blocked "field body: private-pattern match"
}

@test "blocks a private term in gh api -F body=@file" {
  printf 'zzwidgetcorp docs\n' > "$TEST_DIR/b.md"
  run "$GH_WRAPPER" api -X POST repos/octo/tool/issues/3/comments -F "body=@$TEST_DIR/b.md"
  assert_blocked "field body: private-pattern match"
}

@test "blocks a private term in gh api -F body=@- from stdin" {
  run bash -c 'echo zzwidgetcorp | "$0" api -X POST repos/o/r/issues/1/comments -F body=@-' "$GH_WRAPPER"
  assert_blocked "field body: private-pattern match"
}

@test "blocks a nested private term in gh api --input JSON" {
  printf '{"event":"COMMENT","comments":[{"path":"a.sh","body":"zzwidgetcorp only"}]}\n' > "$TEST_DIR/in.json"
  run "$GH_WRAPPER" api -X POST repos/octo/tool/pulls/3/reviews --input "$TEST_DIR/in.json"
  assert_blocked "input: private-pattern match"
}

@test "blocks a private term in base64 content for the contents API" {
  local encoded
  encoded="$(printf 'owner: zzwidgetcorp\n' | base64)"
  run "$GH_WRAPPER" api -X PUT repos/octo/tool/contents/notes.md -f message=add -f "content=$encoded"
  assert_blocked "field content (decoded): private-pattern match"
}

@test "blocks a private term in a graphql mutation" {
  run "$GH_WRAPPER" api graphql -f 'query=mutation { addComment(input: {subjectId: "X", body: "zzwidgetcorp"}) { clientMutationId } }'
  assert_blocked "field query: private-pattern match"
}

# ── Generic markers (no private pattern needed) ──────────────────────

@test "blocks another user's home path" {
  run "$GH_WRAPPER" issue comment 3 -R octo/tool --body "Logs live in /Users/jdoe-corp/src/app"
  assert_blocked "body: user home path"
}

@test "blocks this machine's home path" {
  run "$GH_WRAPPER" pr comment 8 -R octo/tool --body "Indexing $HOME/.config/tool/skills"
  assert_blocked "body: home path"
}

@test "blocks an enterprise-style host gh is not signed in to" {
  run "$GH_WRAPPER" issue comment 3 -R octo/tool --body "Mirror: https://github.widgetco.net/team/app."
  assert_blocked "body: enterprise-style host"
  run "$GH_WRAPPER" issue comment 3 -R octo/tool --body "Cloud tenant: octo-corp.ghe.com"
  assert_blocked "body: enterprise-style host"
}

@test "blocks a git@ remote on a non-github.com host" {
  run "$GH_WRAPPER" issue comment 3 -R octo/tool --body "team set git@git.widgetco.net:team/app.git"
  assert_blocked "body: ssh host"
}

@test "blocks an enterprise host gh is signed in to" {
  run "$GH_WRAPPER" issue comment 3 -R octo/tool --body "Docs at code.widgetco-sso.net/team"
  assert_blocked "body: enterprise host"
}

@test "blocks a private email" {
  run "$GH_WRAPPER" issue comment 3 -R octo/tool --body "Ping jdoe@corp-mail.test"
  assert_blocked "body: private email"
}

@test "blocks a token-shaped secret" {
  local fake_token
  fake_token="ghp_$(printf 'x%.0s' {1..36})"
  run "$GH_WRAPPER" pr comment 8 -R octo/tool --body "token $fake_token"
  assert_blocked "body: secret"
  [[ "$output" != *"$fake_token"* ]]
}

@test "generic markers block without the private pattern file" {
  rm -f "$OSS_READINESS_ENV_FILE"
  run "$GH_WRAPPER" pr comment 8 -R octo/tool --body "Indexing $HOME/.config/tool"
  assert_blocked "body: home path"
  run "$GH_WRAPPER" pr comment 8 -R octo/tool --body "zzwidgetcorp is just a word here"
  assert_posted
}

# ── Owner's public repos: the pattern file must be armed ──────────────

_sign_in_as_owner() {
  cat > "$GH_CONFIG_DIR/hosts.yml" <<'YML'
github.com:
    user: fyodoriv
    git_protocol: ssh
YML
}

@test "owner post to an owner public repo is blocked when the pattern file is missing" {
  _sign_in_as_owner
  rm -f "$OSS_READINESS_ENV_FILE"
  run "$GH_WRAPPER" pr comment 8 -R fyodoriv/dotfiles --body "plain text"
  assert_blocked "pattern file"
  [[ "$output" == *"github.com/fyodoriv/dotfiles"* ]]
}

@test "owner post to an owner public repo is blocked when the pattern file is outdated" {
  _sign_in_as_owner
  local min
  min="$(cat "$REPO_ROOT/config/oss-readiness-min-version")"
  printf 'OSS_READINESS_PATTERN_VERSION=%s\n' "$((min - 1))" >> "$OSS_READINESS_ENV_FILE"
  run "$GH_WRAPPER" pr comment 8 -R fyodoriv/dotfiles --body "plain text"
  assert_blocked "version $((min - 1))"
}

@test "owner post to an owner public repo goes through with a current pattern file" {
  _sign_in_as_owner
  printf 'OSS_READINESS_PATTERN_VERSION=%s\n' "$(cat "$REPO_ROOT/config/oss-readiness-min-version")" >> "$OSS_READINESS_ENV_FILE"
  run "$GH_WRAPPER" pr comment 8 -R fyodoriv/dotfiles --body "plain text"
  assert_posted
}

@test "another user's post to an owner public repo does not need the pattern file" {
  rm -f "$OSS_READINESS_ENV_FILE"
  run "$GH_WRAPPER" pr comment 8 -R fyodoriv/dotfiles --body "plain text"
  assert_posted
}

# ── Bypass paths that must stay closed ───────────────────────────────

@test "MINSKY_PIPELINE=1 does not skip the guard" {
  MINSKY_PIPELINE=1 run "$GH_WRAPPER" issue comment 3 -R octo/tool --body "see zzwidgetcorp docs"
  assert_blocked "body: private-pattern match"
}

@test "DOTFILES_ALLOW_GH_PRIVATE_REFS=1 lets a deliberate post through" {
  DOTFILES_ALLOW_GH_PRIVATE_REFS=1 run "$GH_WRAPPER" pr edit 8 -R octo/tool --body "zzwidgetcorp notes"
  assert_posted
}

@test "the old DOTFILES_GH_ALLOW_PRIVATE_REFS name no longer bypasses" {
  DOTFILES_GH_ALLOW_PRIVATE_REFS=1 run "$GH_WRAPPER" pr edit 8 -R octo/tool --body "zzwidgetcorp notes"
  assert_blocked "body: private-pattern match"
  [[ "$output" == *"DOTFILES_ALLOW_GH_PRIVATE_REFS=1"* ]]
}

@test "a failed visibility lookup counts as public" {
  STUB_LOOKUP_FAIL=1 run "$GH_WRAPPER" pr edit 8 -R octo/tool --body "zzwidgetcorp notes"
  assert_blocked "body: private-pattern match"
  [[ "$output" == *"could not confirm"* ]]
  STUB_VISIBILITY="" run "$GH_WRAPPER" pr edit 8 -R octo/tool --body "zzwidgetcorp notes"
  assert_blocked "body: private-pattern match"
}

@test "a missing guard lib blocks writes but passes reads" {
  mkdir -p "$TEST_DIR/copy/bin" "$TEST_DIR/copy/lib"
  cp "$GH_WRAPPER" "$TEST_DIR/copy/bin/gh"
  cp "$REPO_ROOT/lib/strip-agent-attribution.sh" "$TEST_DIR/copy/lib/"
  run "$TEST_DIR/copy/bin/gh" issue comment 3 -R octo/tool --body "clean text"
  echo "$output"
  [ "$status" -eq 1 ]
  [[ "$output" == *"gh-public-leak.sh"* ]]
  [ ! -f "$GH_POSTED" ]
  run "$TEST_DIR/copy/bin/gh" pr view 8 -R octo/tool
  assert_posted
}

@test "a fork checkout is guarded when upstream is public and origin is private" {
  cd "$(make_checkout origin git@github.com:me/tool-fork.git upstream https://github.com/octo/tool.git)"
  STUB_PRIVATE_SLUGS="me/tool-fork" run "$GH_WRAPPER" pr comment 8 --body "zzwidgetcorp notes"
  assert_blocked "body: private-pattern match"
  [[ "$output" == *"github.com/octo/tool"* ]]
}

@test "the gh-resolved base remote decides the target" {
  local dir
  dir="$(make_checkout origin git@github.com:me/tool-fork.git upstream https://github.com/octo/tool.git)"
  git -C "$dir" config remote.origin.gh-resolved base
  cd "$dir"
  STUB_PRIVATE_SLUGS="me/tool-fork" run "$GH_WRAPPER" pr comment 8 --body "zzwidgetcorp notes"
  assert_posted
}

@test "a github.com PR URL is guarded from an enterprise checkout" {
  cd "$(make_checkout origin git@code.widgetco-sso.net:team/app.git)"
  run "$GH_WRAPPER" pr comment https://github.com/octo/tool/pull/8 --body "zzwidgetcorp notes"
  assert_blocked "body: private-pattern match"
}

# ── Enterprise and private targets stay untouched ────────────────────

@test "an enterprise target via -R HOST/OWNER/REPO is not scanned" {
  run "$GH_WRAPPER" pr edit 8 -R code.widgetco-sso.net/team/app --body "Set up zzwidgetcorp in $HOME/apps."
  assert_posted
  no_visibility_lookup
}

@test "an enterprise target via GH_HOST or GH_REPO is not scanned" {
  GH_HOST=code.widgetco-sso.net run "$GH_WRAPPER" issue comment 3 -R team/app --body "zzwidgetcorp notes"
  assert_posted
  rm -f "$GH_POSTED"
  GH_REPO=code.widgetco-sso.net/team/app run "$GH_WRAPPER" issue comment 3 --body "zzwidgetcorp notes"
  assert_posted
  no_visibility_lookup
}

@test "an enterprise checkout remote is not scanned" {
  cd "$(make_checkout origin git@code.widgetco-sso.net:team/app.git)"
  run "$GH_WRAPPER" issue comment 3 --body "zzwidgetcorp notes from $HOME/apps"
  assert_posted
  no_visibility_lookup
}

@test "an enterprise PR URL is not scanned from a public checkout" {
  cd "$(make_checkout origin git@github.com:fyodoriv/agentbrew.git)"
  run "$GH_WRAPPER" pr comment https://code.widgetco-sso.net/team/app/pull/8 --body "zzwidgetcorp notes"
  assert_posted
  no_visibility_lookup
}

@test "gh api without --hostname goes to the only signed-in enterprise host" {
  cat > "$GH_CONFIG_DIR/hosts.yml" <<'YML'
code.widgetco-sso.net:
    user: octo-corp
YML
  run "$GH_WRAPPER" api -X POST repos/team/app/issues/1/comments -f "body=zzwidgetcorp notes"
  assert_posted
  no_visibility_lookup
  rm -f "$GH_POSTED"
  run "$GH_WRAPPER" api --hostname code.widgetco-sso.net -X POST repos/team/app/issues/1/comments -f "body=zzwidgetcorp"
  assert_posted
}

@test "a private github.com repo is not blocked" {
  STUB_VISIBILITY=private run "$GH_WRAPPER" pr edit 8 -R octo/private-notes --body "zzwidgetcorp notes"
  assert_posted
}

@test "a listed public repo is guarded with no lookup, even if the API says private" {
  STUB_VISIBILITY=private run "$GH_WRAPPER" pr edit 8 -R fyodoriv/agentbrew --body "zzwidgetcorp notes"
  assert_blocked "body: private-pattern match"
  no_visibility_lookup
}

# ── Clean and read-only calls ────────────────────────────────────────

@test "a clean write to a public repo goes through with no lookup" {
  run "$GH_WRAPPER" pr edit 8 -R octo/tool --body "Plain text."
  assert_posted
  no_visibility_lookup
}

@test "placeholders and public hosts are not private references" {
  # shellcheck disable=SC2016
  run "$GH_WRAPPER" pr comment 8 -R octo/tool --body 'Paths: /Users/<you>/src, ~/apps, /Users/$USER/x, /home/runner/work, /Users/Shared/x.
Hosts: github.example.com, raw.githubusercontent.com, docs.github.com, https://github.com/octo/tool.
Remote: git@github.com:octo/tool.git and ssh://git@github.example.com/team/app.
Actions: ${{ github.event.pull_request.number }} and github.event.repository.name.'
  assert_posted
}

@test "read-only commands make no lookup and post" {
  run "$GH_WRAPPER" pr view 8 -R octo/tool
  assert_posted
  run "$GH_WRAPPER" api repos/octo/tool/pulls/1
  assert_posted
  run "$GH_WRAPPER" api -X GET search/issues -f "q=zzwidgetcorp"
  assert_posted
  run "$GH_WRAPPER" api graphql -f 'query=query { viewer { login } }' -f "note=zzwidgetcorp"
  assert_posted
  no_visibility_lookup
}

@test "stdin still reaches gh after the guard reads it" {
  run bash -c 'printf "clean comment" | "$0" api -X POST repos/octo/tool/issues/1/comments -F body=@-' "$GH_WRAPPER"
  assert_posted
  [ "$(cat "$GH_STDIN")" = "clean comment" ]
  run bash -c 'printf "clean body" | "$0" issue comment 3 -R octo/tool --body-file -' "$GH_WRAPPER"
  assert_posted
  [ "$(cat "$GH_BODY")" = "clean body" ]
}
