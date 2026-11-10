#!/usr/bin/env bats
# Tests for the gain numbers of bin/dotfiles-telemetry: seconds_saved on
# dotfiles.run, and the dotfiles.install and dotfiles.gains events built from
# the install receipt. No test sends anything real: a fake curl records the
# request instead.

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME"
  export DOTFILES_STATS_FILE="$TEST_DIR/stats.jsonl"
  export DOTFILES_COMMANDS_FILE="$TEST_DIR/commands.jsonl"
  export DOTFILES_TELEMETRY_STATE="$TEST_DIR/telemetry.json"
  export DOTFILES_INSTALL_RECEIPT="$TEST_DIR/install-receipt.json"
  export DOTFILES_TELEMETRY_URL="http://127.0.0.1:9/fake"
  export DOTFILES_TELEMETRY_KEY_FILE="$TEST_DIR/key"
  export DOTFILES_POSTHOG_KEY="phc_testFakeKey1"
  unset DO_NOT_TRACK CI DOTFILES_TELEMETRY DOTFILES_TELEMETRY_TTY
  : >"$DOTFILES_TELEMETRY_KEY_FILE"
  FAKE="$TEST_DIR/fake-curl"
  cat >"$FAKE" <<'SH'
#!/bin/bash
cat >>"${FAKE_LOG:?}"
echo >>"$FAKE_LOG"
printf '%s' "${FAKE_CODE:-200}"
SH
  chmod +x "$FAKE"
  export DOTFILES_TELEMETRY_CURL="$FAKE" FAKE_LOG="$TEST_DIR/requests.log"
  TEL="$REPO/bin/dotfiles-telemetry"
  NOW="$(date -u +%FT%TZ)"
  TODAY="$(date -u +%F)"
  : >"$DOTFILES_STATS_FILE"
  # The receipt events need a yes on or after the day they shipped. The tests
  # use older days, so they move that day back (a seam for tests only).
  export DOTFILES_TELEMETRY_TEST_GAINS_SINCE="2000-01-01"
  # A fake zsh, first on PATH: the send times it for zsh_ms_now. It logs each
  # start; FAKE_ZSH_SLEEP and FAKE_ZSH_EXIT make it slow or make it fail.
  mkdir -p "$TEST_DIR/bin"
  cat >"$TEST_DIR/bin/zsh" <<SH
#!/bin/bash
echo start >>"$TEST_DIR/zsh.log"
echo "\$\$" >"$TEST_DIR/zsh.pid"
[ -z "\${FAKE_ZSH_DEAF:-}" ] || trap '' TERM
[ -z "\${FAKE_ZSH_SLEEP:-}" ] || exec sleep "\$FAKE_ZSH_SLEEP"
exit "\${FAKE_ZSH_EXIT:-0}"
SH
  chmod +x "$TEST_DIR/bin/zsh"
  export PATH="$TEST_DIR/bin:$PATH" DOTFILES_BASELINE_ZSH_RUNS=1
  unset FAKE_ZSH_SLEEP FAKE_ZSH_EXIT FAKE_ZSH_DEAF
}
refute() { if "$@" 2>/dev/null; then return 1; fi; }
zsh_starts() { if [ -f "$TEST_DIR/zsh.log" ]; then wc -l <"$TEST_DIR/zsh.log" | tr -d ' '; else echo 0; fi; }

teardown() { rm -rf "$TEST_DIR"; }

