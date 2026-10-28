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

# --- page commands, health, clear-cookies (#221) ---
# The CDP client is stubbed through AGENT_TAB_CDP. It logs "<ws> <method> <params>"
# and answers from canned JSON. /json/list comes from $TABS_JSON.

cdp_setup() {
  export TABS_JSON="$TEST_DIR/tabs-list.json"
  echo '[]' > "$TABS_JSON"
  cat > "$TEST_DIR/bin/curl" <<'STUB'
#!/bin/bash
url="${*: -1}"
echo "$*" >> "$CDP_LOG"
case "$url" in
  */json/new*) n=$(( $(wc -l < "$CDP_LOG") )); printf '{"id":"T%s","url":"x","type":"page"}\n' "$n" ;;
  */json/close/*) echo "Target is closing" ;;
  */json/list*) cat "$TABS_JSON" ;;
  */json/version*) echo '{"webSocketDebuggerUrl":"ws://b/browser"}' ;;
  *) exit 7 ;;
esac
STUB
  chmod +x "$TEST_DIR/bin/curl"
  export CDP_CALLS="$TEST_DIR/cdp-calls.log"
  cat > "$TEST_DIR/cdp" <<'STUB'
#!/bin/bash
echo "$1 $2 $3" >> "$CDP_CALLS"
case "$1" in *dead*) exit 1 ;; esac
case "$2" in
  Runtime.evaluate) echo '{"result":{"type":"string","value":"hello page"}}' ;;
  Page.captureScreenshot) echo '{"data":"aGk="}' ;;
  Storage.getCookies) echo '{"cookies":[{"name":"sid","domain":".example.com","path":"/"},{"name":"o","domain":"other.org","path":"/"}]}' ;;
  *) echo '{}' ;;
esac
STUB
  chmod +x "$TEST_DIR/cdp"
  export AGENT_TAB_CDP="$TEST_DIR/cdp"
  export AGENT_TAB_SHOT_DIR="$TEST_DIR/shots"
}

# Adds a tab to the stubbed /json/list.
chrome_has() {
  local tmp; tmp="$(mktemp)"
  jq --arg id "$1" --arg u "$2" '. + [{id: $id, type: "page", url: $u, webSocketDebuggerUrl: ("ws://x/" + $id)}]' "$TABS_JSON" > "$tmp"
  mv "$tmp" "$TABS_JSON"
}

@test "text returns page text for the owner" {
  cdp_setup
  id="$(open_tab agent-a r)"; chrome_has "$id" https://example.com/
  run "$SCRIPT" text --owner agent-a "$id"
  [ "$status" -eq 0 ]
  [ "$output" = "hello page" ]
  grep -q "ws://x/$id Runtime.evaluate" "$CDP_CALLS"
}

@test "eval runs an expression for the owner" {
  cdp_setup
  id="$(open_tab agent-a r)"; chrome_has "$id" https://example.com/
  run "$SCRIPT" eval --owner agent-a "$id" 'document.title'
  [ "$status" -eq 0 ]
  grep -q 'document.title' "$CDP_CALLS"
}

@test "nav sends Page.navigate for the owner" {
  cdp_setup
  id="$(open_tab agent-a r)"; chrome_has "$id" https://example.com/
  run "$SCRIPT" nav --owner agent-a "$id" https://example.com/next
  [ "$status" -eq 0 ]
  grep -q 'Page.navigate.*example.com/next' "$CDP_CALLS"
}

@test "shot writes a PNG under the screenshot dir" {
  cdp_setup
  id="$(open_tab agent-a r)"; chrome_has "$id" https://example.com/
  run "$SCRIPT" shot --owner agent-a "$id"
  [ "$status" -eq 0 ]
  [[ "$output" == "$AGENT_TAB_SHOT_DIR/"*.png ]]
  [ "$(cat "$output")" = "hi" ]
}

@test "page commands from another owner exit 3 with holder and reason" {
  cdp_setup
  id="$(open_tab agent-a "bot login")"; chrome_has "$id" https://example.com/
  for cmd in text eval nav shot; do
    run "$SCRIPT" "$cmd" --owner agent-b "$id" x
    [ "$status" -eq 3 ]
    [[ "$output" == *"agent-a"*"bot login"* ]]
  done
  [ ! -e "$CDP_CALLS" ]
}

@test "page commands need a live lease, even for the owner" {
  cdp_setup
  id="$(open_tab agent-a r)"; chrome_has "$id" https://example.com/
  tmp="$(mktemp)"; jq --arg id "$id" '.[$id].expires = 1' "$AGENT_TAB_STATE_DIR/tabs.json" > "$tmp"
  mv "$tmp" "$AGENT_TAB_STATE_DIR/tabs.json"
  run "$SCRIPT" text --owner agent-a "$id"
  [ "$status" -eq 3 ]
  [[ "$output" == *"renew"* ]]
}

