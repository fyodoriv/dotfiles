#!/usr/bin/env bats
# lib/errors-log.sh and its callers: allow-listed fields only, off in tests,
# and every doctor failing line carries its fix (docs/observability.md).

REPO_ROOT="$BATS_TEST_DIRNAME/.."

setup() {
  TEST_DIR="$(mktemp -d)"
  export DOTFILES_ERRORS_FILE="$TEST_DIR/errors.jsonl"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "log_error writes one JSON line with story, source, code, and check" {
  run env DOTFILES_ERRORS_LOG=1 bash -c "source '$REPO_ROOT/lib/errors-log.sh'; log_error US05 doctor check_failed git.user_name"
  [ "$status" -eq 0 ]
  jq -e '.story == "US05" and .source == "doctor" and .code == "check_failed" and .check == "git.user_name" and (.ts | test("^20"))' "$DOTFILES_ERRORS_FILE"
}

@test "log_error replaces any value outside its allow-list, so no free text is logged" {
  run env DOTFILES_ERRORS_LOG=1 bash -c "source '$REPO_ROOT/lib/errors-log.sh'; log_error 'my story' 'curl evil' 'path /Users/me/secret' 'id with spaces'"
  [ "$status" -eq 0 ]
  jq -e '.story == "invalid" and .source == "invalid" and .code == "invalid" and .check == "invalid"' "$DOTFILES_ERRORS_FILE"
  ! grep -q 'secret\|evil\|spaces' "$DOTFILES_ERRORS_FILE"
  [ "$(jq -r 'keys | join(",")' "$DOTFILES_ERRORS_FILE")" = "check,code,source,story,ts" ]
}

@test "DOTFILES_ERRORS_LOG=0 turns the log off" {
  run env DOTFILES_ERRORS_LOG=0 bash -c "source '$REPO_ROOT/lib/errors-log.sh'; log_error US05 doctor check_failed"
  [ "$status" -eq 0 ]
  [ ! -e "$DOTFILES_ERRORS_FILE" ]
}

@test "test runs turn the errors log off (Makefile and test_helper)" {
  grep -qE '^export DOTFILES_ERRORS_LOG *:?= *0' "$REPO_ROOT/Makefile"
  grep -qE '^export DOTFILES_ERRORS_LOG=0' "$REPO_ROOT/tests/test_helper.bash"
  grep -qE '^export DOTFILES_STATS_LOG *:?= *0' "$REPO_ROOT/Makefile"
  grep -qE '^export DOTFILES_STATS_LOG=0' "$REPO_ROOT/tests/test_helper.bash"
}

@test "log_run allow-lists its fields and DOTFILES_STATS_LOG=0 turns it off" {
  local f="$TEST_DIR/stats.jsonl"
  run env DOTFILES_STATS_LOG=1 DOTFILES_STATS_FILE="$f" bash -c "source '$REPO_ROOT/lib/stats.sh'; log_run 'sync; rm -rf /Users/me' 'lots'"
  [ "$status" -eq 0 ]
  jq -e '.task == "invalid" and .units == 1' "$f"
  ! grep -q 'rm -rf' "$f"
  rm -f "$f"
  run env DOTFILES_STATS_LOG=0 DOTFILES_STATS_FILE="$f" bash -c "source '$REPO_ROOT/lib/stats.sh'; log_run sync"
  [ ! -e "$f" ]
}

@test "a failing doctor check line ends with its fix and logs a US05 event" {
  local mod="$TEST_DIR/extra/fix-hint"
  mkdir -p "$mod"
  printf 'check "fix-hint.auto" "has an auto-fix" "false" "true"\n' >> "$mod/doctor.sh"
  printf 'check "fix-hint.manual" "has no auto-fix" "false" ""\n' >> "$mod/doctor.sh"
  run env HOME="$TEST_DIR/home" DOTFILES_STATS_FILE="$TEST_DIR/stats.jsonl" DOTFILES_ERRORS_LOG=1 \
    EXTRA_DOCTOR_DIR="$TEST_DIR/extra" "$REPO_ROOT/bin/dotfiles-doctor" --module fix-hint
  [ "$status" -eq 1 ]
  [[ "$output" == *"has an auto-fix — fix: dotfiles doctor --fix --module fix-hint"* ]]
  [[ "$output" == *"has no auto-fix — fix: no auto-fix; follow docs/module-reference.md (fix-hint)"* ]]
  [ "$(jq -s '[.[] | select(.story == "US05" and .source == "doctor")] | length' "$DOTFILES_ERRORS_FILE")" -eq 2 ]
}

@test "every fail line in the doctor carries a fix" {
  # A new fail call must add " — fix: …" (or _fix_hint) on the same line.
  run bash -c "grep -nE '\\bfail \"' '$REPO_ROOT/bin/dotfiles-doctor' | grep -vE 'fix: |_fix_hint'"
  [ -z "$output" ] || { echo "fail lines without a fix: $output"; return 1; }
}

@test "inside bats, both logs stay off unless the test turns them on" {
  local s="$TEST_DIR/s.jsonl"
  run env -u DOTFILES_STATS_LOG -u DOTFILES_ERRORS_LOG DOTFILES_STATS_FILE="$s" bash -c "source '$REPO_ROOT/lib/stats.sh'; source '$REPO_ROOT/lib/errors-log.sh'; log_run sync; log_error US05 sync push_failed"
  [ "$status" -eq 0 ]
  [ ! -e "$s" ]
  [ ! -e "$DOTFILES_ERRORS_FILE" ]
}
