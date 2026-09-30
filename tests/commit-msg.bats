#!/usr/bin/env bats
# Tests for commit-msg hook — conventional commits enforcement

load test_helper

HOOK="$BATS_TEST_DIRNAME/../git-hooks/commit-msg"

setup() {
  TEST_DIR="$(mktemp -d)"
  MSG_FILE="$TEST_DIR/COMMIT_EDITMSG"
  # Clear orchestrator pipeline env vars so tests run in a clean non-pipeline
  # context unless they explicitly set MINSKY_PIPELINE=1.
  unset MINSKY_PIPELINE
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Helper: write message to file and run hook
run_hook() {
  echo "$1" > "$MSG_FILE"
  run "$HOOK" "$MSG_FILE"
}

# ── Valid conventional commits ────────────────────────────────────

@test "commit-msg accepts feat: message" {
  run_hook "feat: add login flow"
  [ "$status" -eq 0 ]
}

@test "commit-msg accepts fix: message" {
  run_hook "fix: resolve crash on startup"
  [ "$status" -eq 0 ]
}

@test "commit-msg accepts docs: message" {
  run_hook "docs: update README"
  [ "$status" -eq 0 ]
}

@test "commit-msg accepts chore: message" {
  run_hook "chore: bump dependencies"
  [ "$status" -eq 0 ]
}

@test "commit-msg accepts test: message" {
  run_hook "test: add unit tests for auth module"
  [ "$status" -eq 0 ]
}

@test "commit-msg accepts refactor: message" {
  run_hook "refactor: extract helper function"
  [ "$status" -eq 0 ]
}

@test "commit-msg accepts type with scope" {
  run_hook "feat(auth): add login flow"
  [ "$status" -eq 0 ]
}

@test "commit-msg accepts all valid types" {
  for type in feat fix docs style refactor perf test build ci chore revert; do
    echo "$type: valid message" > "$MSG_FILE"
    run "$HOOK" "$MSG_FILE"
    [ "$status" -eq 0 ]
  done
}

# ── Invalid messages ─────────────────────────────────────────────

@test "commit-msg rejects message without type prefix" {
  run_hook "add login flow"
  [ "$status" -ne 0 ]
  [[ "$output" == *"conventional commits"* ]]
}

@test "commit-msg rejects unknown type" {
  run_hook "feature: add login flow"
  [ "$status" -ne 0 ]
}

@test "commit-msg rejects missing colon" {
  run_hook "feat add login flow"
  [ "$status" -ne 0 ]
}

@test "commit-msg rejects missing description after colon" {
  run_hook "feat: "
  [ "$status" -ne 0 ]
}

@test "commit-msg rejects capitalized type" {
  run_hook "Feat: add login flow"
  [ "$status" -ne 0 ]
}

# ── Header length enforcement ────────────────────────────────────

@test "commit-msg accepts message at 72 chars" {
  # "feat: " is 6 chars, need 66 more chars of description = 72 total
  msg="feat: $(printf 'x%.0s' {1..66})"
  [ ${#msg} -eq 72 ]
  run_hook "$msg"
  [ "$status" -eq 0 ]
}

@test "commit-msg rejects message over 72 chars" {
  # "feat: " is 6 chars, 68 more = 74 total (over limit)
  msg="feat: $(printf 'x%.0s' {1..68})"
  [ ${#msg} -gt 72 ]
  run_hook "$msg"
  [ "$status" -ne 0 ]
  [[ "$output" == *"72 characters"* ]]
}

# ── Skip logic (merge, fixup, auto-generated) ────────────────────

@test "commit-msg skips merge commits" {
  run_hook "Merge branch 'feature' into main"
  [ "$status" -eq 0 ]
}

@test "commit-msg skips fixup commits" {
  run_hook "fixup! feat: original message"
  [ "$status" -eq 0 ]
}

@test "commit-msg skips squash commits" {
  run_hook "squash! feat: original message"
  [ "$status" -eq 0 ]
}

@test "commit-msg skips amend commits" {
  run_hook "amend! feat: original message"
  [ "$status" -eq 0 ]
}

@test "commit-msg skips Revert commits" {
  run_hook "Revert \"feat: something\""
  [ "$status" -eq 0 ]
}

@test "commit-msg skips sync: auto-generated commits" {
  run_hook "sync: auto-update 2024-01-01"
  [ "$status" -eq 0 ]
}

@test "commit-msg skips wip commits" {
  run_hook "wip"
  [ "$status" -eq 0 ]
}

# ── Error output quality ─────────────────────────────────────────

@test "commit-msg error shows the rejected message" {
  run_hook "bad commit message"
  [ "$status" -ne 0 ]
  [[ "$output" == *"bad commit message"* ]]
}

@test "commit-msg error shows valid types" {
  run_hook "bad commit message"
  [ "$status" -ne 0 ]
  [[ "$output" == *"feat"* ]]
  [[ "$output" == *"fix"* ]]
}

# ── Strip tool-specific Co-Authored-By trailers ───────────────────

# Helper: write a multi-line message to the file and run the hook.
# Cannot use run_hook because it uses echo which collapses newlines.
write_msg() {
  printf '%s' "$1" > "$MSG_FILE"
}

@test "commit-msg strips Co-Authored-By Devin trailer by name" {
  write_msg "feat: add feature

Some details here.

Co-Authored-By: Devin <158243242+devin-ai-integration[bot]@users.noreply.github.com>
"
  run "$HOOK" "$MSG_FILE"
  [ "$status" -eq 0 ]
  run grep -c "Co-Authored-By: Devin" "$MSG_FILE"
  [ "$output" = "0" ]
}

@test "commit-msg strips Co-Authored-By Claude trailer by name" {
  write_msg "feat: add feature

Co-Authored-By: Claude <noreply@anthropic.com>
"
  run "$HOOK" "$MSG_FILE"
  [ "$status" -eq 0 ]
  run grep -c "Co-Authored-By: Claude" "$MSG_FILE"
  [ "$output" = "0" ]
}

@test "commit-msg strips Co-Authored-By by devin-ai-integration email" {
  # Agents sometimes use a display name like 'devin-ai-integration[bot]' —
  # match on email pattern too so name variations don't slip through.
  write_msg "feat: add feature

Co-Authored-By: devin-ai-integration[bot] <158243242+devin-ai-integration[bot]@users.noreply.github.com>
"
  run "$HOOK" "$MSG_FILE"
  [ "$status" -eq 0 ]
  run grep -c "devin-ai-integration" "$MSG_FILE"
  [ "$output" = "0" ]
}

@test "commit-msg strips multiple agent trailers in one commit" {
  write_msg "feat: add feature

Co-Authored-By: Devin <158243242+devin-ai-integration[bot]@users.noreply.github.com>
Co-Authored-By: Claude <noreply@anthropic.com>
"
  run "$HOOK" "$MSG_FILE"
  [ "$status" -eq 0 ]
  run grep -cE "Co-Authored-By: (Devin|Claude)" "$MSG_FILE"
  [ "$output" = "0" ]
}

@test "commit-msg preserves human Co-Authored-By trailers" {
  # Real human co-authors must pass through unchanged.
  write_msg "feat: add feature

Co-Authored-By: Alice Smith <alice@example.com>
Co-Authored-By: Bob Jones <bob@company.com>
"
  run "$HOOK" "$MSG_FILE"
  [ "$status" -eq 0 ]
  run grep -c "Co-Authored-By: Alice Smith" "$MSG_FILE"
  [ "$output" = "1" ]
  run grep -c "Co-Authored-By: Bob Jones" "$MSG_FILE"
  [ "$output" = "1" ]
}

@test "commit-msg preserves human trailers when agent trailers are also present" {
  write_msg "feat: add feature

Co-Authored-By: Alice Smith <alice@example.com>
Co-Authored-By: Devin <158242+devin-ai-integration[bot]@users.noreply.github.com>
"
  run "$HOOK" "$MSG_FILE"
  [ "$status" -eq 0 ]
  run grep -c "Co-Authored-By: Alice Smith" "$MSG_FILE"
  [ "$output" = "1" ]
  run grep -c "Co-Authored-By: Devin" "$MSG_FILE"
  [ "$output" = "0" ]
}

@test "commit-msg leaves foreign trailer untouched when MINSKY_PIPELINE is set" {
  # Orchestrator pipelines (minsky) bypass the rewrite entirely so the
  # orchestrator stays in control of attribution.
  write_msg "feat: add feature

Co-Authored-By: Devin <158242+devin-ai-integration[bot]@users.noreply.github.com>
"
  MINSKY_PIPELINE=1 run "$HOOK" "$MSG_FILE"
  [ "$status" -eq 0 ]
  run grep -c "Co-Authored-By: Devin" "$MSG_FILE"
  [ "$output" = "1" ]
}

@test "commit-msg warns when stripping an agent trailer" {
  write_msg "feat: add feature

Co-Authored-By: Devin <158242+devin-ai-integration[bot]@users.noreply.github.com>
"
  run "$HOOK" "$MSG_FILE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"attribution"* ]]
  [[ "$output" == *"MINSKY_PIPELINE"* ]]
}

@test "commit-msg strips Cursor and Windsurf and Copilot agent trailers" {
  write_msg "feat: add feature

Co-Authored-By: Cursor <agent@cursor.com>
Co-Authored-By: Windsurf <agent@windsurf.com>
Co-Authored-By: GitHub Copilot <copilot@github.com>
"
  run "$HOOK" "$MSG_FILE"
  [ "$status" -eq 0 ]
  run grep -c "Co-Authored-By:" "$MSG_FILE"
  [ "$output" = "0" ]
}

@test "commit-msg does not add a Co-Authored-By line for commits without one" {
  # Negative test: passing through a plain commit must not introduce any trailers.
  write_msg "feat: a clean commit with no trailers
"
  run "$HOOK" "$MSG_FILE"
  [ "$status" -eq 0 ]
  run grep -c "Co-Authored-By" "$MSG_FILE"
  [ "$output" = "0" ]
}

# ── Strip "Generated with [<AgentName>]" footer lines ─────────────

@test "commit-msg strips 'Generated with [Devin]' footer line" {
  write_msg "feat: add feature

Some details here.

Generated with [Devin](https://cli.devin.ai/docs)
"
  run "$HOOK" "$MSG_FILE"
  [ "$status" -eq 0 ]
  run grep -c "Generated with \[Devin\]" "$MSG_FILE"
  [ "$output" = "0" ]
  run grep -c "cli.devin.ai" "$MSG_FILE"
  [ "$output" = "0" ]
}

@test "commit-msg strips 'Generated with [Claude Code]' footer line" {
  write_msg "feat: add feature

Generated with [Claude Code](https://claude.com/code)
"
  run "$HOOK" "$MSG_FILE"
  [ "$status" -eq 0 ]
  run grep -c "Generated with \[Claude" "$MSG_FILE"
  [ "$output" = "0" ]
}

@test "commit-msg strips 'Generated by [Devin]' alternate wording" {
  write_msg "feat: add feature

Generated by [Devin](https://app.devin.ai/sessions/abc)
"
  run "$HOOK" "$MSG_FILE"
  [ "$status" -eq 0 ]
  run grep -c "Generated by \[Devin\]" "$MSG_FILE"
  [ "$output" = "0" ]
}

@test "commit-msg preserves 'Generated with [Devin]' when MINSKY_PIPELINE is set" {
  # Pure-bypass mode: the library leaves the message exactly as written.
  write_msg "feat: add feature

Generated with [Devin](https://cli.devin.ai/docs)
"
  MINSKY_PIPELINE=1 run "$HOOK" "$MSG_FILE"
  [ "$status" -eq 0 ]
  run grep -c "Generated with \[Devin\]" "$MSG_FILE"
  [ "$output" = "1" ]
}

@test "commit-msg strips both Co-Authored-By and Generated-with in one commit" {
  write_msg "feat: add feature

Generated with [Devin](https://cli.devin.ai/docs)

Co-Authored-By: Devin <158242+devin-ai-integration[bot]@users.noreply.github.com>
"
  run "$HOOK" "$MSG_FILE"
  [ "$status" -eq 0 ]
  run grep -cE "Generated with \[Devin\]|Co-Authored-By: Devin" "$MSG_FILE"
  [ "$output" = "0" ]
}

@test "commit-msg preserves prose that mentions Devin without the footer format" {
  # The hook must only strip literal footer/trailer formats, not prose.
  # A commit discussing Devin as a subject should pass through unchanged.
  write_msg "feat: refactor Devin integration module

Moves the Devin backend logic from backend/devinCliBackend.ts to
backend/devin/. Updates tests that imported the old path.
"
  run "$HOOK" "$MSG_FILE"
  [ "$status" -eq 0 ]
  run grep -c "Devin" "$MSG_FILE"
  # Two mentions in the prose should survive — one in subject, one in body.
  [ "$output" = "2" ]
}

# ── MINSKY_PIPELINE pure-bypass mode ────────────────────────────────
#
# Orchestrator pipelines (minsky etc.) bypass attribution rewriting
# entirely. The library does NOT inject any orchestrator-specific
# trailer — minsky deliberately has no bot identity (see minsky
# user-story 012: "no new bot account"). The operator's commit message
# survives byte-for-byte; the orchestrator can add whatever attribution
# it wants from its own pipeline driver.

@test "commit-msg does not inject any orchestrator trailer when MINSKY_PIPELINE=1" {
  write_msg "feat: add feature JIRA-123
"
  MINSKY_PIPELINE=1 run "$HOOK" "$MSG_FILE"
  [ "$status" -eq 0 ]
  # No tool-named trailer is added by the library in pipeline mode.
  run grep -c "Co-Authored-By:" "$MSG_FILE"
  [ "$output" = "0" ]
  run grep -c "Generated by" "$MSG_FILE"
  [ "$output" = "0" ]
}

@test "commit-msg preserves foreign Co-Authored-By trailers when MINSKY_PIPELINE=1" {
  # When the orchestrator already wrote a Co-Authored-By trailer, the library
  # leaves it alone so the orchestrator's attribution choices win.
  write_msg "feat: add feature JIRA-123

Co-Authored-By: Claude <noreply@anthropic.com>
"
  MINSKY_PIPELINE=1 run "$HOOK" "$MSG_FILE"
  [ "$status" -eq 0 ]
  run grep -c "Co-Authored-By: Claude" "$MSG_FILE"
  [ "$output" = "1" ]
}

@test "commit-msg delegates to executable repo-local hooks/commit-msg" {
  local repo="$TEST_DIR/repo"
  git init --quiet "$repo"
  mkdir -p "$repo/hooks"
  cat > "$repo/hooks/commit-msg" <<'SCRIPT'
#!/bin/bash
echo "repo-local commit-msg ran" >&2
exit 43
SCRIPT
  chmod +x "$repo/hooks/commit-msg"
  write_msg "feat: add feature"

  run bash -c 'cd "$1" && "$2" "$3"' _ "$repo" "$HOOK" "$MSG_FILE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"repo-local commit-msg ran"* ]]
}
