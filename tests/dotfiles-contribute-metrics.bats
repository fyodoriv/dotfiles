#!/usr/bin/env bats
# dotfiles contribute / dotfiles metrics: thin wrappers over agentbrew.

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  STUB_LOG="$TEST_DIR/agentbrew.log"
  cat > "$TEST_DIR/agentbrew" <<'STUB'
#!/bin/bash
printf 'cwd=%s args=%s\n' "$PWD" "$*" >> "$STUB_LOG"
if [ "$1" = "metrics" ] && [[ " $* " == *" --share "* ]]; then
  printf '## agentbrew metrics snapshot (7 days)\n\n- agentbrew 0.0.0\n'
elif [ "$1" = "metrics" ]; then
  printf 'agentbrew metrics — last 7 days (local only, nothing is uploaded)\n'
fi
STUB
  cat > "$TEST_DIR/sampler" <<'STUB'
#!/bin/bash
printf 'last 24h: 10 rows\npeak load1 9.00 at 2026-10-16T08:00:00 (top: secret-proc:9.0)\noverload rows (load1 > 20): 0\npeak CPU busy 40%% at 2026-10-16T08:00:00\n'
STUB
  chmod +x "$TEST_DIR/agentbrew" "$TEST_DIR/sampler"
  export STUB_LOG DOTFILES_AGENTBREW_BIN="$TEST_DIR/agentbrew" DOTFILES_LOAD_SAMPLER_BIN="$TEST_DIR/sampler"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "contribute runs agentbrew contribute from the dotfiles checkout and passes flags through" {
  run env DOTFILES_DIR="$REPO" bash "$REPO/bin/dotfiles-contribute" --dry-run --draft
  [ "$status" -eq 0 ]
  grep -qx "cwd=$REPO args=contribute --dry-run --draft" "$STUB_LOG"
}

@test "contribute --repo <path> opens the PR from that checkout" {
  mkdir -p "$TEST_DIR/skill-repo"
  run env DOTFILES_DIR="$REPO" bash "$REPO/bin/dotfiles-contribute" --repo "$TEST_DIR/skill-repo" --dry-run
  [ "$status" -eq 0 ]
  grep -q "cwd=$TEST_DIR/skill-repo args=contribute --dry-run" "$STUB_LOG"
}

@test "metrics shows agentbrew metrics plus the full machine load report" {
  run env DOTFILES_DIR="$REPO" bash "$REPO/bin/dotfiles-metrics" --days 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing is uploaded"* ]]
  [[ "$output" == *"Machine load (last 1 days)"* ]]
  [[ "$output" == *"peak load1"* ]]
  grep -q "args=metrics --days 1" "$STUB_LOG"
}

@test "metrics --share writes aggregates only (no process names)" {
  run env DOTFILES_DIR="$REPO" bash "$REPO/bin/dotfiles-metrics" --share "$TEST_DIR/m.md"
  [ "$status" -eq 0 ]
  grep -q '^## agentbrew metrics snapshot' "$TEST_DIR/m.md"
  grep -q '^- overload rows' "$TEST_DIR/m.md"
  ! grep -q 'secret-proc' "$TEST_DIR/m.md"
}

@test "metrics rejects a non-numeric --days" {
  run env DOTFILES_DIR="$REPO" bash "$REPO/bin/dotfiles-metrics" --days soon
  [ "$status" -eq 2 ]
}

@test "metrics --table prints each value, and (stub) when a source is missing" {
  cat > "$TEST_DIR/metrics.md" <<'MD'
## Metrics

| Metric | Goal | Pivot | Command | Story |
|---|---|---|---|---|
| Rows in a file | ≥ 2 | < 1 | `printf 'a\nb\n' \| wc -l \| tr -d ' '` | US01 |
| Missing source | 0 | 1 | `jq -s length "$TEST_DIR/no-such-file.jsonl"` | US02 |
| Count from a source that is missing | 0 | 1 | `cat "$TEST_DIR/no-such-file" \| wc -l` | US03 |
| Not a number | 0 | 1 | `echo soon` | US04 |

## Guards

| Metric | Goal | Pivot | Command | Story |
|---|---|---|---|---|
| Never run | 0 | 1 | `echo 7` | US05 |
MD
  run env DOTFILES_DIR="$REPO" DOTFILES_METRICS_FILE="$TEST_DIR/metrics.md" TEST_DIR="$TEST_DIR" bash "$REPO/bin/dotfiles-metrics" --table
  [ "$status" -eq 0 ]
  [[ "$output" =~ "2        | US01" ]]
  [[ "$output" =~ "(stub)   | US02" ]]
  # A pipe that would answer 0 for a missing file prints (stub), not 0.
  [[ "$output" =~ "(stub)   | US03" ]]
  [[ "$output" =~ "(stub)   | US04" ]]
  [[ "$output" != *"US05"* ]]
}

@test "metrics --table: every docs/metrics.md row has a goal, a pivot, a command, and a story" {
  run awk '/^## /{on=($0=="## Metrics"); next} on && /^\| / && !/^\| *Metric *\|/ && !/^\|[-| ]+\|$/' "$REPO/docs/metrics.md"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  while IFS= read -r row; do
    cells="$(printf '%s' "$row" | sed 's/\\|//g' | awk -F'|' '{print NF-2}')"
    [ "$cells" -eq 5 ] || { echo "not 5 cells: $row"; return 1; }
    printf '%s' "$row" | grep -q '| `' || { echo "no command: $row"; return 1; }
    if printf '%s' "$row" | grep -qiE '\| *(same|TODO|FILL|TBD|-) *\||<[a-z]+>'; then
      echo "placeholder: $row"; return 1
    fi
  done <<< "$output"
}

@test "metrics docs: every table row has as many cells as its header" {
  local f bad=""
  for f in "$REPO/docs/metrics.md" "$REPO/docs/competition/scorecard.md" "$REPO/VISION.md"; do
    bad="$bad$(sed 's/\\|//g' "$f" | awk -v f="$(basename "$f")" '
      /^\|/ { n = gsub(/\|/, "|"); if (!inrow) { want = n; inrow = 1 } else if (n != want) print " " f ":" NR }
      !/^\|/ { inrow = 0 }')"
  done
  [ -z "$bad" ] || { echo "rows with the wrong cell count:$bad"; return 1; }
}

@test "metrics: an empty window prints a real 0; a missing source fails (stub)" {
  # The US08 row: minutes saved in the last 30 days.
  local cmd
  cmd="$(awk -F'`' '/^\| Minutes saved by automation/{print $2; exit}' "$REPO/docs/metrics.md" | sed 's/\\|/|/g')"
  [ -n "$cmd" ]
  mkdir -p "$TEST_DIR/home"
  printf '{"task":"sync","timestamp":"2020-01-01T00:00:00Z","seconds_saved":3,"units":1}\n' > "$TEST_DIR/home/.dotfiles-stats.jsonl"
  run env HOME="$TEST_DIR/home" bash -o pipefail -c "$cmd"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
  rm "$TEST_DIR/home/.dotfiles-stats.jsonl"
  run env HOME="$TEST_DIR/home" bash -o pipefail -c "$cmd"
  [ "$status" -ne 0 ]
}
