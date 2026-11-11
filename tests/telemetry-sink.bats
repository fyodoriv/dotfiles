#!/usr/bin/env bats
# Tests for the org log sink of bin/dotfiles-telemetry: one policy file routes
# the events (and, when switched on, the error log lines) to an org log system
# instead of the public default. The org receiver here is a fake curl. The
# tests follow Splunk's public HEC format; they never meet a real Splunk
# server. Rule numbers match the spec in docs/observability.md#org-log-sink.

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME"
  export DOTFILES_STATS_FILE="$TEST_DIR/stats.jsonl"
  export DOTFILES_COMMANDS_FILE="$TEST_DIR/commands.jsonl"
  export DOTFILES_TELEMETRY_STATE="$TEST_DIR/telemetry.json"
  export DOTFILES_ERRORS_FILE="$TEST_DIR/errors.jsonl"
  export DOTFILES_INSTALL_RECEIPT="$TEST_DIR/install-receipt.json"
  export DOTFILES_TELEMETRY_TEST_GAINS_SINCE="9999-12-31"
  # The stand-in for the public default endpoint: no request may reach it.
  export DOTFILES_TELEMETRY_URL="http://127.0.0.1:9/public-default"
  export DOTFILES_TELEMETRY_KEY_FILE="$TEST_DIR/key"
  export DOTFILES_POSTHOG_KEY="phc_publicCanaryKey1"
  export DOTFILES_TELEMETRY_SINK_FILE="$TEST_DIR/telemetry-sink.json"
  export ORG_TEST_TOKEN="tokCanary123ABC"
  unset DO_NOT_TRACK CI DOTFILES_TELEMETRY DOTFILES_TELEMETRY_TTY
  : >"$DOTFILES_TELEMETRY_KEY_FILE"
  FAKE="$TEST_DIR/fake-curl"
  # Logs the arguments, the config file given with -K, the URL, and the body.
  cat >"$FAKE" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"${FAKE_LOG:?}.args"
url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -K) cat "$2" >>"$FAKE_LOG.config"; shift ;;
    http*) url="$1" ;;
  esac
  shift
done
printf '%s\n' "$url" >>"$FAKE_LOG.urls"
cat >>"$FAKE_LOG"
echo >>"$FAKE_LOG"
printf '%s' "${FAKE_CODE:-200}"
SH
  chmod +x "$FAKE"
  export DOTFILES_TELEMETRY_CURL="$FAKE" FAKE_LOG="$TEST_DIR/requests.log"
  TEL="$REPO/bin/dotfiles-telemetry"
  NOW="$(date -u +%FT%TZ)"
  printf '%s\n' \
    "{\"task\":\"sync\",\"timestamp\":\"$NOW\",\"seconds_saved\":3,\"units\":1}" \
    "{\"task\":\"doctor\",\"timestamp\":\"$NOW\",\"units\":1,\"pass\":40}" \
    >"$DOTFILES_STATS_FILE"
  ORG_URL="https://splunk.example.com:8088/services/collector/event"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Request helpers. A request is one line in the URL log.
request_count() { if [ -f "$FAKE_LOG.urls" ]; then wc -l <"$FAKE_LOG.urls" | tr -d ' '; else echo 0; fi; }
public_requests() { if [ -f "$FAKE_LOG.urls" ]; then grep -c 'public-default' "$FAKE_LOG.urls" || true; else echo 0; fi; }
refute() { if "$@"; then return 1; fi; }
set_state() { jq -c "$1" "$DOTFILES_TELEMETRY_STATE" >"$TEST_DIR/state.new" && mv "$TEST_DIR/state.new" "$DOTFILES_TELEMETRY_STATE"; }

# write_policy JSON: the policy file, mode 600.
write_policy() {
  printf '%s\n' "$1" >"$DOTFILES_TELEMETRY_SINK_FILE"
  chmod 600 "$DOTFILES_TELEMETRY_SINK_FILE"
}
# hec_policy [JQ_FILTER]: a valid splunk-hec policy, changed by the filter.
hec_policy() {
  jq -n -c --arg url "$ORG_URL" '{version: 1, kind: "splunk-hec", url: $url,
    token: {env: "ORG_TEST_TOKEN"}, index: "devtools", sourcetype: "dotfiles:telemetry", source: "dotfiles"}' |
    jq -c "${1:-.}" >"$DOTFILES_TELEMETRY_SINK_FILE"
  chmod 600 "$DOTFILES_TELEMETRY_SINK_FILE"
}
file_policy() {
  jq -n -c --arg path "${FILE_SINK:-~/logs/dotfiles-telemetry.jsonl}" '{version: 1, kind: "file", path: $path}' |
    jq -c "${1:-.}" >"$DOTFILES_TELEMETRY_SINK_FILE"
  chmod 600 "$DOTFILES_TELEMETRY_SINK_FILE"
}
# say_yes: a yes, with both cursors back at the start of the logs.
say_yes() {
  bash "$TEL" on >/dev/null
  set_state '.sent = 0 | .sent_commands = 0'
}
# The events a fake org receiver got, one JSON object per line.
org_events() { jq -c . "$FAKE_LOG" 2>/dev/null; }

# ── Rules 1 and 4: no policy, or kind posthog, is today's behavior ─────