days_ago() { date -u -v-"$1"d +%FT%TZ 2>/dev/null || date -u -d "$1 days ago" +%FT%TZ; }
set_state() { jq -c "$1" "$DOTFILES_TELEMETRY_STATE" >"$TEST_DIR/state.new" && mv "$TEST_DIR/state.new" "$DOTFILES_TELEMETRY_STATE"; }
# say_yes [DAY]: a stored yes, given on DAY (default: 40 days ago, so a
# receipt and a sample that a test seeds count as recorded after the yes).
say_yes() {
  local day="${1:-$(days_ago 40)}"
  bash "$TEL" on >/dev/null
  set_state ".sent = 0 | .sent_commands = 0 | .consent_at = \"${day:0:10}\""
}
# receipt [FINISHED_AT] [TAKEN_AT]: a receipt as lib/mac-baseline.sh writes it.
receipt() {
  local finished="${1:-$NOW}" taken="${2:-$(days_ago 12)}"
  printf '{"profile":"core","before":{"taken_at":"%s","zsh_ms":412,"free_gb":88.1,"launchagents":3,"claude_permissions":"default"},"run":{"started_at":"%s","finished_at":"%s","seconds":754,"ok":true}}\n' \
    "$taken" "$taken" "$finished" >"$DOTFILES_INSTALL_RECEIPT"
}
shell_sample() { printf '{"task":"shell-start","timestamp":"%s","seconds_saved":0,"units":1,"ok":true,"duration_ms":%s}\n' "$1" "$2" >>"$DOTFILES_STATS_FILE"; }
# Every event named $1 in the requests the fake curl got, as a JSON array.
sent_events() {
  if [ -f "$FAKE_LOG" ]; then jq -s -c --arg event "$1" '[.[].batch[] | select(.event == $event)]' "$FAKE_LOG"; else echo '[]'; fi
}
# Every event named $1 in a `send --dry-run` output, as a JSON array.
dry_events() {
  bash "$TEL" send --dry-run | grep -v -e '^POST ' -e '^dry run:' |
    jq -s -c --arg event "$1" '[.[].batch[] | select(.event == $event)]'
}

@test "dotfiles.run carries seconds_saved as a whole number" {
  printf '%s\n' \
    "{\"task\":\"cleanup\",\"timestamp\":\"$NOW\",\"seconds_saved\":50,\"units\":5,\"ok\":true}" \
    "{\"task\":\"sync\",\"timestamp\":\"$NOW\",\"seconds_saved\":3.7,\"units\":1,\"ok\":true}" \
    "{\"task\":\"audit\",\"timestamp\":\"$NOW\",\"seconds_saved\":\"$HOME/canary\",\"units\":1,\"ok\":true}" \
    >"$DOTFILES_STATS_FILE"
  say_yes
  run dry_events dotfiles.run
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.[].properties.seconds_saved]' <<<"$output")" = "[50,3,null]" ] || { echo "$output"; return 1; }
  [[ "$output" != *canary* ]]
}

@test "the install event carries seconds, ok, profile, the common properties, and the install end time" {
  receipt
  say_yes
  bash "$TEL" send
  run sent_events dotfiles.install
  [ "$(jq 'length' <<<"$output")" = "1" ] || { echo "$output"; return 1; }
  [ "$(jq -c '.[0].properties | [.seconds, .ok, .profile, .runtime, .["$geoip_disable"], .["$process_person_profile"]]' <<<"$output")" = '[754,true,"core","shell",true,false]' ] || { echo "$output"; return 1; }
  [ "$(jq -r '.[0].timestamp' <<<"$output")" = "$NOW" ]
  [ "$(jq -r '.[0].distinct_id' <<<"$output")" = "$(jq -r .install_id "$DOTFILES_TELEMETRY_STATE")" ]
  # Only the fields on the list: nothing else from the receipt.
  [ "$(jq -c '.[0].properties | keys' <<<"$output")" = '["$geoip_disable","$process_person_profile","app_version","arch","ok","os","profile","runtime","seconds"]' ] || { echo "$output"; return 1; }
}

@test "the gains event carries zsh_ms_before, zsh_ms_now, and days_since_install" {
  receipt
  # A stored shell-start sample is never the now value: the send measures it.
  shell_sample "$NOW" 99999
  say_yes
  bash "$TEL" send
  run sent_events dotfiles.gains
  [ "$(jq 'length' <<<"$output")" = "1" ] || { echo "$output"; return 1; }
  [ "$(jq -c '.[0].properties | [.zsh_ms_before, .days_since_install]' <<<"$output")" = "[412,12]" ] || { echo "$output"; return 1; }
  [ "$(jq -c '.[0].properties.zsh_ms_now | type == "number" and . >= 1 and . < 5000 and . == floor' <<<"$output")" = "true" ] || { echo "$output"; return 1; }
  [ "$(jq -c '.[0].properties | keys' <<<"$output")" = '["$geoip_disable","$process_person_profile","app_version","arch","days_since_install","os","runtime","zsh_ms_before","zsh_ms_now"]' ] || { echo "$output"; return 1; }
}

