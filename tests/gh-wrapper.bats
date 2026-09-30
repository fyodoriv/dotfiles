#!/usr/bin/env bats

load test_helper

GH_WRAPPER="$BATS_TEST_DIRNAME/../bin/gh"

setup() {
  TEST_DIR="$(mktemp -d)"
  GH_STUB="$TEST_DIR/real-gh"
  GH_ARGS="$TEST_DIR/gh-args.txt"
  GH_BODY="$TEST_DIR/gh-body.md"
  GH_COMMENT="$TEST_DIR/gh-comment.txt"
  GH_API_BODY="$TEST_DIR/gh-api-body.md"
  GH_API_INPUT="$TEST_DIR/gh-api-input.json"
  cat > "$GH_STUB" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" > "$GH_ARGS"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --body-file|--notes-file)
      shift
      cat "$1" > "$GH_BODY"
      ;;
    --comment|-c)
      shift
      printf '%s' "$1" > "$GH_COMMENT"
      ;;
    --input)
      shift
      # Capture the JSON document the wrapper passed via --input so
      # the api-input tests can inspect strip + footer behaviour
      # the same way the api-body tests inspect $GH_API_BODY.
      cat "$1" > "$GH_API_INPUT"
      ;;
    -f|--field|-F|--raw-field)
      shift
      case "$1" in
        body=*)
          # Capture every `body=…` field value the wrapper emitted so
          # the api-body tests can inspect strip + footer behaviour
          # the same way the body-file tests inspect $GH_BODY.
          printf '%s' "${1#body=}" > "$GH_API_BODY"
          ;;
      esac
      ;;
  esac
  shift || break
done
printf 'https://github.example/pr/1\n'
exit 0
STUB
  chmod +x "$GH_STUB"
  export DOTFILES_REAL_GH="$GH_STUB"
  export GH_ARGS
  export GH_BODY
  export GH_COMMENT
  export GH_API_BODY
  export GH_API_INPUT
}

teardown() {
  rm -rf "$TEST_DIR"
}


agent_pr_validation_prefix() {
  printf '%s\n'     '## Requirements checklist'     '- [x] test requirement'     ''     '## Previous state'     '1. before state'     ''     '## Validation steps'     '1. verify'
}

agent_pr_approval() {
  local repo="$1" base="$2" title="$3" body="$4" body_sha
  body_sha="$(printf '%s' "$body" | shasum -a 256 | awk '{print $1}')"
  printf 'repo=%s base=%s title=%s body_sha256=%s' "$repo" "$base" "$title" "$body_sha"
}

@test "agent PR create appends canonical footer when body had no vendor footer" {
  local expected_body approval
  expected_body=$'## Requirements checklist\n- [x] test requirement\n\n## Previous state\n1. before state\n\n## Validation steps\n1. verify\n\n## Why this is needed\nFixes an unsafe public write path.\n\n---\n_🤖 Written by an agent, not Fyodor. Ping me if this looks off._\n'
  approval="$(agent_pr_approval "your-org/example-cli" "master" "fix: guard" "$expected_body")"

  run env AGENT_PUBLIC_WRITE_GUARD=1 AGENT_PUBLIC_WRITE_APPROVAL="$approval" "$GH_WRAPPER" pr create \
    --repo your-org/example-cli \
    --title "fix: guard" \
    --base master \
    --body $'## Requirements checklist\n- [x] test requirement\n\n## Previous state\n1. before state\n\n## Validation steps\n1. verify\n\n## Why this is needed\nFixes an unsafe public write path.'

  [ "$status" -eq 0 ]
  grep -q "Written by an agent, not Fyodor" "$GH_BODY"
}

@test "agent PR create with --body-file - still appends footer and validates approval" {
  local input_body expected_body approval
  input_body=$'## Requirements checklist\n- [x] test requirement\n\n## Previous state\n1. before state\n\n## Validation steps\n1. verify\n\n## Why this is needed\nFixes the stdin body path from the incident.'
  expected_body=$'## Requirements checklist\n- [x] test requirement\n\n## Previous state\n1. before state\n\n## Validation steps\n1. verify\n\n## Why this is needed\nFixes the stdin body path from the incident.\n\n---\n_🤖 Written by an agent, not Fyodor. Ping me if this looks off._\n'
  approval="$(agent_pr_approval "your-org/example-cli" "master" "fix: guard stdin" "$expected_body")"

  run env AGENT_PUBLIC_WRITE_GUARD=1 \
    AGENT_PUBLIC_WRITE_APPROVAL="$approval" \
    GH_WRAPPER="$GH_WRAPPER" INPUT_BODY="$input_body" \
    bash -c 'printf "%s" "$INPUT_BODY" | "$GH_WRAPPER" pr create --repo your-org/example-cli --title "fix: guard stdin" --base master --body-file -'

  [ "$status" -eq 0 ]
  grep -q "Fixes the stdin body path" "$GH_BODY"
  grep -q "Written by an agent, not Fyodor" "$GH_BODY"
}