@test "rule 1 and 4: no policy and kind posthog send the same request to the public default" {
  say_yes
  run bash "$TEL" send
  [[ "$output" == *"sent 2 event(s)"* ]]
  cp "$FAKE_LOG" "$TEST_DIR/none.body"
  cp "$FAKE_LOG.args" "$TEST_DIR/none.args"
  cp "$FAKE_LOG.urls" "$TEST_DIR/none.urls"
  rm -f "$FAKE_LOG" "$FAKE_LOG.args" "$FAKE_LOG.urls"
  write_policy '{"version":1,"kind":"posthog"}'
  set_state '.sent = 0 | .sent_commands = 0'
  run bash "$TEL" send
  [[ "$output" == *"sent 2 event(s)"* ]]
  cmp "$FAKE_LOG" "$TEST_DIR/none.body"
  cmp "$FAKE_LOG.args" "$TEST_DIR/none.args"
  cmp "$FAKE_LOG.urls" "$TEST_DIR/none.urls"
  [ "$(public_requests)" -eq 1 ]
  [ "$(jq -r .api_key "$FAKE_LOG" | head -n 1)" = "phc_publicCanaryKey1" ]
}

# ── Rule 2: an invalid policy sends nothing and asks nothing ───────────

@test "rule 2: every invalid policy sends nothing, asks nothing, and status names a reason code" {
  say_yes
  i=0
  while IFS= read -r bad; do
    i=$((i + 1))
    write_policy "$bad"
    run bash "$TEL" send
    [[ "$output" == *"not sent (sink policy invalid: "* ]] || { echo "case $i: $output"; false; }
    run bash "$TEL" status
    [[ "$output" == *"telemetry: off (sink policy invalid: "* ]] || { echo "case $i: $output"; false; }
    [[ "$output" != *CANARY* ]]
    [ "$(request_count)" -eq 0 ] || { echo "case $i sent"; false; }
  done <<'EOF'
{"version":1,"kind":"splunk-hec","token":{"env":"ORG_TEST_TOKEN"},"canary":"CANARY"}
{"version":2,"kind":"posthog"}
{"version":1,"kind":"carrier-pigeon"}
{"version":1,"kind":"splunk-hec","url":"http://splunk.example.com/x","token":{"env":"ORG_TEST_TOKEN"}}
{"version":1,"kind":"splunk-hec","url":"https://user:pw@splunk.example.com/x","token":{"env":"ORG_TEST_TOKEN"}}
{"version":1,"kind":"splunk-hec","url":"https://splunk.example.com/x"}
{"version":1,"kind":"splunk-hec","url":"https://splunk.example.com/x","token":{"env":"A","file":"~/t"}}
{"version":1,"kind":"splunk-hec","url":"https://splunk.example.com/x","token":{"env":"ORG_TEST_TOKEN"},"index":"bad index!"}
{"version":1,"kind":"posthog","consent":"managed"}
{"version":1,"kind":"posthog","error_logs":true}
{"version":1,"kind":"file"}
{"version":1,"kind":"file","path":"/etc/dotfiles.jsonl"}
{"version":1,"kind":"file","path":"~/../x.jsonl"}
{"version":1,"kind":"off","consent":"managed"}
{"version":1,"kind":"posthog","consent":"sometimes","extra":"CANARY"}
not json at all CANARY
[]
EOF
  [ "$(public_requests)" -eq 0 ]
}

@test "rule 2: a policy file writable by group or others is invalid" {
  say_yes
  hec_policy
  chmod 664 "$DOTFILES_TELEMETRY_SINK_FILE"
  run bash "$TEL" status
  [[ "$output" == *"sink policy invalid: "* ]]
  run bash "$TEL" send
  [[ "$output" == *"not sent (sink policy invalid: "* ]]
  [ "$(request_count)" -eq 0 ]
}

@test "rule 2: an invalid policy asks no question, even on a terminal with a key" {
  hec_policy '.version = 9'
  DOTFILES_TELEMETRY_TTY=1 run bash "$TEL" ask --install </dev/null
  [[ "$output" != *"Share anonymous"* ]]
  [ ! -e "$DOTFILES_TELEMETRY_STATE" ]
}

# ── Rule 3: kind off ───────────────────────────────────────────────────

@test "rule 3: kind off sends nothing, asks nothing, and status says off by org policy" {
  say_yes
  write_policy '{"version":1,"kind":"off"}'
  run bash "$TEL" status
  [[ "$output" == *"off by org policy"* ]]
  run bash "$TEL" send
  [[ "$output" == *"not sent (off by org policy)"* ]]
  DOTFILES_TELEMETRY_TTY=1 run bash "$TEL" ask --install </dev/null
  [[ "$output" != *"Share anonymous"* ]]
  [ "$(request_count)" -eq 0 ]
}

# ── Rule 5: splunk-hec ─────────────────────────────────────────────────

