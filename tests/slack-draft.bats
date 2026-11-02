#!/usr/bin/env bats
# slack-draft: attach, count, and delete Slack drafts. agent-tab is stubbed,
# and the page scripts run against a fake DOM (fixtures/fake-slack-page.mjs),
# so no browser and no Slack workspace is touched.

SCRIPT="$BATS_TEST_DIRNAME/../bin/slack-draft"
PAGE="$BATS_TEST_DIRNAME/fixtures/fake-slack-page.mjs"

setup() {
  TEST_DIR="$(mktemp -d)"
  export CALLS="$TEST_DIR/calls.log"
  export DRAFTS_JSON="$TEST_DIR/drafts.json" INPUT_STATE="$TEST_DIR/input"
  export PAGE MARK="$TEST_DIR/injected" DELCOUNT="$TEST_DIR/delcount" PAGE_STATE="$TEST_DIR/page-state"
  echo drafts > "$PAGE_STATE"
  echo '[]' > "$DRAFTS_JSON"
  echo 1 > "$INPUT_STATE"
  cat > "$TEST_DIR/agent-tab" <<'STUB'
#!/bin/bash
echo "$*" >> "$CALLS"
case "$1" in
  eval) if [[ "$5" == *"  b.click();"* ]]; then
          dn=$(( $(cat "$DELCOUNT" 2>/dev/null || echo 0) + 1 )); echo "$dn" > "$DELCOUNT"
          if [ "${FAIL_ON_DELETE_CALL:-0}" = "$dn" ]; then echo "agent-tab: cdp Runtime.evaluate: no answer in 10 s" >&2; exit 1; fi
        fi
        out="$(node "$PAGE" "$5")"; echo "$out"
        if [[ "$5" == *"  b.click();"* ]] && [ "${INJECT_AFTER_DELETE:-0}" = "$(cat "$DELCOUNT")" ]; then
          jq '[{to:"Bob",body:"hello NEW unseen"}] + .' "$DRAFTS_JSON" > "$DRAFTS_JSON.n"; mv "$DRAFTS_JSON.n" "$DRAFTS_JSON"
        fi
        # INJECT: change the list right after the first read (what the user confirmed)
        if [ -n "${INJECT:-}" ] && [ ! -e "$MARK" ] && [[ "$5" == *"JSON.stringify(hits().map"* ]]; then
          touch "$MARK"
          case "$INJECT" in
            prepend) jq '[{to:"Bob",body:"hello NEW unseen"}] + .' "$DRAFTS_JSON" > "$DRAFTS_JSON.n" ;;
            replace) jq 'map(.body = "hello NEW unseen")' "$DRAFTS_JSON" > "$DRAFTS_JSON.n" ;;
          esac
          mv "$DRAFTS_JSON.n" "$DRAFTS_JSON"
        fi ;;
  nav) echo drafts > "$PAGE_STATE"; echo navigated ;;
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

drafts() { echo "$1" > "$DRAFTS_JSON"; }
left() { jq -r '[.[].to] | join(",")' "$DRAFTS_JSON"; }

# --- attach ---

@test "attach uploads to the main composer's file input" {
  run "$SCRIPT" attach T1 "$TEST_DIR/report.pdf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"attached report.pdf"* ]]
  grep -q "^upload --owner agent-a --selector .*primary_view.* input\[type=file\] T1 $TEST_DIR/report.pdf" "$CALLS"
}

@test "attach clicks the attach button when the input is not there yet" {
  echo 0 > "$INPUT_STATE"
  FAKE_INPUT_AFTER_CLICK=1 run "$SCRIPT" attach T1 "$TEST_DIR/report.pdf"
  [ "$status" -eq 0 ]
  grep -q '^upload ' "$CALLS"
}

@test "attach fails without uploading when the composer has no file input" {
  echo 0 > "$INPUT_STATE"
  run "$SCRIPT" attach T1 "$TEST_DIR/report.pdf"
  [ "$status" -eq 1 ]
  ! grep -q '^upload ' "$CALLS"
}

@test "attach rejects a missing file with exit 2 and never calls the browser" {
  run "$SCRIPT" attach T1 "$TEST_DIR/nope.pdf"
  [ "$status" -eq 2 ]
  [ ! -e "$CALLS" ]
}

# --- count ---