@test "agent PR create blocks bodies without rationale" {
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" pr create \
    --title "fix: guard" \
    --base main \
    --body "Fixes an unsafe public write path."

  [ "$status" -eq 1 ]
  [[ "$output" == *"Why this is needed"* ]]
}

@test "agent PR create blocks bodies without validation sections" {
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" pr create \
    --title "fix: guard" \
    --base main \
    --body $'## Why this is needed\nFixes foo because bar broke.\n\n## Summary\nShip it.'

  [ "$status" -eq 1 ]
  [[ "$output" == *"Requirements checklist"* ]]
  [[ "$output" == *"Validation steps"* ]]
}

@test "agent PR create allows bodies with rationale and validation sections" {
  local expected_body approval
  expected_body=$'## Requirements checklist\n- [x] fix bug\n\n## Previous state\n1. repro\n\n## Validation steps\n1. verify\n\n## Why this is needed\nFixes foo because bar broke.\n\n---\n_🤖 Written by an agent, not Fyodor. Ping me if this looks off._\n'
  approval="$(agent_pr_approval "your-org/example-cli" "master" "fix: guard" "$expected_body")"

  run env AGENT_PUBLIC_WRITE_GUARD=1 AGENT_PUBLIC_WRITE_APPROVAL="$approval" "$GH_WRAPPER" pr create \
    --repo your-org/example-cli \
    --title "fix: guard" \
    --base master \
    --body $'## Requirements checklist\n- [x] fix bug\n\n## Previous state\n1. repro\n\n## Validation steps\n1. verify\n\n## Why this is needed\nFixes foo because bar broke.'

  [ "$status" -eq 0 ]
  grep -q "Requirements checklist" "$GH_BODY"
  grep -q "Validation steps" "$GH_BODY"
}

@test "agent PR create normalizes hard-wrapped prose paragraphs" {
  local expected_body approval
  expected_body=$'## Requirements checklist\n- [x] test requirement\n\n## Previous state\n1. before state\n\n## Validation steps\n1. verify\n\n## Why this is needed\nThis paragraph was hard wrapped by an agent into several short lines.\n\n---\n_🤖 Written by an agent, not Fyodor. Ping me if this looks off._\n'
  approval="$(agent_pr_approval "your-org/example-cli" "master" "fix: guard" "$expected_body")"

  run env AGENT_PUBLIC_WRITE_GUARD=1 AGENT_PUBLIC_WRITE_APPROVAL="$approval" "$GH_WRAPPER" pr create \
    --repo your-org/example-cli \
    --title "fix: guard" \
    --base master \
    --body $'## Requirements checklist\n- [x] test requirement\n\n## Previous state\n1. before state\n\n## Validation steps\n1. verify\n\n## Why this is needed\nThis paragraph was hard wrapped\nby an agent into several\nshort lines.'

  [ "$status" -eq 0 ]
  grep -q "This paragraph was hard wrapped by an agent into several short lines." "$GH_BODY"
}

@test "agent PR create keeps consecutive numbered list items on their own lines" {
  local expected_body approval
  expected_body=$'## Requirements checklist\n- [x] test requirement\n\n## Previous state\n1. before state\n\n## Validation steps\n1. build\n2. test\n10. ship\n\n## Why this is needed\nFixes list rendering.\n\n---\n_🤖 Written by an agent, not Fyodor. Ping me if this looks off._\n'
  approval="$(agent_pr_approval "your-org/example-cli" "master" "fix: guard" "$expected_body")"

  run env AGENT_PUBLIC_WRITE_GUARD=1 AGENT_PUBLIC_WRITE_APPROVAL="$approval" "$GH_WRAPPER" pr create \
    --repo your-org/example-cli \
    --title "fix: guard" \
    --base master \
    --body $'## Requirements checklist\n- [x] test requirement\n\n## Previous state\n1. before state\n\n## Validation steps\n1. build\n2. test\n10. ship\n\n## Why this is needed\nFixes list rendering.'

  [ "$status" -eq 0 ]
  [[ "$output" != *"regexp escape sequence"* ]]
  grep -qx "2. test" "$GH_BODY"
  grep -qx "10. ship" "$GH_BODY"
}

@test "agent PR create requires approval token with body hash" {
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" pr create \
    --repo your-org/example-cli \
    --title "fix: guard" \
    --base master \
    --body $'## Requirements checklist\n- [x] test requirement\n\n## Previous state\n1. before state\n\n## Validation steps\n1. verify\n\n## Why this is needed\nFixes an unsafe public write path.'

  [ "$status" -eq 1 ]
  [[ "$output" == *"blocked agent-authored PR create"* ]]
  [[ "$output" == *"body_sha256="* ]]
}