@test "rule 5: the HEC request has the URL, the Splunk header, the batch lines, and no PostHog key" {
  hec_policy
  say_yes
  bash "$TEL" send >/dev/null
  rm -f "$FAKE_LOG" "$FAKE_LOG.args" "$FAKE_LOG.urls" "$FAKE_LOG.config"
  printf '{"task":"sync","timestamp":"%s","seconds_saved":3,"units":1}\n' "$NOW" >>"$DOTFILES_STATS_FILE"
  printf '{"command":"doctor","timestamp":"%s","ok":true,"duration_ms":1840}\n' "$NOW" >"$DOTFILES_COMMANDS_FILE"
  run bash "$TEL" send
  [[ "$output" == *"sent 2 event(s)"* ]]
  # One request per log (stats, then commands).
  [ "$(request_count)" -eq 2 ]
  [ "$(public_requests)" -eq 0 ]
  [ "$(head -n 1 "$FAKE_LOG.urls")" = "$ORG_URL" ]
  grep -qi 'content-type: application/json' "$FAKE_LOG.args"
  grep -qF "Authorization: Splunk $ORG_TEST_TOKEN" "$FAKE_LOG.config"
  # One JSON object per event, joined by newlines.
  [ "$(org_events | wc -l | tr -d ' ')" -eq 2 ]
  org_events | jq -e -s 'all(.[]; (.time | type) == "number" and .source == "dotfiles"
    and .sourcetype == "dotfiles:telemetry" and .index == "devtools"
    and (.event.event | startswith("dotfiles.")) and (.event.install_id | length) == 32
    and (.event.app_version | length) > 0)' >/dev/null
  org_events | jq -e -s '[.[].event.event] | sort == ["dotfiles.command", "dotfiles.run"]' >/dev/null
  org_events | jq -e -s '.[] | select(.event.event == "dotfiles.run") | .event.task == "sync" and .event.seconds_saved == 3' >/dev/null
  refute grep -q 'phc_' "$FAKE_LOG" "$FAKE_LOG.args" "$FAKE_LOG.config"
  refute grep -q 'api_key' "$FAKE_LOG"
}

@test "rule 5: index is left out when the policy sets none, and the defaults fill source and sourcetype" {
  hec_policy 'del(.index, .sourcetype, .source)'
  say_yes
  bash "$TEL" send >/dev/null
  printf '{"task":"sync","timestamp":"%s","units":1}\n' "$NOW" >>"$DOTFILES_STATS_FILE"
  bash "$TEL" send >/dev/null
  org_events | jq -e -s 'length == 1 and (.[0] | has("index") | not) and .[0].source == "dotfiles"
    and .[0].sourcetype == "dotfiles:telemetry"' >/dev/null
}

@test "rule 5: the PostHog key is never read on the org path: not the env, the file, or the Keychain" {
  hec_policy
  export DOTFILES_POSTHOG_KEY=""
  echo "phc_fileCanaryKey2" >"$DOTFILES_TELEMETRY_KEY_FILE"
  printf '#!/bin/bash\necho "$*" >>"%s/security.calls"\necho phc_keychainCanary3\n' "$TEST_DIR" >"$TEST_DIR/fake-security"
  chmod +x "$TEST_DIR/fake-security"
  export DOTFILES_TELEMETRY_SECURITY="$TEST_DIR/fake-security"
  say_yes
  bash "$TEL" send >/dev/null
  printf '{"task":"sync","timestamp":"%s","units":1}\n' "$NOW" >>"$DOTFILES_STATS_FILE"
  run bash "$TEL" send
  [[ "$output" == *"sent 1 event(s)"* ]]
  [ ! -e "$TEST_DIR/security.calls" ]
  refute grep -q 'phc_' "$FAKE_LOG" "$FAKE_LOG.args" "$FAKE_LOG.config"
  run bash "$TEL" status
  [[ "$output" != *phc_* ]]
}

@test "rule 5: a non-2xx answer is a failure and the cursor stays" {
  hec_policy
  say_yes
  bash "$TEL" send >/dev/null
  printf '{"task":"sync","timestamp":"%s","units":1}\n' "$NOW" >>"$DOTFILES_STATS_FILE"
  FAKE_CODE=503 run bash "$TEL" send
  [[ "$output" == *"send failed (http 503)"* ]]
  [ "$(jq .sent "$DOTFILES_TELEMETRY_STATE")" -eq 2 ]
  run bash "$TEL" send
  [[ "$output" == *"sent 1 event(s)"* ]]
}

# ── Rule 6: file ───────────────────────────────────────────────────────