@test "zsh_ms_now is measured with the method of the receipt: one timed zsh start per send" {
  receipt
  say_yes
  # status and the consent text start no zsh.
  bash "$TEL" status >/dev/null
  bash "$TEL" example >/dev/null
  [ "$(zsh_starts)" = "0" ]
  # A dry run measures once.
  bash "$TEL" send --dry-run >/dev/null
  [ "$(zsh_starts)" = "1" ] || { echo "starts: $(zsh_starts)"; return 1; }
  bash "$TEL" send
  [ "$(zsh_starts)" = "2" ]
  # Nothing is due on the same day: no measurement.
  bash "$TEL" send
  bash "$TEL" send --dry-run >/dev/null
  [ "$(zsh_starts)" = "2" ]
  # It is the helper of the install receipt (lib/mac-baseline.sh).
  grep -q 'baseline_zsh_ms' "$TEL"
}

@test "a hung zsh that ignores SIGTERM, like a real interactive zsh, is still stopped" {
  receipt
  say_yes
  FAKE_ZSH_DEAF=1 FAKE_ZSH_SLEEP=90 run bash "$TEL" send
  refute kill -0 "$(cat "$TEST_DIR/zsh.pid")"
  [[ "$output" == *"sent 2 event(s)"* ]] || { echo "$output"; return 1; }
}

@test "telemetry off during the shell start measurement stops the send" {
  receipt
  say_yes
  # The fake zsh records a no while the send measures it.
  cat >"$TEST_DIR/bin/zsh" <<SH
#!/bin/bash
bash "$TEL" off >/dev/null 2>&1
exit 0
SH
  run bash "$TEL" send
  [ "$(sent_events dotfiles.gains | jq length)" = "0" ] || { cat "$FAKE_LOG"; return 1; }
  [ "$(sent_events dotfiles.install | jq length)" = "0" ] || { cat "$FAKE_LOG"; return 1; }
}

@test "a zsh that fails or takes over 5 seconds leaves zsh_ms_now out; the send still works" {
  receipt
  say_yes
  FAKE_ZSH_EXIT=1 bash "$TEL" send
  run sent_events dotfiles.gains
  [ "$(jq -c '.[0].properties | [has("zsh_ms_now"), .zsh_ms_before]' <<<"$output")" = "[false,412]" ] || { echo "$output"; return 1; }
  [ "$(zsh_starts)" = "1" ]
  rm -f "$FAKE_LOG"
  set_state '.gains_day = "" | .last_send = ""'
  # The slow zsh is stopped at the limit: the send does not wait for it.
  # (The time bound is loose: the test queue can pause a run.)
  SECONDS=0
  FAKE_ZSH_SLEEP=90 run bash "$TEL" send
  [ "$SECONDS" -lt 80 ] || { echo "took $SECONDS s"; return 1; }
  refute kill -0 "$(cat "$TEST_DIR/zsh.pid")"
  [[ "$output" == *"sent 1 event(s)"* ]] || { echo "$output"; return 1; }
  run sent_events dotfiles.gains
  [ "$(jq -c '.[0].properties | [has("zsh_ms_now"), .zsh_ms_before]' <<<"$output")" = "[false,412]" ] || { echo "$output"; return 1; }
  # The daily path has its own short limit; the measurement does not use it up.
  rm -f "$FAKE_LOG"
  set_state '.gains_day = "" | .last_send = "" | .last_try = 0 | .try_hour = ""'
  FAKE_ZSH_SLEEP=90 bash "$TEL" daily
  refute kill -0 "$(cat "$TEST_DIR/zsh.pid")"
  [ "$(sent_events dotfiles.gains | jq length)" = "1" ] || { cat "$FAKE_LOG"; return 1; }
}

@test "a receipt day that is not a real date drops only its own event" {
  # A bad before day: the install event still goes, and no gains event.
  receipt "$NOW" "2026-13-45T99:99:99Z"
  say_yes
  run bash "$TEL" status
  [[ "$output" == *"pending: 1 event(s)"* ]] || { echo "$output"; return 1; }
  run bash "$TEL" send
  [[ "$output" == *"sent 1 event(s)"* ]] || { echo "$output"; return 1; }
  [ "$(sent_events dotfiles.install | jq length)" = "1" ]
  [ "$(sent_events dotfiles.gains)" = "[]" ]
  [ "$(jq -r .install_sent "$DOTFILES_TELEMETRY_STATE")" = "$NOW" ]
  [ "$(jq -r .gains_day "$DOTFILES_TELEMETRY_STATE")" = "" ]
  # A bad end time: no install event and no cursor move; gains still goes.
  rm -f "$FAKE_LOG"
  receipt "2999-13-45T99:99:99Z"
  set_state '.install_sent = "" | .last_send = ""'
  run bash "$TEL" send
  [[ "$output" == *"sent 1 event(s)"* ]] || { echo "$output"; return 1; }
  [ "$(sent_events dotfiles.install)" = "[]" ] || { cat "$FAKE_LOG"; return 1; }
  [ "$(sent_events dotfiles.gains | jq length)" = "1" ]
  [ "$(jq -r .install_sent "$DOTFILES_TELEMETRY_STATE")" = "" ]
  [ "$(jq -r .gains_day "$DOTFILES_TELEMETRY_STATE")" = "$TODAY" ]
}

