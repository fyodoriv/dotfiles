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

# --- upload over the real one-socket node client (no AGENT_TAB_CDP stub) ---

upload_ws_setup() {
  cdp_setup
  unset AGENT_TAB_CDP
  node "$BATS_TEST_DIRNAME/fixtures/fake-cdp-dom-ws.mjs" "$TEST_DIR/port" "$TEST_DIR/dom.log" &
  srv=$!
  for _ in $(seq 50); do [ -s "$TEST_DIR/port" ] && break; sleep 0.1; done
  id="$(open_tab agent-a r)"
  jq --arg id "$id" --arg ws "ws://127.0.0.1:$(cat "$TEST_DIR/port")/$id" \
    '. + [{id: $id, type: "page", url: "https://example.com/", webSocketDebuggerUrl: $ws}]' \
    "$TABS_JSON" > "$TEST_DIR/t.json" && mv "$TEST_DIR/t.json" "$TABS_JSON"
  echo data > "$TEST_DIR/f.txt"
}

@test "upload runs getDocument, querySelector, setFileInputFiles on one socket" {
  upload_ws_setup
  run "$SCRIPT" upload --owner agent-a --selector '.main input[type=file]' "$id" "$TEST_DIR/f.txt"
  kill "$srv" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [ "$(cut -d' ' -f1 "$TEST_DIR/dom.log" | tr '\n' ,)" = "DOM.getDocument,DOM.querySelector,DOM.setFileInputFiles," ]
  grep -q '"selector":".main input\[type=file\]"' "$TEST_DIR/dom.log"
  grep -q 'f.txt' "$TEST_DIR/dom.log"
}

@test "upload fails when no element matches the selector" {
  upload_ws_setup
  run "$SCRIPT" upload --owner agent-a --selector '#missing' "$id" "$TEST_DIR/f.txt"
  kill "$srv" 2>/dev/null || true
  [ "$status" -eq 1 ]
  ! grep -q setFileInputFiles "$TEST_DIR/dom.log"
}

# --- upload refuses secret-looking files unless --force ---

@test "upload refuses ssh, gnupg, keychain, and pem files without --force" {
  cdp_setup
  id="$(open_tab agent-a r)"; chrome_has "$id" https://example.com/
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME/.ssh" "$HOME/.gnupg" "$HOME/Library/Keychains" "$TEST_DIR/x"
  for f in "$HOME/.ssh/id_ed25519" "$HOME/.gnupg/pubring.kbx" "$HOME/Library/Keychains/login.keychain-db" "$TEST_DIR/x/cert.pem"; do
    echo secret > "$f"
    run "$SCRIPT" upload --owner agent-a "$id" "$f"
    [ "$status" -eq 2 ]
    [[ "$output" == *"--force"* ]]
  done
  ! grep -q DOM. "$CDP_CALLS"
}

@test "upload refuses env files, token files, cloud and tool configs, and id_* keys" {
  cdp_setup
  id="$(open_tab agent-a r)"; chrome_has "$id" https://example.com/
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME/.kube" "$HOME/.docker" "$HOME/.config/gcloud" "$TEST_DIR/proj"
  for f in "$TEST_DIR/proj/.env" "$TEST_DIR/proj/.env.local" "$TEST_DIR/proj/.git-credentials" \
           "$TEST_DIR/proj/.npmrc" "$TEST_DIR/proj/.pgpass" "$HOME/.kube/config" "$HOME/.docker/config.json" \
           "$HOME/.config/gcloud/credentials.db" "$TEST_DIR/proj/vault.kdbx" "$TEST_DIR/proj/id_rsa" "$TEST_DIR/proj/id_ed25519.pub"; do
    echo s > "$f"
    run "$SCRIPT" upload --owner agent-a "$id" "$f"
    [ "$status" -eq 2 ]
    [[ "$output" == *"refusing"* ]]
  done
}

@test "upload refuses a symlink that points into ~/.ssh" {
  cdp_setup
  id="$(open_tab agent-a r)"; chrome_has "$id" https://example.com/
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME/.ssh"; echo secret > "$HOME/.ssh/id"
  ln -s "$HOME/.ssh/id" "$TEST_DIR/innocent.txt"
  run "$SCRIPT" upload --owner agent-a "$id" "$TEST_DIR/innocent.txt"
  [ "$status" -eq 2 ]
  [[ "$output" == *"refusing"* ]]
}