@test "rule 6: kind file appends JSON lines, mode 700 folder and 600 file, no network" {
  file_policy
  say_yes
  bash "$TEL" send >/dev/null
  printf '{"task":"sync","timestamp":"%s","units":1}\n' "$NOW" >>"$DOTFILES_STATS_FILE"
  run bash "$TEL" send
  [[ "$output" == *"sent 1 event(s)"* ]]
  out="$HOME/logs/dotfiles-telemetry.jsonl"
  [ -f "$out" ]
  [ "$(stat -c %a "$out" 2>/dev/null || stat -f %Lp "$out")" = "600" ]
  [ "$(stat -c %a "$HOME/logs" 2>/dev/null || stat -f %Lp "$HOME/logs")" = "700" ]
  jq -e -s 'length == 1 and .[0].event == "dotfiles.run" and .[0].sourcetype == "dotfiles:telemetry"
    and (.[0].time | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and .[0].task == "sync"
    and (.[0].install_id | length) == 32' "$out" >/dev/null
  [ "$(request_count)" -eq 0 ]
}

@test "rule 6: a file over 10 MB is renamed to .1, replacing an old one, and a new file starts" {
  file_policy
  say_yes
  bash "$TEL" send >/dev/null
  mkdir -p "$HOME/logs"
  out="$HOME/logs/dotfiles-telemetry.jsonl"
  head -c 10485761 /dev/zero | tr '\0' 'x' >"$out"
  echo old >"$out.1"
  printf '{"task":"sync","timestamp":"%s","units":1}\n' "$NOW" >>"$DOTFILES_STATS_FILE"
  bash "$TEL" send >/dev/null
  [ "$(wc -c <"$out.1" | tr -d ' ')" -eq 10485761 ]
  [ "$(wc -l <"$out" | tr -d ' ')" -eq 1 ]
  [ "$(stat -c %a "$out" 2>/dev/null || stat -f %Lp "$out")" = "600" ]
}

@test "rule 6: a file path that is a symlink, or outside the home, is invalid" {
  mkdir -p "$HOME/logs"
  ln -s "$TEST_DIR/elsewhere.jsonl" "$HOME/logs/link.jsonl"
  FILE_SINK="~/logs/link.jsonl" file_policy
  run bash "$TEL" status
  [[ "$output" == *"sink policy invalid: "* ]]
  FILE_SINK="$TEST_DIR/outside.jsonl" file_policy
  run bash "$TEL" status
  [[ "$output" == *"sink policy invalid: "* ]]
  mkdir -p "$TEST_DIR/real"
  ln -s "$TEST_DIR/real" "$HOME/linkdir"
  FILE_SINK="~/linkdir/out.jsonl" file_policy
  run bash "$TEL" status
  [[ "$output" == *"sink policy invalid: "* ]]
}

# ── Rule 7: consent ────────────────────────────────────────────────────

@test "rule 7: consent ask with an org sink needs the stored yes, and the question names the host" {
  hec_policy
  run bash "$TEL" send
  [[ "$output" == *"not sent (not asked yet"* ]]
  [ "$(request_count)" -eq 0 ]
  DOTFILES_TELEMETRY_TTY=1 run bash "$TEL" ask <<<"n"
  [[ "$output" == *"organization's log system at splunk.example.com"* ]]
  [[ "$output" != *"PostHog"* ]]
  [ "$(jq -r .consent "$DOTFILES_TELEMETRY_STATE")" = "no" ]
  rm -f "$DOTFILES_TELEMETRY_STATE"
  DOTFILES_TELEMETRY_TTY=1 run bash "$TEL" ask <<<"y"
  [ "$(jq -r .consent "$DOTFILES_TELEMETRY_STATE")" = "yes" ]
}

@test "rule 7: the question works with no PostHog key, because that key is not used" {
  hec_policy
  export DOTFILES_POSTHOG_KEY=""
  DOTFILES_TELEMETRY_TTY=1 run bash "$TEL" ask <<<"y"
  [[ "$output" == *"splunk.example.com"* ]]
  [ "$(jq -r .consent "$DOTFILES_TELEMETRY_STATE")" = "yes" ]
}

@test "rule 7: a file sink question names the file path" {
  file_policy
  DOTFILES_TELEMETRY_TTY=1 run bash "$TEL" ask <<<"n"
  [[ "$output" == *"~/logs/dotfiles-telemetry.jsonl"* ]]
}

@test "rule 7: consent managed sends with no stored answer, never asks, and status says so" {
  hec_policy '.consent = "managed"'
  run bash "$TEL" status
  [[ "$output" == *"managed by org policy"* ]]
  DOTFILES_TELEMETRY_TTY=1 run bash "$TEL" ask --install </dev/null
  [[ "$output" != *"Share anonymous"* ]]
  bash "$TEL" send >/dev/null
  printf '{"task":"sync","timestamp":"%s","units":1}\n' "$NOW" >>"$DOTFILES_STATS_FILE"
  run bash "$TEL" send
  [[ "$output" == *"sent 1 event(s)"* ]]
  [ "$(public_requests)" -eq 0 ]
}

@test "rule 7: with consent managed a stored no stops it, and telemetry on clears the no" {
  hec_policy '.consent = "managed"'
  bash "$TEL" off >/dev/null
  printf '{"task":"sync","timestamp":"%s","units":1}\n' "$NOW" >>"$DOTFILES_STATS_FILE"
  run bash "$TEL" send
  [[ "$output" == *"not sent (you said no"* ]]
  [ "$(request_count)" -eq 0 ]
  bash "$TEL" on >/dev/null
  bash "$TEL" send >/dev/null # first sight of the policy: cursors go to the end
  printf '{"task":"doctor","timestamp":"%s","units":1}\n' "$NOW" >>"$DOTFILES_STATS_FILE"
  run bash "$TEL" send
  [[ "$output" == *"sent 1 event(s)"* ]]
}

# ── Rule 8: env switches stop every sink ───────────────────────────────

@test "rule 8: DO_NOT_TRACK, CI, and DOTFILES_TELEMETRY=0 stop managed HEC and file sinks" {
  for kind in hec file; do
    if [ "$kind" = hec ]; then hec_policy '.consent = "managed"'; else file_policy '.consent = "managed"'; fi
    bash "$TEL" send >/dev/null
    printf '{"task":"sync","timestamp":"%s","units":1}\n' "$NOW" >>"$DOTFILES_STATS_FILE"
    for sw in "DO_NOT_TRACK=1" "CI=1" "DOTFILES_TELEMETRY=0"; do
      run env "$sw" bash "$TEL" send
      [[ "$output" == *"not sent ("* ]]
    done
  done
  [ "$(request_count)" -eq 0 ]
  [ ! -e "$HOME/logs/dotfiles-telemetry.jsonl" ]
}

# ── Rule 9: a sink change moves the cursor to the end ──────────────────

@test "rule 9: first sight, a changed policy, and a removed policy each skip older events" {
  say_yes
  hec_policy
  # First sight of a policy: the two seeded events stay behind.
  run bash "$TEL" send
  [[ "$output" == *"nothing new"* ]]
  [ "$(request_count)" -eq 0 ]
  printf '{"task":"sync","timestamp":"%s","units":1}\n' "$NOW" >>"$DOTFILES_STATS_FILE"
  bash "$TEL" send >/dev/null
  [ "$(request_count)" -eq 1 ]
  [ "$(head -n 1 "$FAKE_LOG.urls")" = "$ORG_URL" ]
  # A changed host: the event recorded before the send is not sent to it.
  printf '{"task":"doctor","timestamp":"%s","units":1}\n' "$NOW" >>"$DOTFILES_STATS_FILE"
  hec_policy '.url = "https://other.example.com/services/collector/event"'
  bash "$TEL" send >/dev/null
  [ "$(request_count)" -eq 1 ]
  # A removed policy: back to the public default, and again nothing old goes.
  printf '{"task":"doctor","timestamp":"%s","units":2}\n' "$NOW" >>"$DOTFILES_STATS_FILE"
  rm -f "$DOTFILES_TELEMETRY_SINK_FILE"
  bash "$TEL" send >/dev/null
  [ "$(request_count)" -eq 1 ]
  [ "$(public_requests)" -eq 0 ]
  # The state file keeps a fingerprint (kind and host) and never the token.
  [ "$(jq -r .sink "$DOTFILES_TELEMETRY_STATE")" = "posthog" ]
  hec_policy
  bash "$TEL" send >/dev/null
  [ "$(jq -r .sink "$DOTFILES_TELEMETRY_STATE")" = "splunk-hec:splunk.example.com" ]
  refute grep -q "$ORG_TEST_TOKEN" "$DOTFILES_TELEMETRY_STATE"
}

@test "rule 9: events recorded while the policy says off never go to the public default" {
  say_yes
  write_policy '{"version":1,"kind":"off"}'
  # Any run of the script while the policy is in place sees the change.
  bash "$TEL" daily
  printf '{"task":"sync","timestamp":"%s","units":1}\n' "$NOW" >>"$DOTFILES_STATS_FILE"
  rm -f "$DOTFILES_TELEMETRY_SINK_FILE"
  run bash "$TEL" send
  [[ "$output" == *"nothing new"* ]]
  [ "$(public_requests)" -eq 0 ]
  [ "$(request_count)" -eq 0 ]
}

@test "rule 9: events recorded under an invalid policy never go to the public default" {
  say_yes
  write_policy '{'
  bash "$TEL" daily
  [ "$(jq -r .sink "$DOTFILES_TELEMETRY_STATE")" = "invalid" ]
  printf '{"task":"sync","timestamp":"%s","units":1}\n' "$NOW" >>"$DOTFILES_STATS_FILE"
  rm -f "$DOTFILES_TELEMETRY_SINK_FILE"
  run bash "$TEL" send
  [[ "$output" == *"nothing new"* ]]
  [ "$(public_requests)" -eq 0 ]
  [ "$(request_count)" -eq 0 ]
}

@test "rule 9: events recorded while off do not go to the org sink when it comes back" {
  say_yes
  hec_policy
  bash "$TEL" send >/dev/null
  write_policy '{"version":1,"kind":"off"}'
  bash "$TEL" agent-wanted >/dev/null
  printf '{"task":"sync","timestamp":"%s","units":1}\n' "$NOW" >>"$DOTFILES_STATS_FILE"
  hec_policy
  run bash "$TEL" send
  [[ "$output" == *"nothing new"* ]]
  [ "$(request_count)" -eq 0 ]
}

@test "rule 9: a run with no state file makes none, whatever the policy says" {
  write_policy '{"version":1,"kind":"off"}'
  bash "$TEL" daily
  bash "$TEL" agent-wanted >/dev/null
  [ ! -e "$DOTFILES_TELEMETRY_STATE" ]
}

@test "rule 9: no policy and an old state file with no fingerprint still send everything pending" {
  say_yes
  run bash "$TEL" send
  [[ "$output" == *"sent 2 event(s)"* ]]
  refute jq -e 'has("sink")' "$DOTFILES_TELEMETRY_STATE" >/dev/null
}

# ── Rule 10: the token is never shown ──────────────────────────────────

@test "rule 10: the token is not in status, dry-run, the log, an error line, or an argument" {
  hec_policy
  say_yes
  bash "$TEL" send >/dev/null
  printf '{"task":"sync","timestamp":"%s","units":1}\n' "$NOW" >>"$DOTFILES_STATS_FILE"
  run bash "$TEL" status
  [[ "$output" != *"$ORG_TEST_TOKEN"* ]]
  [[ "$output" == *"token: env"* ]]
  run bash "$TEL" send --dry-run
  [[ "$output" != *"$ORG_TEST_TOKEN"* ]]
  [[ "$output" == *"<token>"* ]]
  [[ "$output" == *"POST $ORG_URL"* ]]
  [[ "$output" != *"phc_"* ]]
  [ "$(request_count)" -eq 0 ]
  FAKE_CODE=500 run bash "$TEL" send
  [[ "$output" != *"$ORG_TEST_TOKEN"* ]]
  refute grep -q "$ORG_TEST_TOKEN" "$TEST_DIR/telemetry.log" "$FAKE_LOG.args" "$DOTFILES_TELEMETRY_STATE"
  # The header reached curl through a config read, not an argument.
  grep -qF "Authorization: Splunk $ORG_TEST_TOKEN" "$FAKE_LOG.config"
}

@test "rule 10: the token comes from the Keychain with the documented command, and no PostHog item is read" {
  hec_policy '.token = {keychain: {service: "org-telemetry", account: "hec_token"}}'
  printf '#!/bin/bash\necho "$*" >>"%s/security.calls"\necho keychainTok456\n' "$TEST_DIR" >"$TEST_DIR/fake-security"
  chmod +x "$TEST_DIR/fake-security"
  export DOTFILES_TELEMETRY_SECURITY="$TEST_DIR/fake-security"
  say_yes
  bash "$TEL" send >/dev/null
  printf '{"task":"sync","timestamp":"%s","units":1}\n' "$NOW" >>"$DOTFILES_STATS_FILE"
  run bash "$TEL" send
  [[ "$output" == *"sent 1 event(s)"* ]]
  grep -qF "Authorization: Splunk keychainTok456" "$FAKE_LOG.config"
  refute grep -q keychainTok456 "$FAKE_LOG.args"
  [ "$(sort -u "$TEST_DIR/security.calls")" = "find-generic-password -s org-telemetry -a hec_token -w" ]
  run bash "$TEL" status
  [[ "$output" == *"token: keychain"* ]]
  [[ "$output" != *keychainTok456* ]]
}

@test "rule 10: a token file must be a regular file that group and others cannot read" {
  printf 'fileTok789\n' >"$HOME/org-token"
  hec_policy '.token = {file: "~/org-token"}'
  say_yes
  bash "$TEL" send >/dev/null
  printf '{"task":"sync","timestamp":"%s","units":1}\n' "$NOW" >>"$DOTFILES_STATS_FILE"
  chmod 644 "$HOME/org-token"
  run bash "$TEL" send
  [[ "$output" == *"not sent (sink token unavailable"* ]]
  [ "$(request_count)" -eq 0 ]
  chmod 600 "$HOME/org-token"
  run bash "$TEL" send
  [[ "$output" == *"sent 1 event(s)"* ]]
  grep -qF "Authorization: Splunk fileTok789" "$FAKE_LOG.config"
  run bash "$TEL" status
  [[ "$output" == *"token: file"* ]]
  ln -sf "$HOME/org-token" "$HOME/org-token-link"
  hec_policy '.token = {file: "~/org-token-link"}'
  printf '{"task":"sync","timestamp":"%s","units":2}\n' "$NOW" >>"$DOTFILES_STATS_FILE"
  run bash "$TEL" send
  [[ "$output" == *"not sent (sink token unavailable"* ]]
}

@test "rule 10: a token with a space or a control character is no token" {
  hec_policy
  say_yes
  bash "$TEL" send >/dev/null
  printf '{"task":"sync","timestamp":"%s","units":1}\n' "$NOW" >>"$DOTFILES_STATS_FILE"
  ORG_TEST_TOKEN="two words" run bash "$TEL" send
  [[ "$output" == *"not sent (sink token unavailable"* ]]
  ORG_TEST_TOKEN="" run bash "$TEL" send
  [[ "$output" == *"not sent (sink token unavailable"* ]]
  [ "$(request_count)" -eq 0 ]
}

# ── Rule 11: error logs ────────────────────────────────────────────────

# err_fixture: policy with error logs on, a yes, the first send done (it sets
# the error cursors to the end of the logs), then fresh error lines.
err_fixture() {
  hec_policy '.error_logs = true'
  say_yes
  : >"$TEST_DIR/telemetry.log"
  : >"$DOTFILES_ERRORS_FILE"
  bash "$TEL" send >/dev/null
  rm -f "$FAKE_LOG" "$FAKE_LOG.args" "$FAKE_LOG.urls" "$FAKE_LOG.config"
}

@test "rule 11: new error log lines go as dotfiles.error_log events, redacted, from the fixed file list" {
  err_fixture
  printf '%s\n' "2026-11-11T10:00:00Z send failed (http 500) at $HOME/secret/dir" \
    "2026-11-11T10:00:01Z fetch https://bob:hunter2pw@host.example.com/x failed" \
    "2026-11-11T10:00:02Z Authorization Bearer abcdefghijklmnopqrstuvwxyz0123 seen" \
    "2026-11-11T10:00:03Z API_KEY=abcd1234efgh5678 leaked" >>"$TEST_DIR/telemetry.log"
  printf '{"ts":"2026-11-11T10:00:04Z","story":"US01","source":"doctor","code":"boom"}\n' >>"$DOTFILES_ERRORS_FILE"
  run bash "$TEL" send
  [[ "$output" == *"sent 5 event(s)"* ]]
  org_events | jq -e -s 'length == 5 and all(.[]; .sourcetype == "dotfiles:error_log" and .event.event == "dotfiles.error_log"
    and (.event.file == "telemetry.log" or .event.file == "errors.jsonl") and (.event.line | type) == "string")' >/dev/null
  all="$(org_events | jq -r '.event.line')"
  [[ "$all" == *"at ~/secret/dir"* ]]
  [[ "$all" != *"$HOME"* ]]
  [[ "$all" != *hunter2pw* ]]
  [[ "$all" != *abcdefghijklmnopqrstuvwxyz0123* ]]
  [[ "$all" != *abcd1234efgh5678* ]]
  [[ "$all" == *'"code":"boom"'* ]]
  [ "$(public_requests)" -eq 0 ]
}