@test "an install older than the 30-day cap is never sent" {
  receipt "$(days_ago 31)" "$(days_ago 31)"
  say_yes "$(days_ago 40)"
  run bash "$TEL" send --dry-run
  [[ "$output" != *dotfiles.install* ]] || { echo "$output"; return 1; }
  [[ "$output" == *dotfiles.gains* ]]
  run bash "$TEL" status
  [[ "$output" == *"pending: 1 event(s)"* ]] || { echo "$output"; return 1; }
  bash "$TEL" send
  [ "$(sent_events dotfiles.install)" = "[]" ]
  [ "$(jq -r .install_sent "$DOTFILES_TELEMETRY_STATE")" = "" ]
  # Inside the cap it is sent.
  receipt "$(days_ago 29)" "$(days_ago 31)"
  set_state '.last_send = ""'
  bash "$TEL" send
  [ "$(sent_events dotfiles.install | jq length)" = "1" ]
}

@test "a yes from before the day these events shipped does not cover them; a new yes does" {
  unset DOTFILES_TELEMETRY_TEST_GAINS_SINCE
  grep -q '^GAINS_SINCE="2026-11-10"' "$TEL"
  receipt
  printf '%s\n' "{\"task\":\"sync\",\"timestamp\":\"$NOW\",\"seconds_saved\":3,\"units\":1}" >"$DOTFILES_STATS_FILE"
  say_yes "2026-11-09"
  run bash "$TEL" send --dry-run
  [[ "$output" == *dotfiles.run* ]] || { echo "$output"; return 1; }
  [[ "$output" != *dotfiles.install* ]] && [[ "$output" != *dotfiles.gains* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"1 event(s) pending"* ]]
  bash "$TEL" send
  [ "$(sent_events dotfiles.install)$(sent_events dotfiles.gains)" = "[][]" ]
  [ "$(sent_events dotfiles.run | jq length)" = "1" ]
  # A yes on the ship day covers them.
  set_state '.consent_at = "2026-11-10"'
  run bash "$TEL" status
  [[ "$output" == *"pending: 2 event(s)"* ]] || { echo "$output"; return 1; }
  # `telemetry on` again is a new yes: it records today as the day.
  set_state '.consent_at = "2026-11-09"'
  bash "$TEL" on >/dev/null
  [ "$(jq -r .consent_at "$DOTFILES_TELEMETRY_STATE")" = "$TODAY" ]
  bash "$TEL" send
  [ "$(sent_events dotfiles.install | jq length)" = "1" ]
  [ "$(sent_events dotfiles.gains | jq length)" = "1" ]
}

@test "a receipt over 64 KB is skipped" {
  receipt
  jq -c --arg pad "$(head -c 70000 /dev/zero | tr '\0' 'x')" '.pad = $pad' "$DOTFILES_INSTALL_RECEIPT" >"$TEST_DIR/r" && mv "$TEST_DIR/r" "$DOTFILES_INSTALL_RECEIPT"
  say_yes
  run bash "$TEL" send --dry-run
  [[ "$output" != *dotfiles.install* ]] && [[ "$output" != *dotfiles.gains* ]] || { echo "${output:0:600}"; return 1; }
  [[ "$output" == *"0 event(s) pending"* ]]
  run bash "$TEL" send
  [ ! -e "$FAKE_LOG" ]
  [ "$(zsh_starts)" = "0" ]
}