@test "upload refuses more secret paths, in any case, and hard links to them" {
  cdp_setup
  id="$(open_tab agent-a r)"; chrome_has "$id" https://example.com/
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME/.aws" "$HOME/.config/gh" "$TEST_DIR/x"
  echo s > "$HOME/.netrc"; echo s > "$HOME/.aws/credentials"; echo s > "$HOME/.config/gh/hosts.yml"
  echo s > "$TEST_DIR/x/SERVER.PEM"; echo s > "$TEST_DIR/x/a.key"; echo s > "$TEST_DIR/x/b.P12"
  for f in "$HOME/.netrc" "$HOME/.aws/credentials" "$HOME/.config/gh/hosts.yml" "$TEST_DIR/x/SERVER.PEM" "$TEST_DIR/x/a.key" "$TEST_DIR/x/b.P12"; do
    run "$SCRIPT" upload --owner agent-a "$id" "$f"
    [ "$status" -eq 2 ]
    [[ "$output" == *"refusing"* ]]
  done
  ln "$HOME/.netrc" "$TEST_DIR/x/plain.txt"
  run "$SCRIPT" upload --owner agent-a "$id" "$TEST_DIR/x/plain.txt"
  [ "$status" -eq 2 ]
  [[ "$output" == *"refusing"* ]]
}

@test "upload --force sends a pem file" {
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
  echo cert > "$TEST_DIR/cert.pem"
  run "$SCRIPT" upload --owner agent-a --force "$id" "$TEST_DIR/cert.pem"
  [ "$status" -eq 0 ]
  grep -q DOM.setFileInputFiles "$CDP_CALLS"
}

# #561: the real shell owner runs against a disposable browser target table.
gdoc_owner_setup() {
  unset BASH_ENV ENV
  cdp_setup
  export AGENT_TAB_PORT=0
  [ -z "${BASH_ENV+x}${ENV+x}" ]
  export OWNER_EVENT="$TEST_DIR/owner-event"
  export CDP_SAMPLE="$TEST_DIR/png-sample"
  export OWNER_REAL_MV="$(command -v mv)"
  export OWNER_REAL_DATE="$(command -v date)"
  cat > "$TEST_DIR/bin/curl" <<'STUB'
#!/bin/bash
set -eu
url="${*: -1}"
case "$url" in http://127.0.0.1:0/json/*) ;; *) exit 91 ;; esac
printf '%s\n' "$url" >> "$CDP_LOG"
case "$url" in
  */json/new*)
    id="T$(wc -l < "$CDP_LOG" | tr -d ' ')"
    jq --arg id "$id" '. + [{id:$id,type:"page",url:"https://example.com",webSocketDebuggerUrl:("ws://x/"+$id)}]' "$TABS_JSON" > "$TABS_JSON.next"
    "$OWNER_REAL_MV" "$TABS_JSON.next" "$TABS_JSON"
    jq -nc --arg id "$id" '{id:$id}'
    ;;
  */json/close/*)
    [ ! -e "$OWNER_EVENT.close" ] || exit 22
    id="${url##*/}"
    jq --arg id "$id" 'map(select(.id != $id))' "$TABS_JSON" > "$TABS_JSON.next"
    "$OWNER_REAL_MV" "$TABS_JSON.next" "$TABS_JSON"
    echo 'Target is closing'
    ;;
  */json/list) cat "$TABS_JSON" ;;
  *) exit 7 ;;
esac
STUB
  cat > "$TEST_DIR/bin/date" <<'STUB'
#!/bin/bash
if [ "$*" = '+%Y%m%d-%H%M%S' ]; then
  echo '20261103-120000'
else
  exec "$OWNER_REAL_DATE" "$@"
fi
STUB
  cat > "$TEST_DIR/bin/mv" <<'STUB'
#!/bin/bash
if [ "${*: -1}" = "$AGENT_TAB_STATE_DIR/tabs.json" ] && [ -e "$OWNER_EVENT.commit" ]; then
  rm "$OWNER_EVENT.commit"
  touch "$OWNER_EVENT.commit-failed"
  exit 1
fi
exec "$OWNER_REAL_MV" "$@"
STUB
  cat > "$AGENT_TAB_CDP" <<'STUB'