@test "rule 11: a line is capped at 2000 characters, a send at 200 lines, and a shrunk file resets" {
  err_fixture
  head -c 5000 /dev/zero | tr '\0' 'a' >>"$TEST_DIR/telemetry.log"
  echo >>"$TEST_DIR/telemetry.log"
  run bash "$TEL" send
  [ "$(org_events | jq -r '.event.line | length')" -eq 2000 ]
  rm -f "$FAKE_LOG" "$FAKE_LOG.args" "$FAKE_LOG.urls" "$FAKE_LOG.config"
  for i in $(seq 1 250); do echo "line $i"; done >>"$TEST_DIR/telemetry.log"
  run bash "$TEL" send
  [ "$(org_events | wc -l | tr -d ' ')" -eq 200 ]
  run bash "$TEL" send
  [ "$(org_events | wc -l | tr -d ' ')" -eq 250 ]
  # The file shrank (the tool trims it): the cursor resets to the start.
  rm -f "$FAKE_LOG" "$FAKE_LOG.args" "$FAKE_LOG.urls" "$FAKE_LOG.config"
  printf 'after trim 1\nafter trim 2\n' >"$TEST_DIR/telemetry.log"
  run bash "$TEL" send
  [ "$(org_events | jq -r '.event.line' | grep -c 'after trim')" -eq 2 ]
}