@test "count matches the recipient exactly, not as a substring" {
  drafts '[{"to":"Alexandra","body":"hello"},{"to":"Carol","body":"tell Al hello"},{"to":"Al","body":"hello there"}]'
  run "$SCRIPT" count T1 hello --to Al
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "count ignores case, spacing, and a leading @ in the recipient" {
  drafts '[{"to":"@Alex  Kim","body":"Hello"}]'
  run "$SCRIPT" count T1 hello --to "alex kim"
  [ "$output" = "1" ]
}

@test "count matches the text against the body, not the recipient" {
  drafts '[{"to":"Hello Kitty","body":"bye"}]'
  run "$SCRIPT" count T1 hello --to "Hello Kitty"
  [ "$output" = "0" ]
}

@test "count matches non-ASCII names in any case" {
  drafts '[{"to":"Фёдор","body":"привет"},{"to":"Ålex","body":"hej"}]'
  run "$SCRIPT" count T1 привет --to "фЁдор"
  [ "$output" = "1" ]
  run "$SCRIPT" count T1 HEJ --to "ÅLEX"
  [ "$output" = "1" ]
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

# --- delete ---

@test "delete --to Al never removes Alexandra's draft or a draft that only mentions Al" {
  drafts '[{"to":"Alexandra","body":"hello"},{"to":"Carol","body":"tell Al hello"},{"to":"Al","body":"hello there"}]'
  run "$SCRIPT" delete T1 hello --to Al --yes
  [ "$status" -eq 0 ]
  [ "$(left)" = "Alexandra,Carol" ]
}

@test "delete shows the matched rows before it asks, and refuses without a terminal" {
  drafts '[{"to":"Bob","body":"hello there"}]'
  run "$SCRIPT" delete T1 hello --to Bob < /dev/null
  [ "$status" -eq 4 ]
  [[ "$output" == *"Bob"*"hello there"* ]]
  [[ "$output" == *"--yes"* ]]
  [ "$(left)" = "Bob" ]
}

@test "delete --yes removes the one match and reports the real count" {
  drafts '[{"to":"Bob","body":"hello"},{"to":"Eve","body":"hello"}]'
  run "$SCRIPT" delete T1 hello --to Bob --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"deleted 1 draft(s) to Bob"* ]]
  [ "$(left)" = "Eve" ]
}

@test "delete with several matches and no --all refuses with exit 4" {
  drafts '[{"to":"Bob","body":"hello 1"},{"to":"Bob","body":"hello 2"}]'
  run "$SCRIPT" delete T1 hello --to Bob --yes
  [ "$status" -eq 4 ]
  [ "$(left)" = "Bob,Bob" ]
}

@test "delete --all --yes removes every match and re-reads the list after each delete" {
  drafts '[{"to":"Bob","body":"hello 1"},{"to":"Eve","body":"hello"},{"to":"Bob","body":"hello 2"}]'
  run "$SCRIPT" delete T1 hello --to Bob --all --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"deleted 2 draft(s)"* ]]
  [ "$(left)" = "Eve" ]
}

@test "delete answers a Slack confirm dialog" {
  drafts '[{"to":"Bob","body":"hello"}]'
  FAKE_CONFIRM=1 run "$SCRIPT" delete T1 hello --to Bob --yes
  [ "$status" -eq 0 ]
  [ "$(left)" = "" ]
}

@test "delete reports unknown, exit 1, never a false 'deleted 0', when the list does not change" {
  drafts '[{"to":"Bob","body":"hello"}]'
  FAKE_NO_DELETE_BUTTON=1 run "$SCRIPT" delete T1 hello --to Bob --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown"* ]]
  [[ "$output" != *"deleted 0"* ]]
}

@test "delete deletes only the rows the user was shown: a new draft landing after the read aborts" {
  drafts '[{"to":"Bob","body":"hello old"}]'
  INJECT=prepend run "$SCRIPT" delete T1 hello --to Bob --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"changed"* ]]
  [ "$(jq length "$DRAFTS_JSON")" -eq 2 ]
}

@test "delete aborts when the confirmed row is replaced by a different one" {
  drafts '[{"to":"Bob","body":"hello old"}]'
  INJECT=replace run "$SCRIPT" delete T1 hello --to Bob --yes
  [ "$status" -eq 1 ]
  [ "$(jq -r '.[0].body' "$DRAFTS_JSON")" = "hello NEW unseen" ]
}

@test "delete --all aborts with nothing deleted when a new match lands after the read" {
  drafts '[{"to":"Bob","body":"hello 1"},{"to":"Bob","body":"hello 2"}]'
  INJECT=prepend run "$SCRIPT" delete T1 hello --to Bob --all --yes
  [ "$status" -eq 1 ]
  [ "$(jq length "$DRAFTS_JSON")" -eq 3 ]
}

@test "agent-tab failing on the 3rd delete of --all prints the count and exits 1" {
  drafts '[{"to":"Bob","body":"hello 1"},{"to":"Bob","body":"hello 2"},{"to":"Bob","body":"hello 3"}]'
  FAIL_ON_DELETE_CALL=3 run "$SCRIPT" delete T1 hello --to Bob --all --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown: 2 confirmed deleted, then agent-tab failed"* ]]
  [ "$(jq length "$DRAFTS_JSON")" -eq 1 ]
}

