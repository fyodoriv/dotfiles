#!/usr/bin/env bats
# Tests for time-saved tracking (log_run, get_time_saved_summary, dotfiles-stats)

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  mkdir -p "$TEST_HOME"

  export HOME="$TEST_HOME"
  export DOTFILES_STATS_FILE="$TEST_DIR/stats.jsonl"

  # shellcheck source=../lib/stats.sh
  source "$BATS_TEST_DIRNAME/../lib/stats.sh"
}

@test "log_run creates stats file and appends JSONL line" {
  [ ! -f "$DOTFILES_STATS_FILE" ]

  log_run sync

  [ -f "$DOTFILES_STATS_FILE" ]
  [ "$(wc -l < "$DOTFILES_STATS_FILE" | tr -d ' ')" -eq 1 ]
  grep -q '"task":"sync"' "$DOTFILES_STATS_FILE"
  grep -q '"seconds_saved":3' "$DOTFILES_STATS_FILE"
}

@test "log_run appends multiple entries" {
  log_run sync
  log_run cleanup
  log_run doctor

  [ "$(wc -l < "$DOTFILES_STATS_FILE" | tr -d ' ')" -eq 3 ]
  grep -q '"task":"sync"' "$DOTFILES_STATS_FILE"
  grep -q '"task":"cleanup"' "$DOTFILES_STATS_FILE"
  grep -q '"task":"doctor"' "$DOTFILES_STATS_FILE"
}

@test "log_run uses correct per-unit estimates (1 unit default)" {
  log_run sync
  log_run doctor
  log_run cleanup
  log_run git-maintain
  log_run cursor-priority
  log_run morning

  grep '"task":"sync"' "$DOTFILES_STATS_FILE" | grep -q '"seconds_saved":3'
  grep '"task":"doctor"' "$DOTFILES_STATS_FILE" | grep -q '"seconds_saved":2'
  grep '"task":"cleanup"' "$DOTFILES_STATS_FILE" | grep -q '"seconds_saved":10'
  grep '"task":"git-maintain"' "$DOTFILES_STATS_FILE" | grep -q '"seconds_saved":5'
  grep '"task":"cursor-priority"' "$DOTFILES_STATS_FILE" | grep -q '"seconds_saved":0'
  grep '"task":"morning"' "$DOTFILES_STATS_FILE" | grep -q '"seconds_saved":15'
}

@test "log_run scales time saved by unit count" {
  log_run git-maintain 5
  log_run cleanup 8

  # git-maintain: 5s/unit × 5 = 25
  grep '"task":"git-maintain"' "$DOTFILES_STATS_FILE" | grep -q '"seconds_saved":25'
  grep '"task":"git-maintain"' "$DOTFILES_STATS_FILE" | grep -q '"units":5'
  # cleanup: 10s/unit × 8 = 80
  grep '"task":"cleanup"' "$DOTFILES_STATS_FILE" | grep -q '"seconds_saved":80'
  grep '"task":"cleanup"' "$DOTFILES_STATS_FILE" | grep -q '"units":8'
}

@test "log_run records units field" {
  log_run sync
  log_run doctor 40

  grep '"task":"sync"' "$DOTFILES_STATS_FILE" | grep -q '"units":1'
  grep '"task":"doctor"' "$DOTFILES_STATS_FILE" | grep -q '"units":40'
  # doctor: 2s/unit × 40 = 80
  grep '"task":"doctor"' "$DOTFILES_STATS_FILE" | grep -q '"seconds_saved":80'
}

@test "log_run uses 0 for unknown task names" {
  log_run unknown-task

  grep '"task":"unknown-task"' "$DOTFILES_STATS_FILE" | grep -q '"seconds_saved":0'
}

@test "log_run includes ISO 8601 timestamp" {
  log_run sync

  # Match pattern: "timestamp":"YYYY-MM-DDTHH:MM:SSZ"
  grep -qE '"timestamp":"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"' "$DOTFILES_STATS_FILE"
}