@test "rule 11: with error_logs off or unset no error line is forwarded" {
  hec_policy
  say_yes
  : >"$TEST_DIR/telemetry.log"
  bash "$TEL" send >/dev/null
  printf 'oops one\n' >>"$TEST_DIR/telemetry.log"
  printf '{"task":"sync","timestamp":"%s","units":1}\n' "$NOW" >>"$DOTFILES_STATS_FILE"
  bash "$TEL" send >/dev/null
  refute grep -q 'error_log' "$FAKE_LOG"
  refute grep -q 'oops one' "$FAKE_LOG"
}

@test "rule 11: the file sink also takes error lines; the sink change keeps old lines out" {
  mkdir -p "$HOME/logs"
  printf 'old line before the policy\n' >"$TEST_DIR/telemetry.log"
  file_policy '.error_logs = true'
  say_yes
  bash "$TEL" send >/dev/null
  printf 'new line after\n' >>"$TEST_DIR/telemetry.log"
  bash "$TEL" send >/dev/null
  out="$HOME/logs/dotfiles-telemetry.jsonl"
  jq -e -s 'length == 1 and .[0].event == "dotfiles.error_log" and .[0].sourcetype == "dotfiles:error_log"
    and .[0].file == "telemetry.log" and .[0].line == "new line after"' "$out" >/dev/null
}