@test "rows hiding while the delete dialog stays open is unknown, not removed" {
  drafts '[{"to":"Bob","body":"hello"}]'
  FAKE_STUCK_MODAL=1 run "$SCRIPT" delete T1 hello --to Bob --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown"* ]]
  [[ "$output" != *"deleted 1"* ]]
}

@test "a Delete dialog that was already open before the click is never answered" {
  drafts '[{"to":"Bob","body":"hello"}]'
  export DECOY_HIT="$TEST_DIR/decoy"
  FAKE_CONFIRM=1 FAKE_OLD_DELETE_DIALOG=1 run "$SCRIPT" delete T1 hello --to Bob --yes
  [ "$status" -eq 0 ]
  [ ! -e "$DECOY_HIT" ]
  [ "$(left)" = "" ]
}

@test "duplicate drafts: --all deletes both Bob drafts and keeps Eve's" {
  drafts '[{"to":"Bob","body":"hello"},{"to":"Bob","body":"hello"},{"to":"Eve","body":"hello"}]'
  run "$SCRIPT" delete T1 hello --to Bob --all --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"deleted 2 draft(s)"* ]]
  [ "$(left)" = "Eve" ]
}

@test "a new match after the first delete stops --all and reports how many went" {
  drafts '[{"to":"Bob","body":"hello 1"},{"to":"Bob","body":"hello 2"},{"to":"Bob","body":"hello 3"}]'
  INJECT_AFTER_DELETE=1 run "$SCRIPT" delete T1 hello --to Bob --all --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"changed"*"1 deleted"* ]]
  [ "$(jq length "$DRAFTS_JSON")" -eq 3 ]
}

@test "empty or blank text is refused with exit 2 and deletes nothing" {
  drafts '[{"to":"Bob","body":"hello"}]'
  for t in "" "   "; do
    run "$SCRIPT" delete T1 "$t" --to Bob --yes
    [ "$status" -eq 2 ]
    run "$SCRIPT" count T1 "$t" --to Bob
    [ "$status" -eq 2 ]
  done
  [ "$(jq length "$DRAFTS_JSON")" -eq 1 ]
}

@test "--all does one delete per eval call, so no call outlasts the eval timeout" {
  drafts '[{"to":"Bob","body":"hello 1"},{"to":"Bob","body":"hello 2"},{"to":"Bob","body":"hello 3"}]'
  run "$SCRIPT" delete T1 hello --to Bob --all --yes
  [ "$status" -eq 0 ]
  [ "$(grep -c '^  b.click();' "$CALLS")" -eq 3 ]
}

@test "full-width and math-bold names do not merge with plain ones" {
  drafts '[{"to":"Ａｌ","body":"hello"},{"to":"𝐀𝐥","body":"hello"},{"to":"Al","body":"hello"}]'
  run "$SCRIPT" count T1 hello --to Al
  [ "$output" = "1" ]
}

@test "the confirm click goes to the delete dialog, not another modal" {
  drafts '[{"to":"Bob","body":"hello"}]'
  export DECOY_HIT="$TEST_DIR/decoy"
  FAKE_CONFIRM=1 FAKE_DECOY=1 run "$SCRIPT" delete T1 hello --to Bob --yes
  [ "$status" -eq 0 ]
  [ ! -e "$DECOY_HIT" ]
  [ "$(left)" = "" ]
}

@test "delete with no match exits 1" {
  run "$SCRIPT" delete T1 hello --to Bob --yes
  [ "$status" -eq 1 ]
}

# --- the rest ---

@test "open needs SLACK_DRAFT_URL and passes it to agent-tab open" {
  run "$SCRIPT" open
  [ "$status" -eq 2 ]
  SLACK_DRAFT_URL=https://slack.example.com/drafts run "$SCRIPT" open
  [ "$status" -eq 0 ]
  [ "$output" = "T1" ]
  grep -q 'open --owner agent-a --reason slack drafts https://slack.example.com/drafts' "$CALLS"
}

@test "no repo file holds a workspace URL default" {
  ! workspace_url_default "$SCRIPT"
}

@test "unknown command exits 2" {
  run "$SCRIPT" frobnicate
  [ "$status" -eq 2 ]
}

@test "count navigates a channel tab to Drafts before reading matches" {
  echo channel > "$PAGE_STATE"
  drafts '[{"to":"Bob","body":"hello"}]'
  run "$SCRIPT" count T1 hello --to Bob
  [ "$status" -eq 0 ]
  [ "$output" = 1 ]
  grep -q '^nav --owner agent-a T1 https://app.slack.com/client/TFIXTURE/drafts' "$CALLS"
}