@test "agent PR create requires approval even for trusted delivery repos" {
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" pr create \
    --repo github.example.com/your-org/example-repo \
    --title "fix: trusted delivery" \
    --base main \
    --body $'## Requirements checklist\n- [x] test requirement\n\n## Previous state\n1. before state\n\n## Validation steps\n1. verify\n\n## Why needed\nKeeps routine trusted-repo delivery explicit.'

  [ "$status" -eq 1 ]
  [[ "$output" == *"blocked agent-authored PR create"* ]]
  [[ "$output" == *"repo=github.example.com/your-org/example-repo"* ]]
  [ ! -f "$GH_BODY" ]
}

make_origin_checkout() {
  local dir="$TEST_DIR/checkout"
  git init -q "$dir"
  git -C "$dir" remote add origin "$1"
  printf '%s' "$dir"
}

@test "agent PR create treats HOST/OWNER/REPO of the current checkout as the same repo" {
  cd "$(make_origin_checkout git@github.example.com:your-org/example-repo.git)"

  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" pr create \
    --repo github.example.com/your-org/example-repo \
    --title "fix: same repo" \
    --base main \
    --body $'## Requirements checklist\n- [x] test requirement\n\n## Previous state\n1. before state\n\n## Validation steps\n1. verify\n\n## Why this is needed\nSame repo, host-qualified.'

  [ "$status" -eq 0 ]
  [ -f "$GH_BODY" ]
}

@test "agent PR create still gates the same OWNER/REPO on another host" {
  cd "$(make_origin_checkout git@github.example.com:your-org/example-repo.git)"

  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" pr create \
    --repo github.com/your-org/example-repo \
    --title "fix: other host" \
    --base main \
    --body $'## Requirements checklist\n- [x] test requirement\n\n## Previous state\n1. before state\n\n## Validation steps\n1. verify\n\n## Why this is needed\nA public mirror is a different repo.'

  [ "$status" -eq 1 ]
  [[ "$output" == *"blocked agent-authored PR create"* ]]
  [ ! -f "$GH_BODY" ]
}

@test "agent PR create allowlist does not cover the same OWNER/REPO on another host" {
  local allowlist="$TEST_DIR/allowlist.txt"
  printf 'your-org/example-repo\n' > "$allowlist"
  cd "$(make_origin_checkout git@github.example.com:your-org/example-repo.git)"

  run env AGENT_PUBLIC_WRITE_GUARD=1 AGENT_GH_ALLOWLIST_FILE="$allowlist" "$GH_WRAPPER" pr create \
    --repo github.com/your-org/example-repo \
    --title "fix: public host" \
    --base main \
    --body $'## Requirements checklist\n- [x] test requirement\n\n## Previous state\n1. before state\n\n## Validation steps\n1. verify\n\n## Why this is needed\nThe allowlist names the enterprise repo only.'

  [ "$status" -eq 1 ]
  [[ "$output" == *"blocked agent-authored PR create"* ]]
  [ ! -f "$GH_BODY" ]
}

@test "agent PR create accepts the ship-it Summary heading as the rationale" {
  cd "$(make_origin_checkout https://github.example.com/your-org/example-repo.git)"

  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" pr create \
    --title "fix: ship-it body" \
    --base main \
    --body $'## Summary\nThe preview went stale after a 409. Now it refreshes.\n\n## Details\n- apply refreshes the preview\n\n## Requirements checklist\n- [x] test requirement\n\n## Previous state\n1. before state\n\n## Validation steps\n1. verify'

  [ "$status" -eq 0 ]
  grep -q "^## Summary" "$GH_BODY"
}

@test "agent PR create skips approval gate when target repo is allowlisted" {
  local allowlist="$TEST_DIR/allowlist.txt"
  cat > "$allowlist" <<'ALLOW'
# blanket-approved repos
your-org/example-repo
your-org/another-allowed   # trailing comment

  your-org/whitespace-ok
ALLOW

  run env \
    AGENT_PUBLIC_WRITE_GUARD=1 \
    AGENT_GH_ALLOWLIST_FILE="$allowlist" \
    "$GH_WRAPPER" pr create \
    --repo your-org/example-repo \
    --title "feat: covered by allowlist" \
    --base main \
    --body $'## Requirements checklist\n- [x] test requirement\n\n## Previous state\n1. before state\n\n## Validation steps\n1. verify\n\n## Why this is needed\nRepo lives in the per-machine allowlist.'

  [ "$status" -eq 0 ]
  [ -f "$GH_BODY" ]
  grep -q "Written by an agent, not Fyodor" "$GH_BODY"
}