@test "AGENT_TAB_OWNER is the default owner" {
  cdp_setup
  id="$(AGENT_TAB_OWNER=agent-a "$SCRIPT" open --reason r https://example.com)"
  jq -e --arg id "$id" '.[$id].owner == "agent-a"' "$AGENT_TAB_STATE_DIR/tabs.json"
  chrome_has "$id" https://example.com/
  AGENT_TAB_OWNER=agent-a run "$SCRIPT" text "$id"
  [ "$status" -eq 0 ]
  AGENT_TAB_OWNER=agent-b run "$SCRIPT" close "$id"
  [ "$status" -eq 3 ]
}

@test "health lists tabs that do not answer" {
  cdp_setup
  chrome_has OK1 https://example.com/
  chrome_has dead1 https://example.com/
  run "$SCRIPT" health
  [ "$status" -eq 1 ]
  [[ "$output" == *"dead1"* ]]
  [[ "$output" != *"OK1"* ]]
  ! grep -q '/json/close/' "$CDP_LOG"
}

@test "health --fix reloads, and closes only tabs no live lease owns" {
  cdp_setup
  chrome_has dead1 https://example.com/
  chrome_has dead2 https://example.com/
  # dead2 has a live lease from agent-a.
  mkdir -p "$AGENT_TAB_STATE_DIR"
  jq -n --argjson e "$(( $(date +%s) + 600 ))" '{dead2: {owner: "agent-a", reason: "r", url: "u", expires: $e}}' > "$AGENT_TAB_STATE_DIR/tabs.json"
  run "$SCRIPT" health --fix
  grep -q 'dead1 Page.reload' "$CDP_CALLS"
  grep -q '/json/close/dead1' "$CDP_LOG"
  ! grep -q '/json/close/dead2' "$CDP_LOG"
  [[ "$output" == *"dead2"*"agent-a"* ]]
}

@test "health is ok when every tab answers" {
  cdp_setup
  chrome_has OK1 https://example.com/
  run "$SCRIPT" health
  [ "$status" -eq 0 ]
}

@test "clear-cookies clears only that site's cookies when no live tab uses it" {
  cdp_setup
  chrome_has P1 https://other.org/
  run "$SCRIPT" clear-cookies example.com
  [ "$status" -eq 0 ]
  grep -q 'Network.deleteCookies.*"name":"sid"' "$CDP_CALLS"
  ! grep -q '"name":"o"' "$CDP_CALLS"
}

@test "clear-cookies exits 3 and lists blocking live-lease tabs" {
  cdp_setup
  id="$(open_tab agent-a "bot login")"; chrome_has "$id" https://app.example.com/x
  run "$SCRIPT" clear-cookies example.com
  [ "$status" -eq 3 ]
  [[ "$output" == *"$id"*"agent-a"*"bot login"* ]]
  ! grep -q 'deleteCookies' "$CDP_CALLS" 2>/dev/null
}

@test "clear-cookies ignores expired-lease tabs on the site" {
  cdp_setup
  id="$(open_tab agent-a r)"; chrome_has "$id" https://example.com/
  chrome_has P1 https://other.org/
  tmp="$(mktemp)"; jq --arg id "$id" '.[$id].expires = 1' "$AGENT_TAB_STATE_DIR/tabs.json" > "$tmp"
  mv "$tmp" "$AGENT_TAB_STATE_DIR/tabs.json"
  run "$SCRIPT" clear-cookies example.com
  [ "$status" -eq 0 ]
}

@test "usage lists the new commands" {
  run "$SCRIPT" --help
  for c in text eval nav shot health clear-cookies AGENT_TAB_OWNER; do
    [[ "$output" == *"$c"* ]]
  done
}

# #234: a real node CDP reply over 64 KiB used to be cut before jq parsed it.
@test "shot saves a full PNG when the CDP reply is larger than 64 KiB" {
  cdp_setup
  unset AGENT_TAB_CDP
  node "$BATS_TEST_DIRNAME/fixtures/fake-cdp-ws.mjs" "$TEST_DIR/port" 300000 &
  srv=$!
  for _ in $(seq 50); do [ -s "$TEST_DIR/port" ] && break; sleep 0.1; done
  id="$(open_tab agent-a r)"
  jq --arg id "$id" --arg ws "ws://127.0.0.1:$(cat "$TEST_DIR/port")/$id" \
    '. + [{id: $id, type: "page", url: "https://example.com/", webSocketDebuggerUrl: $ws}]' \
    "$TABS_JSON" > "$TEST_DIR/t.json" && mv "$TEST_DIR/t.json" "$TABS_JSON"
  run "$SCRIPT" shot --owner agent-a "$id"
  kill "$srv" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [ "$(wc -c < "$output" | tr -d ' ')" -eq 300000 ]
}

