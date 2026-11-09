#!/usr/bin/env bats
# Tests for bin/kimi-usage — read-only Kimi subscription quota display.

load test_helper

KU="$BATS_TEST_DIRNAME/../bin/kimi-usage"

setup() {
  TEST_DIR="$(mktemp -d)"
  cat > "$TEST_DIR/security" <<'STUB'
#!/bin/bash
[ -n "${FAKE_KEY:-}" ] || exit 44
printf '%s\n' "$FAKE_KEY"
STUB
  cat > "$TEST_DIR/curl" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" > "${KIMI_USAGE_FIXTURE}.argv"
cat > "${KIMI_USAGE_FIXTURE}.config"
cat "${KIMI_USAGE_FIXTURE:?missing fixture}"
STUB
  chmod +x "$TEST_DIR/security" "$TEST_DIR/curl"
  export KIMI_USAGE_SECURITY_BIN="$TEST_DIR/security" KIMI_USAGE_CURL_BIN="$TEST_DIR/curl"
  unset KIMI_API_KEY
}

teardown() { rm -rf "$TEST_DIR"; }

write_no_weekly_fixture() {
  export KIMI_USAGE_FIXTURE="$TEST_DIR/no-weekly.json"
  cat > "$KIMI_USAGE_FIXTURE" <<'JSON'
{"limits":[{"window":{"duration":300,"timeUnit":"TIME_UNIT_MINUTE"},"detail":{"limit":"100","used":"40","remaining":"60","resetTime":"2026-11-09T02:48:00.913051Z"}}],"usages":{"limit_5h":{"used_ratio":0.4024,"reset_time":"2026-11-09T02:48:00Z"},"limit_month_total":{"used_ratio":0.0245,"reset_time":"2026-12-08T21:48:33Z"}}}
JSON
}

@test "shows actual 5-hour and monthly quotas when no weekly limit is reported" {
  write_no_weekly_fixture
  FAKE_KEY=test-key run bash "$KU"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Weekly: no weekly limit reported for this plan"* ]]
  [[ "$output" == *"5-hour: 60/100 quota units left (59.76%); resets Mon Nov 9 02:48 UTC"* ]]
  [[ "$output" == *"Monthly: 97.55% quota left; resets Tue Dec 8 21:48 UTC"* ]]
  [[ "$output" != *"test-key"* ]]
}

@test "shows the weekly ratio when the plan reports one" {
  write_no_weekly_fixture
  jq '.usages.limit_7d = {"used_ratio":0.5,"reset_time":"2026-11-15T02:48:00Z"}' "$KIMI_USAGE_FIXTURE" > "$TEST_DIR/weekly.json"
  mv "$TEST_DIR/weekly.json" "$KIMI_USAGE_FIXTURE"
  FAKE_KEY=k run bash "$KU"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Weekly: 50% quota left; resets Sun Nov 15 02:48 UTC"* ]]
}

@test "prefers detailed weekly remaining and limit when present" {
  write_no_weekly_fixture
  jq '.limits += [{"window":{"duration":10080,"timeUnit":"TIME_UNIT_MINUTE"},"detail":{"limit":"100","used":"40","remaining":"60","resetTime":"2026-11-15T02:48:00Z"}}]' "$KIMI_USAGE_FIXTURE" > "$TEST_DIR/weekly.json"
  mv "$TEST_DIR/weekly.json" "$KIMI_USAGE_FIXTURE"
  FAKE_KEY=k run bash "$KU"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Weekly: 60/100 quota units left (60%); resets Sun Nov 15 02:48 UTC"* ]]
}

@test "missing key fails with setup guidance and no secret output" {
  run bash "$KU"
  [ "$status" -eq 2 ]
  [[ "$output" == *"opencode auth login"* ]]
  [[ "$output" == *"-s kimi-code-api-key -w"* ]]
  [[ "$output" != *"sk-"* ]]
}

@test "forecast says when the current 5-hour average cannot exhaust before reset" {
  write_no_weekly_fixture
  reset=$(/bin/date -u -v+1H '+%Y-%m-%dT%H:%M:%SZ')
  jq --arg reset "$reset" '.limits[0].detail.used = "50" | .limits[0].detail.remaining = "50" | .limits[0].detail.resetTime = $reset | .usages.limit_5h.reset_time = $reset' "$KIMI_USAGE_FIXTURE" > "$TEST_DIR/forecast.json"
  mv "$TEST_DIR/forecast.json" "$KIMI_USAGE_FIXTURE"
  FAKE_KEY=k run bash "$KU" --forecast
  [ "$status" -eq 0 ]
  [[ "$output" == *"5-hour forecast: no exhaustion before reset; about 38 units left at reset (current average)"* ]]
}

@test "forecast names estimated exhaustion before reset when the burn rate is high" {
  write_no_weekly_fixture
  reset=$(/bin/date -u -v+1H '+%Y-%m-%dT%H:%M:%SZ')
  jq --arg reset "$reset" '.limits[0].detail.used = "90" | .limits[0].detail.remaining = "10" | .limits[0].detail.resetTime = $reset | .usages.limit_5h.reset_time = $reset' "$KIMI_USAGE_FIXTURE" > "$TEST_DIR/forecast.json"
  mv "$TEST_DIR/forecast.json" "$KIMI_USAGE_FIXTURE"
  FAKE_KEY=k run bash "$KU" --forecast
  [ "$status" -eq 0 ]
  [[ "$output" == *"5-hour forecast: quota runs out in 27m (current average)"* ]]
}

@test "uses environment credential first and keeps it out of curl argv" {
  write_no_weekly_fixture
  export KIMI_API_KEY=env-key
  FAKE_KEY=keychain-key run bash "$KU"
  [ "$status" -eq 0 ]
  grep -q 'Bearer env-key' "${KIMI_USAGE_FIXTURE}.config"
  [[ "$(cat "${KIMI_USAGE_FIXTURE}.argv")" != *"env-key"* ]]
  [[ "$(cat "${KIMI_USAGE_FIXTURE}.argv")" != *"keychain-key"* ]]
  [[ "$(cat "${KIMI_USAGE_FIXTURE}.argv")" == *"https://api.kimi.com/coding/v1/usages"* ]]
  [[ "$(cat "${KIMI_USAGE_FIXTURE}.argv")" != *"--request"* ]]
  [[ "$output" != *"env-key"* ]]
  [[ "$output" != *"keychain-key"* ]]
}

@test "malformed JSON fails without leaking the credential" {
  write_no_weekly_fixture
  printf '{not-json\n' > "$KIMI_USAGE_FIXTURE"
  FAKE_KEY=secret-key run bash "$KU"
  [ "$status" -eq 4 ]
  [[ "$output" == *"unreadable usage response"* ]]
  [[ "$output" != *"secret-key"* ]]
}

@test "request failure is nonzero and never prints the credential" {
  write_no_weekly_fixture
  cat > "$TEST_DIR/curl" <<'STUB'
#!/bin/bash
exit 22
STUB
  chmod +x "$TEST_DIR/curl"
  FAKE_KEY=secret-key run bash "$KU"
  [ "$status" -ne 0 ]
  [[ "$output" == *"could not read Kimi usage"* ]]
  [[ "$output" != *"secret-key"* ]]
}
