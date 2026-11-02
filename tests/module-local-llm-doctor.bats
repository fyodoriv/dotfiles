#!/usr/bin/env bats
# local-llm doctor must follow the same use_local_ai toggle as the installer.

setup() {
  TEST_DIR="$(mktemp -d)"
  STUB_DIR="$TEST_DIR/bin"
  mkdir -p "$STUB_DIR"
  export DOTFILES_DIR="$BATS_TEST_DIRNAME/.."
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME"
  # No hf, huggingface-cli, aider, or pipx on PATH.
  export PATH="$STUB_DIR:/usr/bin:/bin"
  export CHECK_LOG="$TEST_DIR/checks.log"
}

teardown() {
  rm -rf "$TEST_DIR"
}

run_local_llm_doctor() {
  check() {
    printf 'check\t%s\n' "$1" >> "$CHECK_LOG"
  }
  check_advisory() {
    printf 'advisory\t%s\n' "$1" >> "$CHECK_LOG"
  }
  skipped() {
    printf 'skipped\t%s\n' "$1" >> "$CHECK_LOG"
  }
  # shellcheck disable=SC1091
  source "$DOTFILES_DIR/modules/local-llm/doctor.sh"
}

@test "use_local_ai false skips the module instead of warning" {
  USE_LOCAL_AI=false run run_local_llm_doctor
  [ "$status" -eq 0 ]
  grep -q $'^skipped\tlocal-llm checks (use_local_ai is off)' "$CHECK_LOG"
  ! grep -q $'^check\t' "$CHECK_LOG"
  ! grep -q $'^advisory\t' "$CHECK_LOG"
}

@test "use_local_ai false still lists check IDs in --list mode" {
  LIST_MODE=true USE_LOCAL_AI=false run run_local_llm_doctor
  [ "$status" -eq 0 ]
  grep -q $'^check\tlocal-llm.huggingface_cli' "$CHECK_LOG"
}

@test "use_local_ai false still yields check IDs when skipped is undefined" {
  run_without_skipped() {
    check() { printf 'check\t%s\n' "$1" >> "$CHECK_LOG"; }
    check_advisory() { printf 'advisory\t%s\n' "$1" >> "$CHECK_LOG"; }
    unset -f skipped
    # shellcheck disable=SC1091
    source "$DOTFILES_DIR/modules/local-llm/doctor.sh"
  }
  USE_LOCAL_AI=false run run_without_skipped
  [ "$status" -eq 0 ]
  [[ "$output" != *"command not found"* ]]
  grep -q $'^check\tlocal-llm.huggingface_cli' "$CHECK_LOG"
}

@test "use_local_ai true keeps the huggingface CLI check as a hard check" {
  USE_LOCAL_AI=true run run_local_llm_doctor
  [ "$status" -eq 0 ]
  grep -q $'check\tlocal-llm.huggingface_cli' "$CHECK_LOG"
}

@test "use_local_ai unset keeps the huggingface CLI check as a hard check" {
  unset USE_LOCAL_AI
  run run_local_llm_doctor
  [ "$status" -eq 0 ]
  grep -q $'check\tlocal-llm.huggingface_cli' "$CHECK_LOG"
}