@test "agent PR create allowlist tolerates comments, blank lines, and whitespace" {
  local allowlist="$TEST_DIR/allowlist.txt"
  cat > "$allowlist" <<'ALLOW'

# leading comment
  your-org/whitespace-ok  
# trailing comment line
ALLOW

  run env \
    AGENT_PUBLIC_WRITE_GUARD=1 \
    AGENT_GH_ALLOWLIST_FILE="$allowlist" \
    "$GH_WRAPPER" pr create \
    --repo your-org/whitespace-ok \
    --title "feat: pad" \
    --base main \
    --body $'## Requirements checklist\n- [x] test requirement\n\n## Previous state\n1. before state\n\n## Validation steps\n1. verify\n\n## Why this is needed\nWhitespace-padded entries should still match.'

  [ "$status" -eq 0 ]
}

@test "agent PR create allowlist with missing file falls through to per-PR approval gate" {
  run env \
    AGENT_PUBLIC_WRITE_GUARD=1 \
    AGENT_GH_ALLOWLIST_FILE="$TEST_DIR/does-not-exist.txt" \
    "$GH_WRAPPER" pr create \
    --repo your-org/example-repo \
    --title "fix: missing allowlist file" \
    --base main \
    --body $'## Requirements checklist\n- [x] test requirement\n\n## Previous state\n1. before state\n\n## Validation steps\n1. verify\n\n## Why this is needed\nNo allowlist file means strict approval.'

  [ "$status" -eq 1 ]
  [[ "$output" == *"blocked agent-authored PR create"* ]]
}

@test "agent PR create allowlist with unrelated entries does not approve target repo" {
  local allowlist="$TEST_DIR/allowlist.txt"
  cat > "$allowlist" <<'ALLOW'
your-org/something-else
another-org/totally-different
ALLOW

  run env \
    AGENT_PUBLIC_WRITE_GUARD=1 \
    AGENT_GH_ALLOWLIST_FILE="$allowlist" \
    "$GH_WRAPPER" pr create \
    --repo your-org/example-repo \
    --title "fix: not on the list" \
    --base main \
    --body $'## Requirements checklist\n- [x] test requirement\n\n## Previous state\n1. before state\n\n## Validation steps\n1. verify\n\n## Why this is needed\nTarget repo is not in the allowlist.'

  [ "$status" -eq 1 ]
  [[ "$output" == *"blocked agent-authored PR create"* ]]
}

# ── pr close|reopen + issue close|reopen --comment coverage ──────────────────
#
# Regression: orchestrator-driven `gh pr close --comment "..."`
# calls posted the comment under Fyodor's identity without the canonical
# agent footer because the wrapper's allow-list only covered create / edit
# / comment / review. The cases below pin the extended scope so that
# regression cannot land again. They also verify
# the agent-context gating: agents always get the footer auto-appended,
# humans don't.

@test "pr close --comment appends footer in agent context (regression)" {
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" pr close 1561 \
    --repo github.example.com/your-org/example-repo \
    --delete-branch \
    --comment "Closing — generated by orchestrator pipeline that pushed an empty workspace branch."

  [ "$status" -eq 0 ]
  [ -f "$GH_COMMENT" ]
  grep -q "Written by an agent, not Fyodor" "$GH_COMMENT"
  grep -q "Closing" "$GH_COMMENT"
}

@test "pr close -c (short form) appends footer in agent context" {
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" pr close 42 -c "Closing as no-longer-needed."

  [ "$status" -eq 0 ]
  [ -f "$GH_COMMENT" ]
  grep -q "Written by an agent, not Fyodor" "$GH_COMMENT"
}

@test "pr close --comment=value (equals form) appends footer in agent context" {
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" pr close 99 --comment="Closing — superseded by a later PR."

  [ "$status" -eq 0 ]
  [ -f "$GH_COMMENT" ]
  grep -q "Written by an agent, not Fyodor" "$GH_COMMENT"
}

@test "pr close --comment is idempotent when footer already present (agent context)" {
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" pr close 100 \
    --comment $'Closing — already attributed.\n\n---\n_🤖 Written by an agent, not Fyodor. Ping me if this looks off._'

  [ "$status" -eq 0 ]
  [ -f "$GH_COMMENT" ]
  local footer_count
  footer_count=$(grep -c "Written by an agent, not Fyodor" "$GH_COMMENT")
  [ "$footer_count" = "1" ]
}