# --- eval size (#270): the script must never ride in node's argv ---
# The real node CDP client talks to fake-cdp-eval-ws.mjs, which answers with
# the length and sha256 of the expression it got. A node shim on PATH logs
# the total size of node's argv, then runs the real node.

eval_ws_setup() {
  cdp_setup
  unset AGENT_TAB_CDP
  REAL_NODE="$(command -v node)"
  cat > "$TEST_DIR/bin/node" <<STUB
#!/bin/bash
n=0; for a in "\$@"; do n=\$((n + \${#a})); done
echo "\$n" >> "$TEST_DIR/node-argv.log"
exec "$REAL_NODE" "\$@"
STUB
  chmod +x "$TEST_DIR/bin/node"
  "$REAL_NODE" "$BATS_TEST_DIRNAME/fixtures/fake-cdp-eval-ws.mjs" "$TEST_DIR/port" ${1:-} &
  srv=$!
  for _ in $(seq 50); do [ -s "$TEST_DIR/port" ] && break; sleep 0.1; done
  id="$(open_tab agent-a r)"
  jq --arg id "$id" --arg ws "ws://127.0.0.1:$(cat "$TEST_DIR/port")/$id" \
    '. + [{id: $id, type: "page", url: "https://example.com/", webSocketDebuggerUrl: $ws}]' \
    "$TABS_JSON" > "$TEST_DIR/t.json" && mv "$TEST_DIR/t.json" "$TABS_JSON"
}

# "chars=<n> sha256=<16 hex>" for the file $1, as the fake server prints it.
expected_eval() {
  printf 'chars=%s sha256=%s' "$(wc -c < "$1" | tr -d ' ')" "$(shasum -a 256 < "$1" | cut -c1-16)"
}

@test "eval sends a 300 KB script whole, with node argv under 4 KB (#270)" {
  eval_ws_setup
  { printf "'"; head -c 300000 /dev/zero | tr '\0' a; printf "'.length"; } > "$TEST_DIR/big.js"
  run "$SCRIPT" eval --owner agent-a "$id" "$(cat "$TEST_DIR/big.js")"
  kill "$srv" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [ "$output" = "$(expected_eval "$TEST_DIR/big.js")" ]
  [ "$(sort -n "$TEST_DIR/node-argv.log" | tail -n 1)" -lt 4096 ]
}

@test "eval - reads a 2 MB script from stdin, past the argv limit (#270)" {
  eval_ws_setup
  { printf 'window.data = "'; head -c 2000000 /dev/zero | tr '\0' b; printf '"; window.data.length'; } > "$TEST_DIR/huge.js"
  run "$SCRIPT" eval --owner agent-a "$id" - < "$TEST_DIR/huge.js"
  kill "$srv" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [ "$output" = "$(expected_eval "$TEST_DIR/huge.js")" ]
}

@test "eval failure names the cause from the CDP client (#270)" {
  eval_ws_setup close
  SECONDS=0
  run "$SCRIPT" eval --owner agent-a "$id" '1 + 1'
  kill "$srv" 2>/dev/null || true
  [ "$status" -eq 1 ]
  [[ "$output" == *"agent-tab: cdp Runtime.evaluate: websocket closed before the answer (code 1006)"* ]]
  [[ "$output" == *"agent-tab: eval failed in tab"* ]]
  # The close is reported at once, not after the 10 s no-answer timeout.
  [ "$SECONDS" -lt 8 ]
}

@test "upload sets the file on the tab's file input through DOM calls" {
  cdp_setup
  cat > "$TEST_DIR/cdp" <<'STUB'
#!/bin/bash
echo "$1 $2 $3" >> "$CDP_CALLS"
case "$2" in
  DOM.getDocument) echo '{"root":{"nodeId":1}}' ;;
  DOM.querySelector) echo '{"nodeId":7}' ;;
  *) echo '{}' ;;
esac
STUB
  id="$(open_tab agent-a r)"; chrome_has "$id" https://example.com/
  echo data > "$TEST_DIR/f.txt"
  run "$SCRIPT" upload --owner agent-a "$id" "$TEST_DIR/f.txt"
  [ "$status" -eq 0 ]
  grep -q 'DOM.querySelector.*input\[type=file\]' "$CDP_CALLS"
  grep -q "DOM.setFileInputFiles.*\"nodeId\":7.*f.txt" "$CDP_CALLS"
}

@test "upload from another owner exits 3 and a missing file exits 2" {
  cdp_setup
  id="$(open_tab agent-a "bot login")"; chrome_has "$id" https://example.com/
  echo data > "$TEST_DIR/f.txt"
  run "$SCRIPT" upload --owner agent-b "$id" "$TEST_DIR/f.txt"
  [ "$status" -eq 3 ]
  run "$SCRIPT" upload --owner agent-a "$id" "$TEST_DIR/none.txt"
  [ "$status" -eq 2 ]
}
