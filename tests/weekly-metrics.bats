#!/usr/bin/env bats
# lib/weekly-metrics.sh: opt-in weekly aggregate file in the shared provider
# format (config/weekly-metrics.schema.json, copied from agentbrew).

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME"
  export DOTFILES_STATS_FILE="$TEST_DIR/stats.jsonl"
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  cat > "$DOTFILES_STATS_FILE" <<JSONL
{"task":"doctor","timestamp":"$now","pass":10,"fail":1,"fixed":2,"warn":0,"skip":1,"seconds_saved":2,"units":1}
{"task":"doctor","timestamp":"2020-01-01T00:00:00Z","pass":10,"fail":0,"fixed":9,"warn":0,"skip":0,"seconds_saved":2,"units":1}
{"task":"sync","timestamp":"$now","seconds_saved":3,"units":1}
{"task":"upgrade","timestamp":"$now","seconds_saved":0,"units":1}
JSONL
  WEEK="$(date -u +%G-W%V)"
  OUT="$HOME/.local/share/dotfiles/metrics/weekly-$WEEK.json"
}

teardown() { rm -rf "$TEST_DIR"; }

write_metrics() {
  run env DOTFILES_WEEKLY_METRICS="$1" DOTFILES_LAUNCHCTL_LIST_CMD="printf '%s\n' '-	0	com.dotfiles.a' '-	78	com.dotfiles.b' '-	1	com.other.c'" \
    bash -c "source '$REPO/lib/weekly-metrics.sh' && weekly_metrics_write 10 1 2 0 1"
}

@test "schema allows strings only in tool, version, week, and machine_id" {
  run jq -r '[.properties | to_entries[] | select(.value.type == "string") | .key] | sort | join(",")' \
    "$REPO/config/weekly-metrics.schema.json"
  [ "$output" = "machine_id,tool,version,week" ]
  run jq -r '.properties.metrics.additionalProperties.type, .additionalProperties' "$REPO/config/weekly-metrics.schema.json"
  [ "$output" = $'number\nfalse' ]
}

@test "off by default: no file is written" {
  write_metrics false
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.local/share/dotfiles/metrics" ]
}

@test "AGENTBREW_EVENTS=0 turns it off even when opted in" {
  run env AGENTBREW_EVENTS=0 DOTFILES_WEEKLY_METRICS=true bash -c "source '$REPO/lib/weekly-metrics.sh' && weekly_metrics_write 1 0 0 0 0"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.local/share/dotfiles/metrics" ]
}

@test "opted in: writes numbers only, in the shared schema" {
  write_metrics true
  [ "$status" -eq 0 ]
  [ -f "$OUT" ]
  run jq -r 'keys | join(",")' "$OUT"
  [ "$output" = "machine_id,metrics,tool,version,week" ]
  run jq -r '[paths(type == "string")] | map(join(".")) | sort | join(",")' "$OUT"
  [ "$output" = "machine_id,tool,version,week" ]
  run jq -r '.tool, .week' "$OUT"
  [ "$output" = $'dotfiles\n'"$WEEK" ]
  jq -e '.machine_id | test("^[0-9a-f]{32}$")' "$OUT"
  jq -e '.version | test("^[0-9A-Za-z.+-]{1,40}$")' "$OUT"
  jq -e '.metrics | keys | all(test("^[a-z][a-z0-9_]{0,63}$"))' "$OUT"
  jq -e '.metrics | to_entries | all(.value | type == "number")' "$OUT"
  run jq -c '.metrics' "$OUT"
  [ "$output" = '{"doctor_checks_passed":10,"doctor_checks_total":14,"doctor_runs":1,"heal_fixes_applied":2,"sync_runs":1,"upgrade_runs":1,"launchagent_failed":1}' ]
}

@test "machine id is random, stable, and private" {
  write_metrics true
  id1="$(jq -r .machine_id "$OUT")"
  write_metrics true
  [ "$(jq -r .machine_id "$OUT")" = "$id1" ]
  [ "$(stat -f %Lp "$HOME/.local/share/dotfiles/metrics/machine-id")" = "600" ]
}

@test "reuses the agentbrew machine id when it exists" {
  mkdir -p "$HOME/.local/share/agentbrew/metrics"
  echo "0123456789abcdef0123456789abcdef" > "$HOME/.local/share/agentbrew/metrics/machine-id"
  write_metrics true
  [ "$(jq -r .machine_id "$OUT")" = "0123456789abcdef0123456789abcdef" ]
}

@test "chezmoi config: weekly_metrics is false by default and keeps an explicit true" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  render() {
    chezmoi execute-template --init --source "$REPO" --override-data "$1" < "$REPO/.chezmoi.yaml.tmpl"
  }
  run render '{"owner_machine":true,"profile":"full"}'
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\n  weekly_metrics: false'* ]]
  run render '{"owner_machine":true,"profile":"full","weekly_metrics":true}'
  [[ "$output" == *$'\n  weekly_metrics: true'* ]]
}

@test "dotfiles-doctor calls the writer after a full run" {
  grep -q 'source "$DOTFILES_DIR/lib/weekly-metrics.sh"' "$REPO/bin/dotfiles-doctor"
  grep -q 'weekly_metrics_write "$pass_count" "$fail_count" "$fix_count" "$warn_count" "$skip_count"' "$REPO/bin/dotfiles-doctor"
}