@test "with no receipt there is no install event and no gains event" {
  printf '%s\n' "{\"task\":\"sync\",\"timestamp\":\"$NOW\",\"seconds_saved\":3,\"units\":1}" >"$DOTFILES_STATS_FILE"
  shell_sample "$NOW" 120
  say_yes
  run bash "$TEL" send --dry-run
  [[ "$output" != *dotfiles.install* ]] && [[ "$output" != *dotfiles.gains* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"2 event(s) pending"* ]] || { echo "$output"; return 1; }
  bash "$TEL" send
  [ "$(sent_events dotfiles.install)" = "[]" ]
  [ "$(sent_events dotfiles.gains)" = "[]" ]
  [ "$(sent_events dotfiles.run | jq length)" = "2" ]
}

@test "a profile outside the fixed list is dropped" {
  receipt
  jq -c '.profile = "team-acme"' "$DOTFILES_INSTALL_RECEIPT" >"$TEST_DIR/r" && mv "$TEST_DIR/r" "$DOTFILES_INSTALL_RECEIPT"
  say_yes
  run dry_events dotfiles.install
  [ "$(jq -c '.[0].properties | [has("profile"), .seconds]' <<<"$output")" = "[false,754]" ] || { echo "$output"; return 1; }
  [[ "$output" != *acme* ]]
  jq -c '.profile = "full"' "$DOTFILES_INSTALL_RECEIPT" >"$TEST_DIR/r" && mv "$TEST_DIR/r" "$DOTFILES_INSTALL_RECEIPT"
  run dry_events dotfiles.install
  [ "$(jq -r '.[0].properties.profile' <<<"$output")" = "full" ]
}

@test "the install event is sent once per receipt; a new install run sends a new one" {
  first="$(days_ago 1)"
  receipt "$first"
  say_yes
  bash "$TEL" send
  bash "$TEL" send
  set_state '.gains_day = "" | .last_send = ""'
  bash "$TEL" send
  [ "$(sent_events dotfiles.install | jq length)" = "1" ] || { cat "$FAKE_LOG"; return 1; }
  [ "$(jq -r .install_sent "$DOTFILES_TELEMETRY_STATE")" = "$first" ]
  receipt "$NOW"
  bash "$TEL" send
  [ "$(sent_events dotfiles.install | jq length)" = "2" ]
}

@test "the install cursor moves only after the endpoint answers 2xx" {
  receipt
  say_yes
  FAKE_CODE=500 run bash "$TEL" send
  [[ "$output" == *"send failed (http 500)"* ]] || { echo "$output"; return 1; }
  [ "$(jq -r '.install_sent + .gains_day' "$DOTFILES_TELEMETRY_STATE")" = "" ]
  run bash "$TEL" status
  [[ "$output" == *"pending: 2 event(s)"* ]] || { echo "$output"; return 1; }
  bash "$TEL" send
  [ "$(jq -r .install_sent "$DOTFILES_TELEMETRY_STATE")" = "$NOW" ]
  [ "$(jq -r .gains_day "$DOTFILES_TELEMETRY_STATE")" = "$TODAY" ]
}

@test "gains is sent at most once a day, also through the daily path" {
  receipt
  say_yes
  bash "$TEL" send
  bash "$TEL" send
  set_state '.last_send = "" | .last_try = 0 | .try_hour = ""'
  bash "$TEL" daily
  [ "$(sent_events dotfiles.gains | jq length)" = "1" ] || { cat "$FAKE_LOG"; return 1; }
  # The next day it is due again, and the daily path sends it.
  set_state '.gains_day = "2001-01-01" | .last_send = "2001-01-01" | .last_try = 0 | .try_hour = ""'
  bash "$TEL" daily
  [ "$(sent_events dotfiles.gains | jq length)" = "2" ] || { cat "$FAKE_LOG"; return 1; }
  [ "$(sent_events dotfiles.install | jq length)" = "1" ]
}

@test "an install that finished before the day of the yes is never sent" {
  receipt "$(days_ago 5)"
  say_yes "$(days_ago 2)"
  run bash "$TEL" send --dry-run
  [[ "$output" != *dotfiles.install* ]] || { echo "$output"; return 1; }
  bash "$TEL" send
  [ "$(sent_events dotfiles.install)" = "[]" ]
  # An install on the day of the yes is sent.
  receipt "$(days_ago 2)"
  set_state '.last_send = ""'
  bash "$TEL" send
  [ "$(sent_events dotfiles.install | jq length)" = "1" ]
}