#!/bin/bash
case "$1" in ws://x/T[0-9]*) ;; *) exit 92 ;; esac
printf '%s %s\n' "$1" "$2" >> "$CDP_CALLS"
case "$2" in
  Runtime.evaluate) echo '{"result":{"type":"string","value":"fixture page"}}' ;;
  Page.captureScreenshot) jq -Rn --arg png "$(cat "$CDP_SAMPLE")" '{data:$png}' ;;
  *) exit 1 ;;
esac
STUB
  chmod +x "$TEST_DIR/bin/curl" "$TEST_DIR/bin/date" "$TEST_DIR/bin/mv"
  [ "$(/bin/bash -c 'type -P curl')" = "$TEST_DIR/bin/curl" ]
  [ "$AGENT_TAB_CDP" = "$TEST_DIR/cdp" ] && [ -x "$AGENT_TAB_CDP" ]
  export PNG_BLACK='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGNgAAAAAgABSK+kcQAAAABJRU5ErkJggg=='
  export PNG_WHITE='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGP4DwABAQEAsTj2FAAAAABJRU5ErkJggg=='
  printf '%s\n' "$PNG_BLACK" > "$CDP_SAMPLE"
}

gdoc_registry_has() {
  jq -e --arg id "$1" 'any(.[]; .id == $id)' "$TABS_JSON" >/dev/null
}

gdoc_open() {
  local id
  id="$(open_tab "$@")" || return 1
  gdoc_registry_has "$id" || return 1
  grep -Fq 'http://127.0.0.1:0/json/new?' "$CDP_LOG" || return 1
  printf '%s\n' "$id"
}

@test "gdoc-561 T01 same-second shots preserve both images" {
  gdoc_owner_setup
  id="$(gdoc_open agent-a capture)"
  first="$("$SCRIPT" shot --owner agent-a "$id")"
  printf '%s\n' "$PNG_WHITE" > "$CDP_SAMPLE"
  second="$("$SCRIPT" shot --owner agent-a "$id")"
  [ "$(wc -l < "$CDP_CALLS" | tr -d ' ')" = 2 ]
  if [ "$first" = "$second" ]; then
    echo 'T01: two successful capture replies reused one screenshot path'
    return 1
  fi
  [ "$(base64 < "$first" | tr -d '\n')" = "$PNG_BLACK" ]
  [ "$(base64 < "$second" | tr -d '\n')" = "$PNG_WHITE" ]
}

@test "gdoc-561 T02 close failure keeps the lease for retry" {
  gdoc_owner_setup
  id="$(gdoc_open agent-a capture)"
  touch "$OWNER_EVENT.close"
  run "$SCRIPT" close --owner agent-a "$id"
  gdoc_registry_has "$id"
  grep -F "/json/close/$id" "$CDP_LOG"
  if [ "$status" -eq 0 ] || ! jq -e --arg id "$id" '.[$id].owner == "agent-a"' "$AGENT_TAB_STATE_DIR/tabs.json"; then
    owner="$(jq -r --arg id "$id" '.[$id].owner // "missing"' "$AGENT_TAB_STATE_DIR/tabs.json")"
    echo "T02: target still present, close exit=$status, lease owner=$owner"
    return 1
  fi
  rm "$OWNER_EVENT.close"
  run "$SCRIPT" close --owner agent-a "$id"
  [ "$status" -eq 0 ]
  if gdoc_registry_has "$id"; then return 1; fi
  jq -e --arg id "$id" 'has($id) | not' "$AGENT_TAB_STATE_DIR/tabs.json"
}

@test "gdoc-561 T03 failed lease commit leaves no unowned target" {
  gdoc_owner_setup
  touch "$OWNER_EVENT.commit"
  run open_tab agent-a capture
  [ -e "$OWNER_EVENT.commit-failed" ]
  grep -F '/json/new?' "$CDP_LOG"
  [ "$status" -ne 0 ]
  id="$(jq -r '.[0].id // empty' "$TABS_JSON")"
  if [ -n "$id" ] && ! jq -e --arg id "$id" '.[$id].owner == "agent-a"' "$AGENT_TAB_STATE_DIR/tabs.json"; then
    echo 'T03: lease commit failed, open refused, browser still has untracked target'
    return 1
  fi
}