# Regression: when an agent rule injects its own
# "Written by an agent, not <github-username>" footer (the template used to
# expand `{{ user_name }}` into the GitHub login, not the canonical name),
# the wrapper used to stack a second canonical "not Fyodor" footer on top,
# producing two divider blocks at the end of the comment. We now normalize
# any foreign agent footer to the single canonical Fyodor one.
@test "pr close --comment strips foreign agent footer and emits exactly one canonical footer" {
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" pr close 101 \
    --comment $'Body line.\n\n---\n_🤖 Written by an agent, not the-owner. Ping me if this looks off._'

  [ "$status" -eq 0 ]
  [ -f "$GH_COMMENT" ]
  ! grep -q "Written by an agent, not the-owner" "$GH_COMMENT"
  local footer_count
  footer_count=$(grep -c "Written by an agent, not Fyodor" "$GH_COMMENT")
  [ "$footer_count" = "1" ]
  local divider_count
  divider_count=$(grep -c '^---$' "$GH_COMMENT")
  [ "$divider_count" = "1" ]
}

@test "pr close strips foreign agent attribution from --comment (agent context)" {
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" pr close 200 \
    --comment $'Closing — was created by an agent.\n\nGenerated with [Devin](https://devin.ai)\nCo-Authored-By: Devin <devin-ai-integration[bot]@users.noreply.github.com>'

  [ "$status" -eq 0 ]
  [ -f "$GH_COMMENT" ]
  ! grep -q "Generated with \[Devin\]" "$GH_COMMENT"
  ! grep -qi "Co-Authored-By: Devin" "$GH_COMMENT"
  grep -q "Written by an agent, not Fyodor" "$GH_COMMENT"
}

@test "pr reopen --comment appends footer in agent context" {
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" pr reopen 50 --comment "Reopening — fix landed in main."

  [ "$status" -eq 0 ]
  [ -f "$GH_COMMENT" ]
  grep -q "Written by an agent, not Fyodor" "$GH_COMMENT"
}

@test "issue close --comment appends footer in agent context" {
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" issue close 200 --comment "Closing — fixed in 2026-04 sprint."

  [ "$status" -eq 0 ]
  [ -f "$GH_COMMENT" ]
  grep -q "Written by an agent, not Fyodor" "$GH_COMMENT"
}

@test "issue reopen --comment appends footer in agent context" {
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" issue reopen 201 --comment "Reopening — regression observed in 2026-05."

  [ "$status" -eq 0 ]
  [ -f "$GH_COMMENT" ]
  grep -q "Written by an agent, not Fyodor" "$GH_COMMENT"
}

@test "pr close --comment leaves text unchanged for human-context invocation (no auto-footer)" {
  # Defence against false-positive on the footer rule: when no agent
  # marker env vars are set, the wrapper must NOT auto-append Fyodor's
  # footer to a human-authored close comment.
  #
  # Explicitly unset every agent-detection env var the wrapper's
  # `_gh_wrapper_is_agent_context` consults. Without this, DEVIN_MODEL
  # leaks from the operator's interactive shell (set by zshrc.ai-tools)
  # and the wrapper unconditionally appends the footer — combined with
  # bash's POSIX `set -e` silencing for negated commands, the `! grep`
  # below would silently pass even when the negation logically fails.
  # Matches the env-isolation pattern in the "gh api --input" test below.
  run env -u AGENT_PUBLIC_WRITE_GUARD -u DEVIN_MODEL -u DEVIN_SESSION_ID \
         -u CLAUDE_CODE_SSE_PORT -u CURSOR_AGENT -u WINDSURF_AGENT \
         -u CODEX_AGENT \
    "$GH_WRAPPER" pr close 400 --comment "Thanks for the contribution!"

  [ "$status" -eq 0 ]
  [ -f "$GH_COMMENT" ]
  ! grep -q "Written by an agent" "$GH_COMMENT"
  grep -q "Thanks for the contribution" "$GH_COMMENT"
}

# ── pr comment / pr edit footer coverage ────────────────────────────────────
#
# Same regression class: before the footer fix, `_ensure_agent_footer`
# only ran for `pr create`. Agent-authored `gh pr comment` / `gh pr edit`
# / `gh issue comment` calls posted under Fyodor's identity without the
# canonical footer. These tests pin the agent-context behaviour so the
# fix can never quietly regress.

@test "pr comment --body appends footer in agent context" {
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" pr comment 1565 \
    --body $'Correction on the previous comment — see the new wrapper coverage.'

  [ "$status" -eq 0 ]
  [ -f "$GH_BODY" ]
  grep -q "Written by an agent, not Fyodor" "$GH_BODY"
}

@test "pr comment --body leaves human-authored text unchanged (no auto-footer)" {
  # Env-isolation per the same rationale as the `pr close --comment`
  # human-context test above: scrub the agent-detection env vars so
  # `! grep -q "Written by an agent"` is meaningful instead of silent.
  run env -u AGENT_PUBLIC_WRITE_GUARD -u DEVIN_MODEL -u DEVIN_SESSION_ID \
         -u CLAUDE_CODE_SSE_PORT -u CURSOR_AGENT -u WINDSURF_AGENT \
         -u CODEX_AGENT \
    "$GH_WRAPPER" pr comment 1565 --body "Thanks!"

  [ "$status" -eq 0 ]
  [ -f "$GH_BODY" ]
  ! grep -q "Written by an agent" "$GH_BODY"
  grep -q "Thanks!" "$GH_BODY"
}