@test "delete navigates to Drafts then confirms the scoped Delete button" {
  echo channel > "$PAGE_STATE"
  drafts '[{"to":"Bob","body":"hello"},{"to":"Eve","body":"hello"}]'
  FAKE_CONFIRM=1 FAKE_CONFIRM_VARIANT=button run "$SCRIPT" delete T1 hello --to Bob --yes
  [ "$status" -eq 0 ]
  [ "$(left)" = Eve ]
}

@test "a Drafts readiness timeout fails without deleting a row" {
  drafts '[{"to":"Bob","body":"hello"}]'
  FAKE_DRAFTS_NEVER_READY=1 SLACK_DRAFT_TIMEOUT_SECONDS=0 run "$SCRIPT" delete T1 hello --to Bob --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"Drafts"*"limit"* ]]
  [ "$(left)" = Bob ]
  [ ! -e "$DELCOUNT" ]
}

@test "Drafts navigation refuses a tab outside Slack" {
  FAKE_SLACK_URL=https://example.com/client/TFIXTURE/channel run "$SCRIPT" count T1 hello --to Bob
  [ "$status" -eq 1 ]
  ! grep -q '^nav ' "$CALLS"
}

@test "a stalled Drafts view stays within the command deadline" {
  drafts '[{"to":"Bob","body":"hello"}]'
  SECONDS=0
  FAKE_DRAFTS_NEVER_READY=1 SLACK_DRAFT_TIMEOUT_SECONDS=1 run "$SCRIPT" count T1 hello --to Bob
  [ "$status" -eq 1 ]
  [ "$SECONDS" -lt 5 ]
  [[ "$output" == *"30-second limit"* ]]
  [ "$(left)" = Bob ]
}

workspace_url_default() {
  grep -E 'https?://[^[:space:]"<>]*slack\.com/(client|archives)/|SLACK_DRAFT_URL[=:].*(https?://|slack\.com)' "$1"
}

@test "workspace URL guard rejects a planted default while allowing the public host pin" {
  cp "$SCRIPT" "$TEST_DIR/planted"
  printf '\nSLACK_DRAFT_URL=https://app.slack.com/client/TFIXTURE/drafts\n' >> "$TEST_DIR/planted"
  run workspace_url_default "$TEST_DIR/planted"
  [ "$status" -eq 0 ]
  run workspace_url_default "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "the deployed individual command symlink finds its repository tools" {
  mkdir -p "$TEST_DIR/home/.local/bin"
  ln -s "$SCRIPT" "$TEST_DIR/home/.local/bin/slack-draft"
  drafts '[{"to":"Bob","body":"hello"}]'
  run "$TEST_DIR/home/.local/bin/slack-draft" count T1 hello --to Bob
  [ "$status" -eq 0 ]
  [ "$output" = 1 ]
}

@test "a browser process that ignores TERM cannot overrun the deadline" {
  cat > "$TEST_DIR/stalled-tab" <<'STUB'
#!/usr/bin/env perl
$SIG{TERM} = "IGNORE";
sleep 4;
STUB
  chmod +x "$TEST_DIR/stalled-tab"
  SECONDS=0
  SLACK_DRAFT_AGENT_TAB="$TEST_DIR/stalled-tab" SLACK_DRAFT_TIMEOUT_SECONDS=1 run "$SCRIPT" count T1 hello --to Bob
  [ "$status" -eq 1 ]
  [ "$SECONDS" -lt 3 ]
  [[ "$output" == *"30-second limit"* ]]
}

@test "deadline cleanup also kills a child delayed before process-group setup" {
  export SLACK_TEST_REAL_PERL="$(command -v perl)"
  mkdir -p "$TEST_DIR/delayed-perl"
  cat > "$TEST_DIR/delayed-perl/perl" <<'STUB'
#!/bin/bash
if [ "$1" = -e ] && [[ "$2" == *'setpgrp(0, 0)'* ]]; then
  program="${2/setpgrp(0, 0)/sleep 4; setpgrp(0, 0)}"
  shift 2
  exec "$SLACK_TEST_REAL_PERL" -e "$program" "$@"
fi
exec "$SLACK_TEST_REAL_PERL" "$@"
STUB
  chmod +x "$TEST_DIR/delayed-perl/perl"
  SECONDS=0
  PATH="$TEST_DIR/delayed-perl:$PATH" SLACK_DRAFT_TIMEOUT_SECONDS=1 run "$SCRIPT" count T1 hello --to Bob
  [ "$status" -eq 1 ]
  [ "$SECONDS" -lt 3 ]
  [[ "$output" == *"30-second limit"* ]]
}