@test "no receipt event without a yes, with CI set, or with an opt-out variable" {
  receipt
  printf '%s\n' "{\"task\":\"sync\",\"timestamp\":\"$NOW\",\"seconds_saved\":3,\"units\":1}" >"$DOTFILES_STATS_FILE"
  no_receipt_events() {
    run "$@" bash "$TEL" send --dry-run
    [[ "$output" == *dotfiles.run* ]] || { echo "$*: $output"; return 1; }
    [[ "$output" != *dotfiles.install* ]] && [[ "$output" != *dotfiles.gains* ]] || { echo "$*: $output"; return 1; }
    [[ "$output" == *"1 event(s) pending"* ]] || { echo "$*: $output"; return 1; }
    run "$@" bash "$TEL" status
    [[ "$output" == *"pending: 1 event(s)"* ]] || { echo "$*: $output"; return 1; }
  }
  # No answer yet.
  no_receipt_events env
  bash "$TEL" send
  say_yes
  # A stored yes, and each run-time switch.
  no_receipt_events env CI=true
  no_receipt_events env DO_NOT_TRACK=1
  no_receipt_events env DOTFILES_TELEMETRY=0
  CI=true bash "$TEL" send
  DO_NOT_TRACK=1 bash "$TEL" send
  DOTFILES_TELEMETRY=0 bash "$TEL" send
  bash "$TEL" off >/dev/null
  no_receipt_events env
  bash "$TEL" send
  [ ! -e "$FAKE_LOG" ]
  [ "$(zsh_starts)" = "0" ]
}