@test "issue comment --body appends footer in agent context" {
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" issue comment 100 \
    --body $'Triaged — root cause identified, PR coming.'

  [ "$status" -eq 0 ]
  [ -f "$GH_BODY" ]
  grep -q "Written by an agent, not Fyodor" "$GH_BODY"
}

@test "pr close without --comment is a pure pass-through (no comment file written)" {
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" pr close 300 --delete-branch

  [ "$status" -eq 0 ]
  [ ! -f "$GH_COMMENT" ]
  grep -q "pr close 300 --delete-branch" "$GH_ARGS"
}

@test "pr view (read-only) remains pure pass-through after extending the allow-list" {
  run "$GH_WRAPPER" pr view 1
  [ "$status" -eq 0 ]
  [ ! -f "$GH_COMMENT" ]
  [ ! -f "$GH_BODY" ]
  grep -q "pr view 1" "$GH_ARGS"
}

@test "release create does not treat -c as a comment flag" {
  # Defence against false-positive on the new --comment / -c handler:
  # release subcommands also have short flags, but `-c` is not one of
  # them. The wrapper must only intercept --comment / -c on the
  # close/reopen subcommands. This test makes sure the release path is
  # untouched.
  run "$GH_WRAPPER" release create v1.2.3 \
    --notes $'## Why this is needed\nShipping v1.2.3 with bug fixes.'

  [ "$status" -eq 0 ]
  [ -f "$GH_BODY" ]
  [ ! -f "$GH_COMMENT" ]
  grep -q "Why this is needed" "$GH_BODY"
}

# `gh api -f body=…` coverage. Agents can post review-comment replies
# and other comment-shaped bodies via the raw API surface (e.g.
# `gh api -X POST repos/.../pulls/comments/<id>/replies -f body=…`).
# Before this coverage existed, those calls bypassed the wrapper's
# strip + footer pipeline entirely (regression observed on
# workspace-capabilities#1952 review-comment reply). These tests
# pin the agent-context behaviour so the gap can never quietly reopen.

@test "gh api -f body= appends footer in agent context" {
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" api \
    -X POST repos/owner/repo/pulls/comments/123/replies \
    -f "body=Replying to a review comment thread."

  [ "$status" -eq 0 ]
  [ -f "$GH_API_BODY" ]
  grep -q "Replying to a review comment thread." "$GH_API_BODY"
  grep -q "Written by an agent, not Fyodor" "$GH_API_BODY"
}

@test "gh api --field body= appends footer in agent context" {
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" api \
    -X POST repos/owner/repo/issues/100/comments \
    --field "body=Triaged — root cause identified."

  [ "$status" -eq 0 ]
  [ -f "$GH_API_BODY" ]
  grep -q "Triaged" "$GH_API_BODY"
  grep -q "Written by an agent, not Fyodor" "$GH_API_BODY"
}

@test "gh api -F body= (raw-field short) appends footer in agent context" {
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" api \
    -X PATCH repos/owner/repo/pulls/comments/456 \
    -F "body=Updating my earlier review note."

  [ "$status" -eq 0 ]
  [ -f "$GH_API_BODY" ]
  grep -q "Updating my earlier" "$GH_API_BODY"
  grep -q "Written by an agent, not Fyodor" "$GH_API_BODY"
}

@test "gh api -f=body= (equals form) appends footer in agent context" {
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" api \
    -X POST repos/owner/repo/pulls/1/reviews \
    "-f=body=Approving with one nit."

  [ "$status" -eq 0 ]
  [ -f "$GH_API_BODY" ]
  grep -q "Approving with one nit." "$GH_API_BODY"
  grep -q "Written by an agent, not Fyodor" "$GH_API_BODY"
}

@test "gh api -f body= leaves human-authored text unchanged (no auto-footer)" {
  run "$GH_WRAPPER" api \
    -X POST repos/owner/repo/issues/100/comments \
    -f "body=Thanks!"

  [ "$status" -eq 0 ]
  [ -f "$GH_API_BODY" ]
  ! grep -q "Written by an agent" "$GH_API_BODY"
  grep -q "Thanks!" "$GH_API_BODY"
}

