#!/usr/bin/env bats
# agent-tab: owner, reason, and lease per tab of the shared agents Chrome.
# curl is stubbed on PATH, so no real Chrome is needed.

SCRIPT="$BATS_TEST_DIRNAME/../bin/agent-tab"

setup() {
  TEST_DIR="$(mktemp -d)"
  export AGENT_TAB_STATE_DIR="$TEST_DIR/state"
  export CDP_LOG="$TEST_DIR/cdp.log"
  mkdir -p "$TEST_DIR/bin"
  cat > "$TEST_DIR/bin/curl" <<'STUB'
#!/bin/bash
url="${*: -1}"
echo "$*" >> "$CDP_LOG"
case "$url" in
  */json/new*) n=$(( $(wc -l < "$CDP_LOG") )); printf '{"id":"T%s","url":"x","type":"page"}\n' "$n" ;;
  */json/close/*) echo "Target is closing" ;;
  */json/list*) echo '[]' ;;
  *) exit 7 ;;
esac
STUB
  chmod +x "$TEST_DIR/bin/curl"
  export PATH="$TEST_DIR/bin:$PATH"
}

teardown() { rm -rf "$TEST_DIR"; }

open_tab() { "$SCRIPT" open --owner "$1" --reason "$2" https://example.com; }

@test "open records owner, reason, lease, and prints the tab id" {
  run open_tab agent-a "sign-in check"
  [ "$status" -eq 0 ]
  id="$output"
  [ -n "$id" ]
  grep -q '/json/new?https://example.com' "$CDP_LOG"
  grep -q -- '-X PUT' "$CDP_LOG"
  run "$SCRIPT" list
  [[ "$output" == *"$id"*"agent-a"*"sign-in check"* ]]
  jq -e --arg id "$id" '.[$id].owner == "agent-a" and .[$id].expires > now' "$AGENT_TAB_STATE_DIR/tabs.json"
}

@test "open requires owner and reason" {
  run "$SCRIPT" open --owner a https://example.com
  [ "$status" -eq 2 ]
  run "$SCRIPT" open --reason r https://example.com
  [ "$status" -eq 2 ]
}

@test "owner can close its own tab" {
  id="$(open_tab agent-a r)"
  run "$SCRIPT" close --owner agent-a "$id"
  [ "$status" -eq 0 ]
  grep -q "/json/close/$id" "$CDP_LOG"
  jq -e --arg id "$id" 'has($id) | not' "$AGENT_TAB_STATE_DIR/tabs.json"
}

@test "closing another owner's live tab exits 3 with holder and reason" {
  id="$(open_tab agent-a "bot login")"
  run "$SCRIPT" close --owner agent-b "$id"
  [ "$status" -eq 3 ]
  [[ "$output" == *"agent-a"* ]]
  [[ "$output" == *"bot login"* ]]
  ! grep -q "/json/close/" "$CDP_LOG"
}

@test "anyone can close a tab whose lease expired" {
  id="$(open_tab agent-a r)"
  tmp="$(mktemp)"; jq --arg id "$id" '.[$id].expires = 1' "$AGENT_TAB_STATE_DIR/tabs.json" > "$tmp"
  mv "$tmp" "$AGENT_TAB_STATE_DIR/tabs.json"
  run "$SCRIPT" list
  [[ "$output" == *"expired"* ]]
  run "$SCRIPT" close --owner agent-b "$id"
  [ "$status" -eq 0 ]
  grep -q "/json/close/$id" "$CDP_LOG"
}

@test "renew extends the lease for the owner only" {
  id="$(AGENT_TAB_LEASE_SECONDS=5 "$SCRIPT" open --owner agent-a --reason r https://example.com)"
  before="$(jq -r --arg id "$id" '.[$id].expires' "$AGENT_TAB_STATE_DIR/tabs.json")"
  run "$SCRIPT" renew --owner agent-a --lease 600 "$id"
  [ "$status" -eq 0 ]
  after="$(jq -r --arg id "$id" '.[$id].expires' "$AGENT_TAB_STATE_DIR/tabs.json")"
  [ "$after" -gt "$before" ]
  run "$SCRIPT" renew --owner agent-b "$id"
  [ "$status" -eq 3 ]
}

@test "--lease sets the lease seconds on open" {
  id="$("$SCRIPT" open --owner a --reason r --lease 30 https://example.com)"
  exp="$(jq -r --arg id "$id" '.[$id].expires' "$AGENT_TAB_STATE_DIR/tabs.json")"
  [ "$exp" -le $(( $(date +%s) + 31 )) ]
}

@test "close of an untracked tab fails without touching Chrome" {
  run "$SCRIPT" close --owner a NOPE
  [ "$status" -eq 1 ]
  [ ! -s "$CDP_LOG" ]
}

@test "busy exit code 3 is in the usage text" {
  run "$SCRIPT" --help
  [[ "$output" == *"Exit 3"* ]]
}

@test "state writes are atomic (temp file + mv)" {
  grep -q 'mv ' "$SCRIPT"
  open_tab a r >/dev/null
  [ -z "$(find "$AGENT_TAB_STATE_DIR" -name '*.tmp*')" ]
}

@test "agent-tab never raises windows" {
  ! grep -qE 'osascript|activate|/json/activate|open -a' "$SCRIPT"
}
