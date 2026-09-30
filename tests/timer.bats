#!/usr/bin/env bats
# Functional tests for timer (pomodoro) script

load test_helper

TIMER_CMD="$BATS_TEST_DIRNAME/../bin/timer"

# ── Script basics ────────────────────────────────────────────────

@test "timer script exists and is executable" {
  [ -f "$TIMER_CMD" ]
  [ -x "$TIMER_CMD" ]
}

@test "timer script has correct shebang" {
  head -1 "$TIMER_CMD" | grep -q '#!/bin/bash'
}

# ── --help output ────────────────────────────────────────────────

@test "timer --help prints usage" {
  run "$TIMER_CMD" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"timer"* ]]
}

@test "timer --help mentions default 25 min" {
  run "$TIMER_CMD" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"25"* ]]
}

# ── Zero-duration timer (completion path) ────────────────────────

@test "timer 0 completes immediately with done message" {
  run bash -c "'$TIMER_CMD' 0 Test 2>/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Test"* ]]
  [[ "$output" == *"done"* ]]
}

@test "timer 0 includes label in output" {
  run bash -c "'$TIMER_CMD' 0 MyLabel 2>/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"MyLabel"* ]]
}

@test "timer 0 with default label says Focus" {
  run bash -c "'$TIMER_CMD' 0 2>/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Focus"* ]]
}

# ── Start message format ─────────────────────────────────────────

@test "timer shows duration and time range on start" {
  # Use 0 to avoid blocking; the start line is printed before the loop
  run bash -c "'$TIMER_CMD' 0 2>/dev/null"
  [ "$status" -eq 0 ]
  # Start line has format: ⏱  Focus — 0 min (HH:MM → HH:MM)
  [[ "$output" == *"0 min"* ]]
}

# ── Ctrl+C handling ──────────────────────────────────────────────

@test "timer has SIGINT trap for clean cancellation" {
  grep -q "trap.*INT" "$TIMER_CMD"
  # The trap outputs "cancelled" on Ctrl+C
  grep -q "cancelled" "$TIMER_CMD"
}
