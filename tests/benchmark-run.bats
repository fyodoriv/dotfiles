#!/usr/bin/env bats
# Tests for scripts/benchmark-run.sh (competitive scorecard)

load test_helper

BENCH="$BATS_TEST_DIRNAME/../scripts/benchmark-run.sh"

setup() {
  command -v jq >/dev/null 2>&1 || skip "jq is not installed"
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi is not installed"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  printf 'keep\n' > "$HOME/sentinel"
  # Small, offline, one-shot workload. Missing competitors become blocked.
  export BENCH_FILES=4 BENCH_REPS=1 BENCH_NO_FETCH=1
  # Tests never save a scorecard unless a test asks for it.
  export BENCH_SAVE=""
}

home_listing() {
  (cd "$HOME" && find . -print | LC_ALL=C sort)
}

@test "benchmark-run: script is executable and has no env shebang" {
  [ -x "$BENCH" ]
  run head -1 "$BENCH"
  [ "$output" = "#!/bin/bash" ]
}

@test "benchmark-run: --json prints one scorecard with the top-level keys" {
  BENCH_TOOLS="dotfiles chezmoi" run "$BENCH" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'has("dotfiles") and has("competitors") and has("blocked") and has("generatedAt") and has("host") and has("north_star")'
}

@test "benchmark-run: dotfiles reports at least five shared metrics" {
  BENCH_TOOLS="dotfiles chezmoi" run "$BENCH" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.dotfiles.status == "ok"'
  echo "$output" | jq -e '[.dotfiles.metrics | to_entries[] | select(.value != null)] | length >= 5'
  echo "$output" | jq -e '.dotfiles.metrics.reproducibility_pct == 100'
  echo "$output" | jq -e '.dotfiles.metrics.drift_detected == true'
}

@test "benchmark-run: north star compares dotfiles with competitors that ran" {
  BENCH_TOOLS="dotfiles chezmoi" run "$BENCH" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.north_star.metrics_compared >= 5'
  echo "$output" | jq -e '.north_star.metrics_beaten <= .north_star.metrics_compared'
}

@test "benchmark-run: all competitors appear, missing ones as blocked with a reason" {
  export BENCH_CACHE_DIR="$BATS_TEST_TMPDIR/empty-cache"
  export BENCH_STOW="$BATS_TEST_TMPDIR/no-such-stow"
  export BENCH_NIX="$BATS_TEST_TMPDIR/no-such-nix"
  run "$BENCH" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.competitors | length >= 4'
  echo "$output" | jq -e '[.competitors[].tool] == ["chezmoi", "stow", "yadm", "dotbot", "home-manager"]'
  echo "$output" | jq -e '[.blocked[].tool] | (index("yadm") != null and index("dotbot") != null and index("home-manager") != null)'
  echo "$output" | jq -e '.blocked | all(.reason | length > 0)'
  # Blocked rows keep null measurements; only the doc-sourced step count is set.
  echo "$output" | jq -e '.competitors[] | select(.tool == "yadm") | .metrics.cold_apply_ms == null and .metrics.manual_bootstrap_steps == 2'
}

@test "benchmark-run: the real HOME is never changed" {
  before="$(home_listing)"
  run "$BENCH" --json
  [ "$status" -eq 0 ]
  [ "$(home_listing)" = "$before" ]
  [ "$(cat "$HOME/sentinel")" = "keep" ]
}

@test "benchmark-run: a full run saves its scorecard; a subset run does not" {
  export BENCH_CACHE_DIR="$BATS_TEST_TMPDIR/empty-cache"
  export BENCH_SAVE="$BATS_TEST_TMPDIR/state/scorecard.json"
  BENCH_TOOLS="dotfiles chezmoi" run "$BENCH" --json
  [ "$status" -eq 0 ]
  [ ! -e "$BENCH_SAVE" ]
  run "$BENCH" --json
  [ "$status" -eq 0 ]
  jq -e '.north_star.metrics_beaten >= 0' "$BENCH_SAVE"
}

@test "benchmark-run: dotfiles bootstrap steps are measured from the README quick start" {
  BENCH_TOOLS="dotfiles chezmoi" run "$BENCH" --json
  [ "$status" -eq 0 ]
  local readme
  readme="$(awk '/^```/{if (f) exit; f = 1; next} f && $0 !~ /^[[:space:]]*(#|$)/' "$BATS_TEST_DIRNAME/../README.md" | wc -l | tr -d ' ')"
  [ "$readme" -ge 1 ]
  echo "$output" | jq -e --argjson n "$readme" '.dotfiles.metrics.manual_bootstrap_steps == $n'
}

@test "benchmark-run: table output names every tool and the north star" {
  BENCH_TOOLS="dotfiles chezmoi" run "$BENCH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dotfiles"* ]]
  [[ "$output" == *"chezmoi"* ]]
  [[ "$output" == *"north star:"* ]]
}

@test "benchmark-run: rejects a bad --files value" {
  run "$BENCH" --files abc
  [ "$status" -eq 2 ]
}

@test "benchmark-run: rejects an unknown tool" {
  BENCH_TOOLS="nope" run "$BENCH" --json
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown tool"* ]]
}