@test "gdoc-561 T04 foreign live target refuses close eval and shot" {
  gdoc_owner_setup
  id="$(gdoc_open agent-a capture)"
  cp "$TABS_JSON" "$TEST_DIR/targets.before"
  cp "$AGENT_TAB_STATE_DIR/tabs.json" "$TEST_DIR/leases.before"
  run "$SCRIPT" close --owner agent-b "$id"
  [ "$status" -eq 3 ]
  run "$SCRIPT" eval --owner agent-b "$id" 'document.title'
  [ "$status" -eq 3 ]
  run "$SCRIPT" shot --owner agent-b "$id"
  [ "$status" -eq 3 ]
  [ ! -e "$CDP_CALLS" ]
  [ ! -e "$AGENT_TAB_SHOT_DIR" ]
  if grep -F '/json/close/' "$CDP_LOG"; then return 1; fi
  cmp "$TABS_JSON" "$TEST_DIR/targets.before"
  cmp "$AGENT_TAB_STATE_DIR/tabs.json" "$TEST_DIR/leases.before"
}

@test "gdoc-561 T05 own open eval shot and close preserve a second target" {
  gdoc_owner_setup
  id="$(gdoc_open agent-a capture)"
  other="$(gdoc_open agent-a sentinel)"
  run "$SCRIPT" eval --owner agent-a "$id" 'document.title'
  [ "$status" -eq 0 ]
  [ "$output" = 'fixture page' ]
  run "$SCRIPT" shot --owner agent-a "$id"
  [ "$status" -eq 0 ]
  [ "$(base64 < "$output" | tr -d '\n')" = "$PNG_BLACK" ]
  run "$SCRIPT" close --owner agent-a "$id"
  [ "$status" -eq 0 ]
  if gdoc_registry_has "$id"; then return 1; fi
  gdoc_registry_has "$other"
  jq -e --arg id "$id" --arg other "$other" '(.[$id] == null) and (.[$other].owner == "agent-a")' "$AGENT_TAB_STATE_DIR/tabs.json"
}

gdoc_verified_setup() {
  gdoc_owner_setup
  mv "$TEST_DIR/bin/curl" "$TEST_DIR/bin/curl-fixture"
  cat > "$TEST_DIR/bin/curl" <<'STUB'
#!/bin/bash
set -eu
url="${*: -1}"
case "$url" in
  http://127.0.0.1:0/json/close/*)
    if [ -f "$OWNER_EVENT.held" ]; then
      printf '%s\n' "$url" >> "$CDP_LOG"
      echo 'Target is closing'
      exit 0
    fi ;;
  http://127.0.0.1:0/json/list)
    if [ -f "$OWNER_EVENT.malformed" ]; then
      printf '%s\n' "$url" >> "$CDP_LOG"
      printf '%s\n' '{"unexpected":"fixture"}'
      exit 0
    fi
    if [ -f "$OWNER_EVENT.unavailable" ]; then
      printf '%s\n' "$url" >> "$CDP_LOG"
      exit 7
    fi ;;
esac
exec "${0%/*}/curl-fixture" "$@"
STUB
  chmod 700 "$TEST_DIR/bin/curl"
  [ "$(/bin/bash -c 'type -P curl')" = "$TEST_DIR/bin/curl" ]
  export VERIFIED_STATE="$AGENT_TAB_STATE_DIR/tabs.json"
}

gdoc_verified_lease_present() {
  jq -e --arg id "$1" 'has($id)' "$VERIFIED_STATE" >/dev/null
}

gdoc_verified_receipt() {
  local id="$1" variant="$2" lease=0 target=0 calls=0
  if gdoc_verified_lease_present "$3"; then lease=1; fi
  if gdoc_registry_has "$3"; then target=1; fi
  calls="$(wc -l < "$CDP_LOG" | tr -d ' ')"
  printf 'VERIFIED_CLOSE_OBSERVATION %s %s exit=%s lease=%s target=%s calls=%s\n' \
    "$id" "$variant" "$status" "$lease" "$target" "$calls" >&3
}