@test "gh api -f body= strips foreign agent attribution in agent context" {
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" api \
    -X POST repos/owner/repo/issues/100/comments \
    -f $'body=Useful context here.\n\nGenerated with [Devin](https://devin.ai/)\n\nCo-Authored-By: Devin <devin@example.com>'

  [ "$status" -eq 0 ]
  [ -f "$GH_API_BODY" ]
  grep -q "Useful context here." "$GH_API_BODY"
  ! grep -q "Generated with \[Devin\]" "$GH_API_BODY"
  ! grep -q "Co-Authored-By: Devin" "$GH_API_BODY"
  grep -q "Written by an agent, not Fyodor" "$GH_API_BODY"
}

@test "gh api -f body= is idempotent when footer already present (agent context)" {
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" api \
    -X POST repos/owner/repo/issues/100/comments \
    -f $'body=Thanks for the review!\n\n---\n_🤖 Written by an agent, not Fyodor. Ping me if this looks off._'

  [ "$status" -eq 0 ]
  [ -f "$GH_API_BODY" ]
  # Exactly one occurrence of the footer line — no duplication.
  count="$(grep -c 'Written by an agent, not Fyodor' "$GH_API_BODY")"
  [ "$count" = "1" ]
}

@test "gh api with no -f body= field is a pure pass-through" {
  # gh api calls that don't post body content (read-only queries,
  # field-typed flags for non-body keys) must not get touched.
  run "$GH_WRAPPER" api repos/owner/repo/pulls/1
  [ "$status" -eq 0 ]
  [ ! -f "$GH_API_BODY" ]
  grep -q "api repos/owner/repo/pulls/1" "$GH_ARGS"
}

@test "gh api -f title= (non-body field) is left untouched" {
  # When -f appears with a non-body key, the wrapper must not
  # mistakenly intercept it. This guards against a regression where
  # the wrapper greedily consumed any -f value.
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" api \
    -X POST repos/owner/repo/issues \
    -f "title=My new issue" \
    -f "body=Filing this for follow-up."

  [ "$status" -eq 0 ]
  # body= field still got the footer treatment …
  [ -f "$GH_API_BODY" ]
  grep -q "Filing this for follow-up." "$GH_API_BODY"
  grep -q "Written by an agent, not Fyodor" "$GH_API_BODY"
  # … and the title= field was forwarded verbatim.
  grep -q "title=My new issue" "$GH_ARGS"
}

# ── `gh api --input <file>` coverage ─────────────────────────────────
#
# Agents can post a full JSON payload via `gh api --input body.json`
# — that path bypasses -f / --field / --raw-field, so without the
# JSON-aware filter the strip + footer pipeline would be skipped and
# Devin's foreign attribution + a bare body would land verbatim. The
# wrapper now parses the JSON via jq, runs top-level string-valued
# `body` / `note` fields through the same pipeline as -f body=, and
# substitutes --input <tmpfile>.

_write_input_json() {
  # Write JSON to a file inside TEST_DIR; print the path.
  local path="$TEST_DIR/input-$BATS_TEST_NUMBER.json"
  cat > "$path"
  printf '%s' "$path"
}

@test "gh api --input appends footer in agent context" {
  input=$(printf '{"body":"Replying via --input."}' | _write_input_json)
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" api \
    -X POST repos/owner/repo/pulls/1/comments \
    --input "$input"

  [ "$status" -eq 0 ]
  [ -f "$GH_API_INPUT" ]
  grep -q "Replying via --input." "$GH_API_INPUT"
  grep -q "Written by an agent, not Fyodor" "$GH_API_INPUT"
  # And the original input file is left untouched on disk.
  grep -qv "Written by an agent, not Fyodor" "$input"
}

@test "gh api --input=file form appends footer in agent context" {
  input=$(printf '{"body":"Equals form path."}' | _write_input_json)
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" api \
    -X POST repos/owner/repo/issues/9/comments \
    --input="$input"

  [ "$status" -eq 0 ]
  [ -f "$GH_API_INPUT" ]
  grep -q "Equals form path." "$GH_API_INPUT"
  grep -q "Written by an agent, not Fyodor" "$GH_API_INPUT"
}

@test "gh api --input - reads from stdin and filters" {
  run env AGENT_PUBLIC_WRITE_GUARD=1 bash -c '
    printf "%s" "{\"body\":\"From stdin.\"}" |
      "$0" api -X POST repos/owner/repo/pulls/2/comments --input -
  ' "$GH_WRAPPER"

  [ "$status" -eq 0 ]
  [ -f "$GH_API_INPUT" ]
  grep -q "From stdin." "$GH_API_INPUT"
  grep -q "Written by an agent, not Fyodor" "$GH_API_INPUT"
}

