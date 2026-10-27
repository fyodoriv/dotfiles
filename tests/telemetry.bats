#!/usr/bin/env bats
# Tests for bin/dotfiles-telemetry: opt-in usage counts to PostHog EU.
# No test sends anything real: a fake curl records the request instead.

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME"
  export DOTFILES_STATS_FILE="$TEST_DIR/stats.jsonl"
  export DOTFILES_TELEMETRY_STATE="$TEST_DIR/telemetry.json"
  export DOTFILES_TELEMETRY_URL="http://127.0.0.1:9/fake"
  export DOTFILES_POSTHOG_KEY="phc_test_fake_key"
  unset DO_NOT_TRACK
  FAKE="$TEST_DIR/fake-curl"
  cat >"$FAKE" <<'SH'
#!/bin/bash
cat >>"${FAKE_LOG:?}"
echo >>"$FAKE_LOG"
printf '%s' "${FAKE_CODE:-200}"
SH
  chmod +x "$FAKE"
  export DOTFILES_TELEMETRY_CURL="$FAKE" FAKE_LOG="$TEST_DIR/requests.log"
  TEL="$BATS_TEST_DIRNAME/../bin/dotfiles-telemetry"
  printf '%s\n' \
    '{"task":"sync","timestamp":"2026-10-26T10:00:00Z","seconds_saved":3,"units":1}' \
    '{"task":"doctor","timestamp":"2026-10-26T11:00:00Z","seconds_saved":2,"units":1,"pass":40,"fail":1,"path":"canary-dir/secret.txt","message":"canary text"}' \
    >"$DOTFILES_STATS_FILE"
}

@test "send --dry-run prints only allowlisted fields and hides the key" {
  run bash "$TEL" send --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *'"api_key": "<posthog_key>"'* ]]
  [[ "$output" == *'"task": "doctor"'* ]]
  # shellcheck disable=SC2016 # literal $ in the expected JSON key
  [[ "$output" == *'"$process_person_profile": false'* ]]
  # shellcheck disable=SC2016 # literal $ in the expected JSON key
  [[ "$output" == *'"$geoip_disable": true'* ]]
  [[ "$output" != *canary* ]]
  [[ "$output" != *phc_test* ]]
  [ ! -f "$FAKE_LOG" ]
}

@test "send posts the pending events once, then nothing new" {
  run bash "$TEL" send
  [ "$status" -eq 0 ]
  [[ "$output" == *"sent 2 event(s)"* ]]
  [ "$(jq -s 'length' "$FAKE_LOG")" -eq 1 ]
  [ "$(jq -s '.[0].batch | length' "$FAKE_LOG")" -eq 2 ]
  run grep -q canary "$FAKE_LOG"
  [ "$status" -ne 0 ]
  run bash "$TEL" send
  [[ "$output" == *"nothing new"* ]]
  [ "$(jq -s 'length' "$FAKE_LOG")" -eq 1 ]
}

@test "no key sends nothing" {
  export DOTFILES_POSTHOG_KEY=""
  run bash "$TEL" send
  [[ "$output" == *"no key"* ]]
  [ ! -f "$FAKE_LOG" ]
}

@test "DO_NOT_TRACK and telemetry off send nothing" {
  DO_NOT_TRACK=1 run bash "$TEL" send
  [[ "$output" == *"DO_NOT_TRACK"* ]]
  bash "$TEL" off
  run bash "$TEL" send
  [[ "$output" == *"turned off"* ]]
  [ ! -f "$FAKE_LOG" ]
  run bash "$TEL" status
  [[ "$output" == *"telemetry: off"* ]]
}

@test "a failed send keeps the cursor and never fails" {
  FAKE_CODE=500 run bash "$TEL" send
  [ "$status" -eq 0 ]
  [[ "$output" == *"send failed"* ]]
  [ "$(jq -r .sent "$DOTFILES_TELEMETRY_STATE")" = "0" ]
}

@test "daily sends only after the notice, and once a day" {
  bash "$TEL" daily
  [ ! -f "$FAKE_LOG" ]
  run bash "$TEL" notice
  [[ "$output" == *"anonymous usage counts"* ]]
  run bash "$TEL" notice
  [ -z "$output" ]
  bash "$TEL" daily
  [ "$(jq -s 'length' "$FAKE_LOG")" -eq 1 ]
  echo '{"task":"sync","timestamp":"2026-10-26T12:00:00Z","seconds_saved":3,"units":1}' >>"$DOTFILES_STATS_FILE"
  bash "$TEL" daily
  [ "$(jq -s 'length' "$FAKE_LOG")" -eq 1 ]
}

@test "the state file is private" {
  bash "$TEL" status >/dev/null
  [ "$(stat -f %Lp "$DOTFILES_TELEMETRY_STATE" 2>/dev/null || stat -c %a "$DOTFILES_TELEMETRY_STATE")" = "600" ]
}
