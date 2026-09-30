#!/usr/bin/env bats
# Tests for note — quick developer notes script

load test_helper

NOTE_CMD="$BATS_TEST_DIRNAME/../bin/note"

@test "note script exists and is executable" {
  [ -f "$NOTE_CMD" ]
  [ -x "$NOTE_CMD" ]
}

@test "note script uses set -euo pipefail" {
  grep -q 'set -euo pipefail' "$NOTE_CMD"
}

@test "note with no args and no notes shows 'No notes' message" {
  run "$NOTE_CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No notes for"* ]]
}

@test "note creates .notes directory under HOME" {
  run "$NOTE_CMD"
  [ -d "$HOME/.notes" ]
}

@test "note saves a note to today's file" {
  run "$NOTE_CMD" "fixed the auth bug"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Note saved"* ]]

  today=$(date +%Y-%m-%d)
  [ -f "$HOME/.notes/$today.md" ]
  grep -q "fixed the auth bug" "$HOME/.notes/$today.md"
}

@test "note prepends timestamp to entry" {
  run "$NOTE_CMD" "test entry"
  [ "$status" -eq 0 ]

  today=$(date +%Y-%m-%d)
  # Entry format: - HH:MM <text>
  grep -qE '^- [0-9]{2}:[0-9]{2} test entry$' "$HOME/.notes/$today.md"
}

@test "note appends multiple entries to same file" {
  "$NOTE_CMD" "first note"
  "$NOTE_CMD" "second note"

  today=$(date +%Y-%m-%d)
  count=$(wc -l < "$HOME/.notes/$today.md" | tr -d ' ')
  [ "$count" -eq 2 ]
  grep -q "first note" "$HOME/.notes/$today.md"
  grep -q "second note" "$HOME/.notes/$today.md"
}

@test "note with no args displays today's notes" {
  "$NOTE_CMD" "hello world"

  run "$NOTE_CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello world"* ]]
}

@test "note --search with no query exits 1" {
  run "$NOTE_CMD" --search
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: note --search"* ]]
}

@test "note --search finds matching text" {
  "$NOTE_CMD" "important finding"

  run "$NOTE_CMD" --search "important"
  [ "$status" -eq 0 ]
  [[ "$output" == *"important finding"* ]]
}

@test "note --search shows 'No matches' for missing text" {
  "$NOTE_CMD" "something else"

  run "$NOTE_CMD" --search "nonexistent-query-xyz"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No matches"* ]]
}

@test "note --week shows notes from this week" {
  "$NOTE_CMD" "weekly check"

  run "$NOTE_CMD" --week
  [ "$status" -eq 0 ]
  [[ "$output" == *"weekly check"* ]]
}

@test "note --week shows nothing when no notes exist" {
  run "$NOTE_CMD" --week
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "note --month shows notes from this month" {
  "$NOTE_CMD" "monthly review"

  run "$NOTE_CMD" --month
  [ "$status" -eq 0 ]
  [[ "$output" == *"monthly review"* ]]
}

@test "note --month shows nothing when no notes exist" {
  run "$NOTE_CMD" --month
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "note preserves multi-word arguments" {
  run "$NOTE_CMD" "this has many words in it"
  [ "$status" -eq 0 ]

  today=$(date +%Y-%m-%d)
  grep -q "this has many words in it" "$HOME/.notes/$today.md"
}
