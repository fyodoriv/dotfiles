#!/usr/bin/env bats
# slack-draft: attach, count, and delete Slack drafts. agent-tab is stubbed,
# so no browser and no Slack workspace is touched.

SCRIPT="$BATS_TEST_DIRNAME/../bin/slack-draft"

setup() {
  TEST_DIR="$(mktemp -d)"
  export CALLS="$TEST_DIR/calls.log"
  export FOUND='[]' DELETED=0
  cat > "$TEST_DIR/agent-tab" <<'STUB'
#!/bin/bash
echo "$*" >> "$CALLS"
case "$1" in
  eval)
    case "$5" in
      *"b.click"*) echo "$DELETED" ;;
      *) echo "$FOUND" ;;
    esac ;;
  open) echo T1 ;;
  upload) echo "agent-tab: uploaded" ;;
esac
STUB
  chmod +x "$TEST_DIR/agent-tab"
  export SLACK_DRAFT_AGENT_TAB="$TEST_DIR/agent-tab"
  export AGENT_TAB_OWNER=agent-a
  echo hi > "$TEST_DIR/report.pdf"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "attach uploads the file through agent-tab upload" {
  run "$SCRIPT" attach T1 "$TEST_DIR/report.pdf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"attached report.pdf"* ]]
  grep -q "^upload --owner agent-a --selector input\[type=file\] T1 $TEST_DIR/report.pdf" "$CALLS"
}

@test "attach rejects a missing file with exit 2 and never calls the browser" {
  run "$SCRIPT" attach T1 "$TEST_DIR/nope.pdf"
  [ "$status" -eq 2 ]
  [ ! -e "$CALLS" ]
}

@test "count prints the number of matching drafts" {
  FOUND='["to bob: hello","to bob: hello again"]' run "$SCRIPT" count T1 hello --to Bob
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "count prints 0 when nothing matches" {
  run "$SCRIPT" count T1 hello --to Bob
  [ "$output" = "0" ]
}

@test "count passes name and text to the page as JSON strings, not code" {
  run "$SCRIPT" count T1 'x"); alert(1);//' --to 'a"b'
  [ "$status" -eq 0 ]
  grep -qF 'x\"); alert(1);//' "$CALLS"
  grep -qF '"a\"b"' "$CALLS"
}

@test "count needs --to" {
  run "$SCRIPT" count T1 hello
  [ "$status" -eq 2 ]
}

@test "commands need an owner" {
  unset AGENT_TAB_OWNER
  run "$SCRIPT" count T1 hello --to Bob
  [ "$status" -eq 2 ]
}

@test "delete without --yes and without a terminal refuses with exit 4" {
  FOUND='["to bob: hello"]' run "$SCRIPT" delete T1 hello --to Bob < /dev/null
  [ "$status" -eq 4 ]
  [[ "$output" == *"--yes"* ]]
  ! grep -q 'b.click' "$CALLS"
}

@test "delete --yes removes the one match" {
  FOUND='["to bob: hello"]' DELETED=1 run "$SCRIPT" delete T1 hello --to Bob --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"deleted 1 draft(s) to Bob"* ]]
  grep -q 'b.click' "$CALLS"
}

@test "delete with several matches and no --all refuses with exit 4" {
  FOUND='["a","b"]' run "$SCRIPT" delete T1 hello --to Bob --yes
  [ "$status" -eq 4 ]
  ! grep -q 'b.click' "$CALLS"
}

@test "delete --all --yes removes every match" {
  FOUND='["a","b"]' DELETED=2 run "$SCRIPT" delete T1 hello --to Bob --all --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"deleted 2 draft(s)"* ]]
}

@test "delete with no match exits 1 and clicks nothing" {
  run "$SCRIPT" delete T1 hello --to Bob --yes
  [ "$status" -eq 1 ]
  ! grep -q 'b.click' "$CALLS"
}

@test "delete reports a short count when the page deletes fewer drafts" {
  FOUND='["a"]' DELETED=0 run "$SCRIPT" delete T1 hello --to Bob --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"deleted 0 of 1"* ]]
}

@test "open needs SLACK_DRAFT_URL and passes it to agent-tab open" {
  run "$SCRIPT" open
  [ "$status" -eq 2 ]
  SLACK_DRAFT_URL=https://slack.example.com/drafts run "$SCRIPT" open
  [ "$status" -eq 0 ]
  [ "$output" = "T1" ]
  grep -q 'open --owner agent-a --reason slack drafts https://slack.example.com/drafts' "$CALLS"
}

@test "no repo file holds a workspace URL default" {
  ! grep -E 'slack\.com/(client|archives)|app\.slack\.com' "$SCRIPT"
}

@test "unknown command exits 2" {
  run "$SCRIPT" frobnicate
  [ "$status" -eq 2 ]
}