@test "rule 11: with no policy or kind posthog, no error log event can reach a public body" {
  say_yes
  printf 'oops one\n' >>"$TEST_DIR/telemetry.log"
  printf '{"ts":"2026-11-11T10:00:04Z","story":"US01","source":"doctor","code":"boom"}\n' >>"$DOTFILES_ERRORS_FILE"
  run bash "$TEL" send
  [ "$(public_requests)" -eq 1 ]
  refute grep -q 'error_log' "$FAKE_LOG"
  refute grep -q 'oops one' "$FAKE_LOG"
  refute grep -q 'boom' "$FAKE_LOG"
  jq -e -s 'all(.[].batch[]; .event == "dotfiles.run" or .event == "dotfiles.command")' "$FAKE_LOG" >/dev/null
  # kind posthog with error_logs true is an invalid policy, so it sends nothing.
  write_policy '{"version":1,"kind":"posthog","error_logs":true}'
  rm -f "$FAKE_LOG" "$FAKE_LOG.args" "$FAKE_LOG.urls"
  set_state '.sent = 0'
  run bash "$TEL" send
  [[ "$output" == *"sink policy invalid"* ]]
  [ "$(request_count)" -eq 0 ]
}

# ── Rule 12: names come from fixed lists ───────────────────────────────

@test "rule 12: a made-up task or command name never reaches a public or an org body" {
  printf '%s\n' "{\"task\":\"evilcanarytask\",\"timestamp\":\"$NOW\",\"units\":1,\"file\":\"evilcanaryfile\"}" >"$DOTFILES_STATS_FILE"
  printf '%s\n' "{\"command\":\"evilcanarycmd\",\"timestamp\":\"$NOW\",\"ok\":true}" >"$DOTFILES_COMMANDS_FILE"
  say_yes
  bash "$TEL" send >/dev/null
  [ "$(public_requests)" -eq 2 ]
  refute grep -q evilcanary "$FAKE_LOG"
  rm -f "$FAKE_LOG" "$FAKE_LOG.args" "$FAKE_LOG.urls"
  hec_policy
  bash "$TEL" send >/dev/null
  set_state '.sent = 0 | .sent_commands = 0'
  run bash "$TEL" send
  [[ "$output" == *"sent "* ]]
  [ "$(request_count)" -eq 2 ]
  refute grep -q evilcanary "$FAKE_LOG"
}

# ── Rule 13: status ────────────────────────────────────────────────────