@test "get_time_saved_summary returns zero message for empty stats" {
  run get_time_saved_summary
  [ "$status" -eq 0 ]
  [ "$output" = "0 runs, 0m saved" ]
}

@test "get_time_saved_summary returns zero message for missing file" {
  rm -f "$DOTFILES_STATS_FILE"

  run get_time_saved_summary
  [ "$status" -eq 0 ]
  [ "$output" = "0 runs, 0m saved" ]
}

@test "get_time_saved_summary shows minutes for small totals" {
  log_run sync  # 45s

  run get_time_saved_summary
  [ "$status" -eq 0 ]
  [ "$output" = "1 runs, ~0m saved" ]
}

@test "get_time_saved_summary shows minutes for scaled totals" {
  # sync(1×3) + doctor(40×2) + cleanup(8×10) + git-maintain(5×5)
  # = 3 + 80 + 80 + 25 = 188s = 3m
  log_run sync
  log_run doctor 40
  log_run cleanup 8
  log_run git-maintain 5

  run get_time_saved_summary
  [ "$status" -eq 0 ]
  [ "$output" = "4 runs, ~3m saved" ]
}

@test "get_time_saved_summary shows hours when over 60 minutes" {
  # 70 runs × cleanup(10 units × 10s) = 70 × 100 = 7000s = 1h 56m
  for i in $(seq 1 70); do
    log_run cleanup 10
  done

  run get_time_saved_summary
  [ "$status" -eq 0 ]
  [ "$output" = "70 runs, ~1h 56m saved" ]
}