@test "a hostile receipt value never reaches the body" {
  cat >"$DOTFILES_INSTALL_RECEIPT" <<JSON
{"profile":"$HOME/canary-profile","host":"canary-host.local","user":"canary-user",
 "before":{"taken_at":"$(days_ago 3)","zsh_ms":"$HOME/canary-zsh","free_gb":"canary-disk","claude_permissions":"canary-mode"},
 "run":{"started_at":"canary-start","finished_at":"$NOW","seconds":"/tmp/canary-seconds","ok":"canary-ok","failed_step":"canary step text"}}
JSON
  say_yes
  run bash "$TEL" send --dry-run
  [[ "$output" == *dotfiles.install* ]] && [[ "$output" == *dotfiles.gains* ]] || { echo "$output"; return 1; }
  [[ "$output" != *canary* ]] && [[ "$output" != *"$HOME"* ]] && [[ "$output" != */tmp/* ]] || { echo "$output"; return 1; }
  bash "$TEL" send
  refute_in_body() { ! grep -q -e canary -e "$HOME" -e /tmp/ "$FAKE_LOG"; }
  refute_in_body || { cat "$FAKE_LOG"; return 1; }
  [ "$(sent_events dotfiles.install | jq -c '.[0].properties | [has("seconds"), has("ok"), has("profile")]')" = "[false,false,false]" ]
  [ "$(sent_events dotfiles.gains | jq -c '.[0].properties | [has("zsh_ms_before"), (.zsh_ms_now | type == "number"), .days_since_install]')" = "[false,true,3]" ]
  # A number that is negative, huge, or an array is dropped. A fraction
  # leaves as a whole number, and a negative zero leaves as 0.
  hostile_numbers() {
    printf '{"profile":"core","before":{"taken_at":"%s","zsh_ms":%s},"run":{"finished_at":"%s","seconds":%s,"ok":true}}\n' \
      "$(days_ago 3)" "$2" "$NOW" "$1" >"$DOTFILES_INSTALL_RECEIPT"
    bash "$TEL" send --dry-run | grep -v -e '^POST ' -e '^dry run:' |
      jq -s -c '[.[].batch[] | select(.event != "dotfiles.run")] | [.[0].properties.seconds, .[1].properties.zsh_ms_before]'
  }
  set_state '.gains_day = "" | .install_sent = "" | .last_send = ""'
  [ "$(hostile_numbers -5 -412)" = "[null,null]" ]
  [ "$(hostile_numbers 1e300 1000000000)" = "[null,null]" ]
  [ "$(hostile_numbers '[754]' '{"ms":412}')" = "[null,null]" ]
  [ "$(hostile_numbers 754.9 412.2)" = "[754,412]" ]
  [ "$(hostile_numbers 999999999 0)" = "[999999999,0]" ]
  run hostile_numbers -0.0 -0.3e-9
  [ "$output" = "[0,null]" ] || { echo "$output"; return 1; }
  printf '{"profile":"core","before":{"taken_at":"%s","zsh_ms":-0.0},"run":{"finished_at":"%s","seconds":-0.0,"ok":true}}\n' "$(days_ago 3)" "$NOW" >"$DOTFILES_INSTALL_RECEIPT"
  printf '{"task":"sync","timestamp":"%s","seconds_saved":-0.0,"units":1}\n' "$NOW" >"$DOTFILES_STATS_FILE"
  set_state '.sent = 0'
  run bash "$TEL" send --dry-run
  [[ "$output" == *'"seconds": 0'* ]] && [[ "$output" == *'"zsh_ms_before": 0'* ]] && [[ "$output" == *'"seconds_saved": 0'* ]] || { echo "$output"; return 1; }
  [[ "$output" != *': -0'* ]] || { echo "$output"; return 1; }
  : >"$DOTFILES_STATS_FILE"
  set_state '.sent = 0'
  # A receipt time that is not a UTC timestamp sends no event at all.
  rm -f "$FAKE_LOG"
  printf '{"profile":"core","before":{"taken_at":"%s/canary","zsh_ms":400},"run":{"finished_at":"canary-end","seconds":5,"ok":true}}\n' "$HOME" >"$DOTFILES_INSTALL_RECEIPT"
  set_state '.gains_day = "" | .install_sent = "" | .last_send = ""'
  run bash "$TEL" send --dry-run
  [[ "$output" != *canary* ]] && [[ "$output" != *dotfiles.install* ]] && [[ "$output" != *dotfiles.gains* ]] || { echo "$output"; return 1; }
  # A receipt that is not JSON at all sends nothing and breaks nothing.
  printf 'canary not json\n' >"$DOTFILES_INSTALL_RECEIPT"
  run bash "$TEL" send
  [ "$status" -eq 0 ]
  [ ! -e "$FAKE_LOG" ]
}

@test "send --dry-run prints the install and gains events, hides the key, and changes nothing" {
  receipt
  shell_sample "$NOW" 120
  say_yes
  before="$(cat "$DOTFILES_TELEMETRY_STATE")"
  run bash "$TEL" send --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'"event": "dotfiles.install"'* ]] || { echo "$output"; return 1; }
  [[ "$output" == *'"event": "dotfiles.gains"'* ]]
  [[ "$output" == *'"api_key": "<posthog_key>"'* ]]
  [[ "$output" != *phc_* ]]
  # One shell-start line in the stats log, plus the install and gains events.
  [[ "$output" == *"3 event(s) pending"* ]] || { echo "$output"; return 1; }
  [ "$(cat "$DOTFILES_TELEMETRY_STATE")" = "$before" ]
  [ ! -e "$FAKE_LOG" ]
}

@test "status counts the install and gains events as pending until they are sent" {
  receipt
  say_yes
  run bash "$TEL" status
  [[ "$output" == *"pending: 2 event(s)"* ]] || { echo "$output"; return 1; }
  run bash "$TEL" send
  [[ "$output" == *"sent 2 event(s)"* ]] || { echo "$output"; return 1; }
  run bash "$TEL" status
  [[ "$output" == *"pending: 0 event(s)"* ]] || { echo "$output"; return 1; }
}

@test "the consent text names the install and gains numbers and the baseline from before the yes" {
  run bash "$TEL" example
  [[ "$output" == *"how long the install took"* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"shell start time"*"before the install and now"* ]]
  [[ "$output" == *"baseline, measured before your yes"* ]]
  [[ "$output" == *"The maintainer reads the totals and averages"* ]]
  [[ "$output" != *"public"* ]]
}

@test "a state file from before these events loads, and an invalid cursor value is unset" {
  receipt
  say_yes
  set_state 'del(.install_sent, .gains_day)'
  run bash "$TEL" status
  [[ "$output" == *"pending: 2 event(s)"* ]] || { echo "$output"; return 1; }
  set_state ".install_sent = \"$HOME/canary\" | .gains_day = 7"
  bash "$TEL" send
  [ "$(jq -r .install_sent "$DOTFILES_TELEMETRY_STATE")" = "$NOW" ]
  [ "$(jq -r .gains_day "$DOTFILES_TELEMETRY_STATE")" = "$TODAY" ]
  [ "$(jq -r .consent "$DOTFILES_TELEMETRY_STATE")" = "yes" ]
}