@test "gdoc-561 V01 accepted close while target remains" {
  gdoc_verified_setup
  local legacy strict legacy_status legacy_lease
  legacy="$(gdoc_open agent-a legacy)"
  touch "$OWNER_EVENT.held"
  : > "$CDP_LOG"
  run "$SCRIPT" close --owner agent-a "$legacy"
  gdoc_verified_receipt V01 legacy "$legacy"
  legacy_status="$status"
  legacy_lease=0
  if gdoc_verified_lease_present "$legacy"; then legacy_lease=1; fi
  [ "$legacy_status" -eq 0 ] && [ "$legacy_lease" -eq 0 ]
  gdoc_registry_has "$legacy"
  [ "$(cat "$CDP_LOG")" = "http://127.0.0.1:0/json/close/$legacy" ]

  strict="$(gdoc_open agent-a strict)"
  cp "$VERIFIED_STATE" "$TEST_DIR/prior"
  : > "$CDP_LOG"
  run "$SCRIPT" close-verified --owner agent-a "$strict"
  gdoc_verified_receipt V01 strict "$strict"
  [ "$status" -eq 1 ]
  cmp -s "$VERIFIED_STATE" "$TEST_DIR/prior"
  gdoc_registry_has "$strict"
  [ "$(cat "$CDP_LOG")" = "$(printf 'http://127.0.0.1:0/json/close/%s\nhttp://127.0.0.1:0/json/list' "$strict")" ]
}

@test "gdoc-561 V02 valid census proves exact target absent" {
  gdoc_verified_setup
  local owned other
  owned="$(gdoc_open agent-a owned)"
  other="$(gdoc_open agent-b other)"
  jq --arg id "$owned" 'del(.[$id])' "$VERIFIED_STATE" > "$TEST_DIR/expected"
  : > "$CDP_LOG"
  run "$SCRIPT" close-verified --owner agent-a "$owned"
  gdoc_verified_receipt V02 strict "$owned"
  [ "$status" -eq 0 ]
  ! gdoc_registry_has "$owned"
  gdoc_registry_has "$other"
  [ "$(jq -cS . "$VERIFIED_STATE")" = "$(jq -cS . "$TEST_DIR/expected")" ]
  [ "$(cat "$CDP_LOG")" = "$(printf 'http://127.0.0.1:0/json/close/%s\nhttp://127.0.0.1:0/json/list' "$owned")" ]
}

@test "gdoc-561 V03 malformed and unavailable census retain the lease" {
  gdoc_verified_setup
  local variant owned malformed unavailable failures=0
  malformed="$(gdoc_open agent-a malformed)"
  unavailable="$(gdoc_open agent-a unavailable)"
  [ "$malformed" != "$unavailable" ]
  for variant in malformed unavailable; do
    owned="$malformed"
    if [ "$variant" = unavailable ]; then owned="$unavailable"; fi
    cp "$VERIFIED_STATE" "$TEST_DIR/prior"
    touch "$OWNER_EVENT.held" "$OWNER_EVENT.$variant"
    : > "$CDP_LOG"
    run "$SCRIPT" close-verified --owner agent-a "$owned"
    gdoc_verified_receipt V03 "$variant" "$owned"
    if ! { [ "$status" -eq 1 ] &&
      cmp -s "$VERIFIED_STATE" "$TEST_DIR/prior" &&
      gdoc_registry_has "$owned" &&
      [ "$(cat "$CDP_LOG")" = "$(printf 'http://127.0.0.1:0/json/close/%s\nhttp://127.0.0.1:0/json/list' "$owned")" ]; }; then
      failures=$((failures + 1))
    fi
    rm "$OWNER_EVENT.$variant"
  done
  [ "$failures" -eq 0 ]
}

@test "gdoc-561 V04 wrong owner refuses before transport even for expired lease" {
  gdoc_verified_setup
  local foreign variant failures=0
  foreign="$(gdoc_open agent-b foreign)"
  for variant in live expired; do
    if [ "$variant" = expired ]; then
      jq --arg id "$foreign" '.[$id].expires = 1' "$VERIFIED_STATE" > "$TEST_DIR/expired"
      mv "$TEST_DIR/expired" "$VERIFIED_STATE"
    fi
    cp "$VERIFIED_STATE" "$TEST_DIR/prior"
    cp "$TABS_JSON" "$TEST_DIR/registry"
    : > "$CDP_LOG"
    run "$SCRIPT" close-verified --owner agent-a "$foreign"
    gdoc_verified_receipt V04 "$variant" "$foreign"
    if ! { [ "$status" -eq 3 ] &&
      [ ! -s "$CDP_LOG" ] &&
      cmp -s "$VERIFIED_STATE" "$TEST_DIR/prior" &&
      cmp -s "$TABS_JSON" "$TEST_DIR/registry"; }; then
      failures=$((failures + 1))
    fi
  done
  [ "$failures" -eq 0 ]
}
