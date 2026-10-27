#!/usr/bin/env bats
# scripts/proof.sh: the README Proof section is generated from
# docs/proof/metrics.json, and every metric names its date, kind, and command.

load test_helper

REPO="$BATS_TEST_DIRNAME/.."

@test "proof: the README Proof section is what the generator writes" {
  run bash "$REPO/scripts/proof.sh" --render
  [ "$status" -eq 0 ]
  expected="$output"
  actual="$(awk '/<!-- proof:start -->/{f=1} f{print} /<!-- proof:end -->/{f=0}' "$REPO/README.md")"
  [ -n "$actual" ]
  [ "$actual" = "$expected" ]
}

@test "proof: every saved metric has a date, a kind, and a command" {
  run bash "$REPO/scripts/proof.sh" --validate "$REPO/docs/proof/metrics.json"
  [ "$status" -eq 0 ]
}

@test "proof: a metric with no date fails the check" {
  jq 'del(.metrics[(.metrics | keys)[0]].date)' "$REPO/docs/proof/metrics.json" >"$TEST_DIR/bad.json"
  run bash "$REPO/scripts/proof.sh" --validate "$TEST_DIR/bad.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"date"* ]]
}

@test "proof: a metric with no kind or command fails the check" {
  jq 'del(.metrics[(.metrics | keys)[0]].kind)' "$REPO/docs/proof/metrics.json" >"$TEST_DIR/bad.json"
  run bash "$REPO/scripts/proof.sh" --validate "$TEST_DIR/bad.json"
  [ "$status" -ne 0 ]
  jq 'del(.metrics[(.metrics | keys)[0]].command)' "$REPO/docs/proof/metrics.json" >"$TEST_DIR/bad.json"
  run bash "$REPO/scripts/proof.sh" --validate "$TEST_DIR/bad.json"
  [ "$status" -ne 0 ]
}

@test "proof: collect aggregates a synthetic stats log under a salted machine label" {
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  {
    printf '{"task":"doctor","timestamp":"%s","seconds_saved":2,"units":1,"fail":0}\n' "$now"
    printf '{"task":"doctor","timestamp":"%s","seconds_saved":2,"units":1,"fail":3}\n' "$now"
    printf '{"task":"sync","timestamp":"%s","seconds_saved":3,"units":1}\n' "$now"
    printf '{"task":"morning","timestamp":"%s","seconds_saved":60,"units":4}\n' "$now"
    printf '{"task":"morning","timestamp":"%s","seconds_saved":0,"units":1}\n' "$now"
    printf '{"task":"private-thing","timestamp":"%s","seconds_saved":0,"units":1}\n' "$now"
  } >"$TEST_DIR/stats.jsonl"
  export DOTFILES_STATS_FILE="$TEST_DIR/stats.jsonl" XDG_STATE_HOME="$TEST_DIR/state"
  run bash "$REPO/scripts/proof.sh" --collect "$TEST_DIR/out.json"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.metrics.doctor_clean_pct.value' "$TEST_DIR/out.json")" = "50" ]
  [ "$(jq -r '.metrics.minutes_saved_30d.value' "$TEST_DIR/out.json")" = "1" ]
  [ "$(jq -r '.metrics.sync_runs_30d.value' "$TEST_DIR/out.json")" = "1" ]
  [ "$(jq -r '.metrics.doctor_clean_pct.kind' "$TEST_DIR/out.json")" = "real use" ]
  [ "$(jq -r '.metrics.morning_runs_7d.value' "$TEST_DIR/out.json")" = "1" ]
  [ "$(jq -r '.charts.runs_by_task_30d[] | select(.task == "other") | .runs' "$TEST_DIR/out.json")" = "1" ]
  ! grep -qF "private-thing" "$TEST_DIR/out.json"
  label="$(jq -r '.machines | keys[0]' "$TEST_DIR/out.json")"
  [[ "$label" =~ ^m-[0-9a-f]{10}$ ]]
  [ -f "$TEST_DIR/state/dotfiles/proof-salt" ]
  ! grep -qiF "$(hostname -s)" "$TEST_DIR/out.json"
  ! grep -qF "$USER" "$TEST_DIR/out.json"
}

@test "proof: install events fill the one-command row with real use minutes to a clean doctor" {
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  {
    printf '{"task":"install","timestamp":"%s","ok":true,"duration_ms":600000,"fail":0}\n' "$now"
    printf '{"task":"install","timestamp":"%s","ok":true,"duration_ms":900000,"fail":2}\n' "$now"
    printf '{"task":"install","timestamp":"%s","ok":false,"duration_ms":60000}\n' "$now"
  } >"$TEST_DIR/stats.jsonl"
  export DOTFILES_STATS_FILE="$TEST_DIR/stats.jsonl" XDG_STATE_HOME="$TEST_DIR/state"
  run bash "$REPO/scripts/proof.sh" --collect "$TEST_DIR/out.json"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(jq -r '.metrics.install_clean_minutes.value' "$TEST_DIR/out.json")" = "10" ]
  [ "$(jq -r '.metrics.install_clean_minutes.kind' "$TEST_DIR/out.json")" = "real use" ]
  [[ "$(jq -r '.metrics.install_clean_minutes.detail' "$TEST_DIR/out.json")" == *"1 of 3 install runs"* ]]
  cp "$TEST_DIR/out.json" "$TEST_DIR/metrics.json"
  row="$(PROOF_METRICS="$TEST_DIR/metrics.json" bash "$REPO/scripts/proof.sh" --render | grep '^| One command sets up a Mac')"
  [[ "$row" == *"10 min"* && "$row" == *"real use"* ]] || { echo "$row"; return 1; }
}

@test "proof: shell-start samples fill the shell row with a real use median" {
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  for ms in 120 180 400; do
    printf '{"task":"shell-start","timestamp":"%s","seconds_saved":0,"units":1,"ok":true,"duration_ms":%s}\n' "$now" "$ms"
  done >"$TEST_DIR/stats.jsonl"
  export DOTFILES_STATS_FILE="$TEST_DIR/stats.jsonl" XDG_STATE_HOME="$TEST_DIR/state"
  run bash "$REPO/scripts/proof.sh" --collect "$TEST_DIR/out.json"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(jq -r '.metrics.shell_start_field_ms.value' "$TEST_DIR/out.json")" = "180" ]
  [[ "$(jq -r '.metrics.shell_start_field_ms.detail' "$TEST_DIR/out.json")" == *"3 daily samples"*"1 machine"* ]]
  row="$(PROOF_METRICS="$TEST_DIR/out.json" bash "$REPO/scripts/proof.sh" --render | grep '^| The shell starts fast')"
  [[ "$row" == *"180 ms"* && "$row" == *"real use"* ]] || { echo "$row"; return 1; }
}