@test "dotfiles-stats --oneliner matches get_time_saved_summary" {
  log_run sync
  log_run doctor

  expected=$(get_time_saved_summary)
  run bash "$BATS_TEST_DIRNAME/../bin/dotfiles-stats" --oneliner
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "dotfiles-stats --oneliner handles empty stats" {
  run bash "$BATS_TEST_DIRNAME/../bin/dotfiles-stats" --oneliner
  [ "$status" -eq 0 ]
  [ "$output" = "No automation runs recorded yet" ]
}

@test "dotfiles-stats full output shows task breakdown" {
  log_run sync
  log_run cleanup

  run bash "$BATS_TEST_DIRNAME/../bin/dotfiles-stats"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Total time saved"
  echo "$output" | grep -q "Total runs"
  echo "$output" | grep -q "sync"
  echo "$output" | grep -q "cleanup"
}

@test "dotfiles-stats full output handles empty stats gracefully" {
  run bash "$BATS_TEST_DIRNAME/../bin/dotfiles-stats"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "No runs recorded yet"
}

@test "dotfiles-stats --recalc rewrites historical data with current estimates" {
  # Write old-style inflated entries
  echo '{"task":"cursor-priority","timestamp":"2026-03-11T12:00:00Z","seconds_saved":15,"units":1}' >> "$DOTFILES_STATS_FILE"
  echo '{"task":"sync","timestamp":"2026-03-11T12:01:00Z","seconds_saved":45,"units":1}' >> "$DOTFILES_STATS_FILE"
  echo '{"task":"doctor","timestamp":"2026-03-11T12:02:00Z","pass":100,"fail":2,"seconds_saved":1020,"units":102}' >> "$DOTFILES_STATS_FILE"

  run bash "$BATS_TEST_DIRNAME/../bin/dotfiles-stats" --recalc
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Recalculated 3 records"

  # cursor-priority: 0
  grep '"task":"cursor-priority"' "$DOTFILES_STATS_FILE" | grep -q '"seconds_saved":0'
  # sync: 3 × 1 = 3
  grep '"task":"sync"' "$DOTFILES_STATS_FILE" | grep -q '"seconds_saved":3'
  # doctor: flat 2, units reset to 1
  grep '"task":"doctor"' "$DOTFILES_STATS_FILE" | grep -q '"seconds_saved":2'
  grep '"task":"doctor"' "$DOTFILES_STATS_FILE" | grep -q '"units":1'
}

@test "dotfiles-stats --recalc on a missing stats file is a clean no-op" {
  # Closes test-stats-recalc case 2: no file, no error, friendly message.
  [ ! -f "$DOTFILES_STATS_FILE" ]
  run bash "$BATS_TEST_DIRNAME/../bin/dotfiles-stats" --recalc
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "No stats file to recalculate"
  # Recalc must not create a file out of nowhere.
  [ ! -f "$DOTFILES_STATS_FILE" ]
}

@test "dotfiles-stats --recalc on an empty stats file is a clean no-op" {
  # Closes test-stats-recalc case 2: empty file, no error, friendly message.
  : > "$DOTFILES_STATS_FILE"
  run bash "$BATS_TEST_DIRNAME/../bin/dotfiles-stats" --recalc
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "No stats file to recalculate"
  # File still exists and is still empty — recalc must not touch it.
  [ -f "$DOTFILES_STATS_FILE" ]
  [ ! -s "$DOTFILES_STATS_FILE" ]
}

@test "dotfiles-stats --recalc on malformed JSON surfaces the error and preserves the file" {
  # Closes test-stats-recalc case 3: corrupt input must NOT silently overwrite
  # the user's history. jq exits non-zero, set -e propagates, and the original
  # file is preserved untouched (jq writes to a tmp_file; the rename only fires
  # if jq succeeds).
  echo '{"task":"sync","timestamp":"2026-03-11T12:00:00Z","seconds_saved":3,"units":1}' >> "$DOTFILES_STATS_FILE"
  echo 'not-valid-json {{{' >> "$DOTFILES_STATS_FILE"

  # Snapshot before recalc — must match after.
  before=$(cat "$DOTFILES_STATS_FILE")

  run bash "$BATS_TEST_DIRNAME/../bin/dotfiles-stats" --recalc
  [ "$status" -ne 0 ]

  # Original file content preserved (jq never finished; mv never ran).
  [ "$(cat "$DOTFILES_STATS_FILE")" = "$before" ]
}

@test "dotfiles-stats completes within 5 seconds on 5000-line file" {
  # Generate a large stats file spanning multiple days
  for day in $(seq 1 5); do
    d=$(printf "2026-03-%02d" "$day")
    for i in $(seq 1 1000); do
      echo "{\"task\":\"sync\",\"timestamp\":\"${d}T12:00:00Z\",\"seconds_saved\":15,\"units\":1}"
    done
  done > "$DOTFILES_STATS_FILE"

  [ "$(wc -l < "$DOTFILES_STATS_FILE" | tr -d ' ')" -eq 5000 ]

  start=$(date +%s)
  run bash "$BATS_TEST_DIRNAME/../bin/dotfiles-stats"
  end=$(date +%s)
  elapsed=$((end - start))

  [ "$status" -eq 0 ]
  [ "$elapsed" -lt 5 ]
  echo "$output" | grep -q "Total runs"
  echo "$output" | grep -q "5000"
}

# ── Failure-mode coverage for stats library ────────────────────────
#
# Stats is intentionally best-effort instrumentation: a corrupt JSONL,
# a read-only file, or a missing parent directory must NOT take down
# doctor / cleanup / upgrade / sync. The tests below pin those
# guarantees so future edits to lib/stats.sh and bin/dotfiles-stats
# can't quietly regress automation.

@test "log_run: parent directory creation failure does not crash the caller" {
  # Replace the parent directory of the stats file with a regular file
  # so `mkdir -p` cannot succeed. log_run must warn on stderr and
  # return 0 — never propagate the failure into the calling script.
  rm -rf "$TEST_DIR/blocked"
  printf 'placeholder\n' > "$TEST_DIR/blocked"
  export DOTFILES_STATS_FILE="$TEST_DIR/blocked/stats.jsonl"

  run log_run sync

  [ "$status" -eq 0 ]
  [[ "$output" == *"cannot create directory"* ]]
  [ ! -f "$DOTFILES_STATS_FILE" ]
}

@test "log_run: read-only stats file does not crash the caller" {
  # An older stats file that lost write permission (chmod 444 from a
  # cleanup script, restored from backup, etc.) must surface a clear
  # diagnostic without aborting the script that called log_run.
  printf '' > "$DOTFILES_STATS_FILE"
  chmod 444 "$DOTFILES_STATS_FILE"

  run log_run sync

  [ "$status" -eq 0 ]
  before=$(stat -f '%p' "$DOTFILES_STATS_FILE" 2>/dev/null || stat -c '%a' "$DOTFILES_STATS_FILE")
  chmod 644 "$DOTFILES_STATS_FILE"
  [ ! -s "$DOTFILES_STATS_FILE" ]
}

@test "get_time_saved_summary: corrupt JSONL falls back to zero rather than aborting" {
  # A truncated upgrade or interrupted log_run can leave a half-written
  # last line. The summary must report what it can — counting the
  # malformed line as zero — instead of crashing the prompt widget that
  # calls this on every shell start.
  echo '{"task":"sync","timestamp":"2026-03-11T12:00:00Z","seconds_saved":3,"units":1}' >> "$DOTFILES_STATS_FILE"
  printf 'not-valid-json {{{ no newline' >> "$DOTFILES_STATS_FILE"

  run get_time_saved_summary

  [ "$status" -eq 0 ]
  [[ "$output" == *"runs"* ]]
  [[ "$output" == *"saved"* ]]
}

@test "get_time_saved_summary: entries missing seconds_saved are treated as zero" {
  # Old log_run versions wrote different shapes; the summary must keep
  # working when an entry is missing the field entirely.
  cat > "$DOTFILES_STATS_FILE" <<'JSONL'
{"task":"sync","timestamp":"2026-03-11T12:00:00Z","units":1}
{"task":"sync","timestamp":"2026-03-11T12:00:01Z","seconds_saved":3,"units":1}
JSONL

  run get_time_saved_summary

  [ "$status" -eq 0 ]
  [[ "$output" == *"2 runs"* ]]
  # Total is 0 + 3 = 3 seconds → "~0m saved"
  [[ "$output" == *"~0m saved"* ]]
}

@test "get_time_saved_summary: very large totals format correctly past 24 hours" {
  # 36 hours ÷ morning(15s/run) = 8640 runs. Use cleanup at 1000 units
  # × 10s/unit = 10000s/run × 13 runs = 130000s ≈ 36h 6m.
  for i in $(seq 1 13); do
    log_run cleanup 1000
  done

  run get_time_saved_summary

  [ "$status" -eq 0 ]
  [[ "$output" =~ ^13\ runs,\ ~36h\ [0-9]+m\ saved$ ]]
}

@test "bin/dotfiles-stats shebang avoids /usr/bin/env (endpoint agents may block env)" {
  local script="$BATS_TEST_DIRNAME/../bin/dotfiles-stats"
  local shebang
  shebang=$(head -1 "$script")
  [ "$shebang" = "#!/bin/bash" ] || {
    echo "bin/dotfiles-stats shebang must be #!/bin/bash (not env):"
    echo "  $shebang"
    return 1
  }
  grep -q 'BASH_VERSINFO\[0\] < 4' "$script" || {
    echo "bin/dotfiles-stats must re-exec Homebrew bash when Bash < 4"
    return 1
  }
}

@test "bin/dotfiles-stats --help runs cleanly when invoked directly" {
  # Direct invocation (no `dotfiles stats` wrapper) must succeed, since
  # adopters who add `~/apps/dotfiles/bin` to PATH expect to call
  # `dotfiles-stats` directly. --help exits before Bash 4+ code paths;
  # full runs re-exec Homebrew bash when macOS /bin/bash is 3.2.
  run "$BATS_TEST_DIRNAME/../bin/dotfiles-stats" --help
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qiE '^Usage: dotfiles-stats' || {
    echo "dotfiles-stats --help missing 'Usage:' line"
    printf '%s\n' "$output"
    return 1
  }
  # And no Bash-3.2 declare error leaked into the output.
  printf '%s\n' "$output" | grep -qE 'declare: -A: invalid option' && {
    echo "dotfiles-stats --help leaked Bash 3.2 'declare: -A' error"
    printf '%s\n' "$output"
    return 1
  } || true
}
