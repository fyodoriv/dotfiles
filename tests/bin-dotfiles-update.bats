#!/usr/bin/env bats
load test_helper

SCRIPT="$BATS_TEST_DIRNAME/../bin/dotfiles-update"
REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

make_recording_stub() {
  local stub_path="$1" command_name="$2" invocations="$3" exit_code="${4:-0}"
  cat > "$stub_path" <<STUB
#!/usr/bin/env bash
printf '%s' "$command_name" >> "$invocations"
if [ "\$#" -gt 0 ]; then
  printf ' %s' "\$@" >> "$invocations"
fi
printf '\n' >> "$invocations"
exit $exit_code
STUB
  chmod +x "$stub_path"
}

copy_script_to_test_repo() {
  mkdir -p "$TEST_DOTFILES/bin"
  cp "$SCRIPT" "$TEST_DOTFILES/bin/dotfiles-update"
  chmod +x "$TEST_DOTFILES/bin/dotfiles-update"
  touch "$TEST_DOTFILES/Agentfile.yaml"
}


@test "dry-run prints phases without executing commands" {
  local stub_bin invocations command_name
  stub_bin="$TEST_DIR/bin"
  invocations="$TEST_DIR/invocations"
  mkdir -p "$stub_bin"
  for command_name in git dotfiles agentbrew dotfiles-upgrade dotfiles-doctor; do
    cat > "$stub_bin/$command_name" <<STUB
#!/usr/bin/env bash
echo "$command_name $*" >> "$invocations"
exit 0
STUB
    chmod +x "$stub_bin/$command_name"
  done

  run env PATH="$stub_bin:/usr/bin:/bin" "$SCRIPT" --dry-run

  [ "$status" -eq 0 ]
  [ ! -e "$invocations" ]
  [[ "$output" == *"DRY-RUN: git -C $REPO pull --rebase"* ]]
  [[ "$output" == *"DRY-RUN: dotfiles apply"* ]]
  [[ "$output" == *"DRY-RUN: agentbrew sync --pull --agentfile $REPO/Agentfile.yaml"* ]]
  [[ "$output" == *"DRY-RUN: dotfiles-upgrade"* ]]
  [[ "$output" == *"DRY-RUN: dotfiles-doctor --fix"* ]]
}

@test "normal run executes phases in order" {
  local stub_bin invocations command_name expected
  stub_bin="$TEST_DIR/bin"
  invocations="$TEST_DIR/invocations"
  mkdir -p "$stub_bin"
  for command_name in git dotfiles agentbrew dotfiles-upgrade dotfiles-doctor; do
    make_recording_stub "$stub_bin/$command_name" "$command_name" "$invocations"
  done
  copy_script_to_test_repo

  run env PATH="$stub_bin:/usr/bin:/bin" "$TEST_DOTFILES/bin/dotfiles-update"

  expected="git -C $TEST_DOTFILES pull --rebase
""dotfiles apply
""agentbrew sync --pull --agentfile $TEST_DOTFILES/Agentfile.yaml
""dotfiles-upgrade
""dotfiles-doctor --fix"
  [ "$status" -eq 0 ]
  [ "$(cat "$invocations")" = "$expected" ]
}

@test "missing agentbrew skips refresh and continues" {
  local stub_bin invocations command_name expected
  stub_bin="$TEST_DIR/bin"
  invocations="$TEST_DIR/invocations"
  mkdir -p "$stub_bin"
  for command_name in git dotfiles dotfiles-upgrade dotfiles-doctor; do
    make_recording_stub "$stub_bin/$command_name" "$command_name" "$invocations"
  done
  copy_script_to_test_repo

  run env PATH="$stub_bin:/usr/bin:/bin" "$TEST_DOTFILES/bin/dotfiles-update"

  expected="git -C $TEST_DOTFILES pull --rebase
""dotfiles apply
""dotfiles-upgrade
""dotfiles-doctor --fix"
  [ "$status" -eq 0 ]
  [[ "$output" == *"○ agentbrew not available — skipping agent config refresh"* ]]
  [ "$(cat "$invocations")" = "$expected" ]
}

@test "phase failure stops later phases and reports exit code" {
  local stub_bin invocations expected
  stub_bin="$TEST_DIR/bin"
  invocations="$TEST_DIR/invocations"
  mkdir -p "$stub_bin"
  make_recording_stub "$stub_bin/git" git "$invocations"
  make_recording_stub "$stub_bin/dotfiles" dotfiles "$invocations" 42
  make_recording_stub "$stub_bin/agentbrew" agentbrew "$invocations"
  make_recording_stub "$stub_bin/dotfiles-upgrade" dotfiles-upgrade "$invocations"
  make_recording_stub "$stub_bin/dotfiles-doctor" dotfiles-doctor "$invocations"
  copy_script_to_test_repo

  run env PATH="$stub_bin:/usr/bin:/bin" "$TEST_DOTFILES/bin/dotfiles-update"

  expected="git -C $TEST_DOTFILES pull --rebase
""dotfiles apply"
  [ "$status" -eq 42 ]
  [[ "$output" == *"✗ Phase failed: apply (exit 42)"* ]]
  [ "$(cat "$invocations")" = "$expected" ]
}