@test "rule 13: status shows the sink, the consent source, error logs, and the token source" {
  hec_policy '.consent = "managed" | .error_logs = true'
  run bash "$TEL" status
  [[ "$output" == *"telemetry: on"* ]]
  [[ "$output" == *"sink: splunk-hec at splunk.example.com"* ]]
  [[ "$output" == *"consent: managed by org policy"* ]]
  [[ "$output" == *"error logs: on"* ]]
  [[ "$output" == *"token: env"* ]]
  [[ "$output" != *"$ORG_TEST_TOKEN"* ]]
  [[ "$output" != *"/services/collector"* ]]
  file_policy
  run bash "$TEL" status
  [[ "$output" == *"sink: file ~/logs/dotfiles-telemetry.jsonl"* ]]
  [[ "$output" == *"error logs: off"* ]]
  [[ "$output" != *"$HOME"* ]]
}

# ── Rule 14: the LaunchAgent follows the policy ────────────────────────

@test "rule 14: agent-wanted: managed is yes unless a stored no; off and invalid are no" {
  run bash "$TEL" agent-wanted
  [ "$output" = "no" ]
  hec_policy
  run bash "$TEL" agent-wanted
  [ "$output" = "no" ]
  hec_policy '.consent = "managed"'
  run bash "$TEL" agent-wanted
  [ "$output" = "yes" ]
  [ ! -e "$DOTFILES_TELEMETRY_STATE" ]
  bash "$TEL" off >/dev/null
  run bash "$TEL" agent-wanted
  [ "$output" = "no" ]
  bash "$TEL" on >/dev/null
  run bash "$TEL" agent-wanted
  [ "$output" = "yes" ]
  write_policy '{"version":1,"kind":"off"}'
  run bash "$TEL" agent-wanted
  [ "$output" = "no" ]
  hec_policy '.version = 3'
  run bash "$TEL" agent-wanted
  [ "$output" = "no" ]
}

@test "rule 14: the apply script installs the agent for managed, and skips it for off or invalid" {
  apply="$REPO/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
  eval "$(sed -n '/^should_skip_agent() {/,/^}/p' "$apply")"
  SOURCE_DIR="$REPO"
  PROFILE=full
  should_skip_agent telemetry # no policy, nobody answered
  hec_policy '.consent = "managed"'
  refute should_skip_agent telemetry
  bash "$TEL" off >/dev/null
  should_skip_agent telemetry
  bash "$TEL" on >/dev/null
  refute should_skip_agent telemetry
  write_policy '{"version":1,"kind":"off"}'
  should_skip_agent telemetry
  hec_policy '.version = 3'
  should_skip_agent telemetry
}

@test "rule 14: telemetry on loads the agent for a managed sink and removes it for off or invalid" {
  cat >"$TEST_DIR/fake-launchctl" <<SH
#!/bin/bash
printf '%s\\n' "\$*" >>"$TEST_DIR/launchctl.log"
case "\$1" in
  print) [ -e "$TEST_DIR/agent-loaded" ] ;;
  bootout) rm -f "$TEST_DIR/agent-loaded" ;;
  bootstrap) : >"$TEST_DIR/agent-loaded" ;;
esac
SH
  printf '#!/bin/bash\n[ "$1" = "execute-template" ] || exit 1\ncat\n' >"$TEST_DIR/fake-chezmoi"
  chmod +x "$TEST_DIR/fake-launchctl" "$TEST_DIR/fake-chezmoi"
  export DOTFILES_TELEMETRY_LAUNCHCTL="$TEST_DIR/fake-launchctl" DOTFILES_TELEMETRY_CHEZMOI="$TEST_DIR/fake-chezmoi"
  PLIST="$HOME/Library/LaunchAgents/com.dotfiles.telemetry.plist"
  hec_policy '.consent = "managed"'
  bash "$TEL" on >/dev/null
  [ -s "$PLIST" ]
  write_policy '{"version":1,"kind":"off"}'
  bash "$TEL" on >/dev/null
  [ ! -e "$PLIST" ]
  hec_policy '.consent = "managed"'
  bash "$TEL" on >/dev/null
  [ -s "$PLIST" ]
  hec_policy '.consent = "managed" | .version = 5'
  bash "$TEL" on >/dev/null
  [ ! -e "$PLIST" ]
  hec_policy '.consent = "managed"'
  bash "$TEL" on >/dev/null
  bash "$TEL" off >/dev/null
  [ ! -e "$PLIST" ]
}

@test "rule 14: the daily send follows the same rules: managed sends, off and invalid do not" {
  hec_policy '.consent = "managed"'
  bash "$TEL" send >/dev/null
  printf '{"task":"sync","timestamp":"%s","units":1}\n' "$NOW" >>"$DOTFILES_STATS_FILE"
  set_state '.last_try = 0'
  bash "$TEL" daily
  [ "$(request_count)" -eq 1 ]
  [ "$(public_requests)" -eq 0 ]
  set_state '.last_send = "" | .last_try = 0'
  printf '{"task":"sync","timestamp":"%s","units":2}\n' "$NOW" >>"$DOTFILES_STATS_FILE"
  write_policy '{"version":1,"kind":"off"}'
  bash "$TEL" daily
  hec_policy '.consent = "managed" | .version = 2'
  bash "$TEL" daily
  [ "$(request_count)" -eq 1 ]
}