@test "gh api --input leaves human-authored body unchanged (no auto-footer)" {
  input=$(printf '{"body":"Human reply via --input."}' | _write_input_json)
  # Explicitly unset every agent-detection env var that the wrapper's
  # `_gh_wrapper_is_agent_context` consults. Without this, DEVIN_MODEL
  # leaks from the operator's interactive shell (set by zshrc.ai-tools)
  # and the wrapper unconditionally appends the footer — making this
  # test silently meaningless under the operator's normal shell.
  run env -u AGENT_PUBLIC_WRITE_GUARD -u DEVIN_MODEL -u DEVIN_SESSION_ID \
         -u CLAUDE_CODE_SSE_PORT -u CURSOR_AGENT -u WINDSURF_AGENT \
         -u CODEX_AGENT \
    "$GH_WRAPPER" api \
      -X POST repos/owner/repo/issues/9/comments \
      --input "$input"

  [ "$status" -eq 0 ]
  [ -f "$GH_API_INPUT" ]
  grep -q "Human reply via --input." "$GH_API_INPUT"
  ! grep -q "Written by an agent, not Fyodor" "$GH_API_INPUT"
}

@test "gh api --input strips foreign agent attribution in agent context" {
  input=$(_write_input_json <<'JSON'
{"body":"Useful context here.\n\nGenerated with [Devin](https://devin.ai/)\n\nCo-Authored-By: Devin <devin@example.com>"}
JSON
  )
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" api \
    -X POST repos/owner/repo/issues/9/comments \
    --input "$input"

  [ "$status" -eq 0 ]
  [ -f "$GH_API_INPUT" ]
  grep -q "Useful context here." "$GH_API_INPUT"
  ! grep -q "devin@example.com" "$GH_API_INPUT"
  ! grep -q "Generated with \[Devin\]" "$GH_API_INPUT"
  grep -q "Written by an agent, not Fyodor" "$GH_API_INPUT"
}

@test "gh api --input is idempotent when footer already present" {
  input=$(_write_input_json <<'JSON'
{"body":"Thanks for the review!\n\n---\n_🤖 Written by an agent, not Fyodor. Ping me if this looks off._"}
JSON
  )
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" api \
    -X POST repos/owner/repo/issues/9/comments \
    --input "$input"

  [ "$status" -eq 0 ]
  # Exactly one canonical footer in the result — no duplication.
  [ -f "$GH_API_INPUT" ]
  footer_count=$(grep -c "Written by an agent, not Fyodor" "$GH_API_INPUT" || true)
  [ "$footer_count" = "1" ]
}

@test "gh api --input with no body field is a pure pass-through" {
  input=$(printf '{"title":"Just a title","draft":true}' | _write_input_json)
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" api \
    -X POST repos/owner/repo/pulls \
    --input "$input"

  [ "$status" -eq 0 ]
  [ -f "$GH_API_INPUT" ]
  # Object shape preserved; no body, no footer injected.
  grep -q '"title"' "$GH_API_INPUT"
  grep -q '"draft"' "$GH_API_INPUT"
  ! grep -q "body" "$GH_API_INPUT"
  ! grep -q "Written by an agent, not Fyodor" "$GH_API_INPUT"
}

@test "gh api --input filters note field (project cards)" {
  input=$(printf '{"note":"Project card note from agent."}' | _write_input_json)
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" api \
    -X POST projects/columns/1/cards \
    --input "$input"

  [ "$status" -eq 0 ]
  [ -f "$GH_API_INPUT" ]
  grep -q "Project card note from agent." "$GH_API_INPUT"
  grep -q "Written by an agent, not Fyodor" "$GH_API_INPUT"
}

@test "gh api --input ignores nested body fields (top-level only)" {
  # Nested `body` inside an array element — wrapper must leave it alone.
  # The wrapper's strip regex is conservative; nested bodies could come
  # from passthrough payloads we don't want to silently rewrite.
  input=$(printf '{"items":[{"body":"nested-body-untouched"}]}' | _write_input_json)
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" api \
    -X POST repos/owner/repo/some-endpoint \
    --input "$input"

  [ "$status" -eq 0 ]
  [ -f "$GH_API_INPUT" ]
  grep -q "nested-body-untouched" "$GH_API_INPUT"
  ! grep -q "Written by an agent, not Fyodor" "$GH_API_INPUT"
}

@test "gh api --input leaves non-api subcommands untouched" {
  # `gh pr edit --input file.json` would be invalid gh CLI usage, but if
  # someone passes --input to a non-`api` subcommand the wrapper should
  # NOT try to filter it as JSON.
  input=$(printf '{"body":"unrelated"}' | _write_input_json)
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" pr edit 42 \
    --input "$input"

  # The wrapper passes through; the stub captures --input via its case
  # statement, but the filtering should NOT have happened.
  [ "$status" -eq 0 ]
  [ -f "$GH_API_INPUT" ]
  grep -q "unrelated" "$GH_API_INPUT"
  ! grep -q "Written by an agent, not Fyodor" "$GH_API_INPUT"
}
