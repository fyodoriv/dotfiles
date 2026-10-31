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
  mkdir -p "$TEST_DOTFILES/lib"
  cp "$REPO/lib/confirm.sh" "$TEST_DOTFILES/lib/confirm.sh"
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

  run env PATH="$stub_bin:/usr/bin:/bin" "$TEST_DOTFILES/bin/dotfiles-update" --yes

  expected="git -C $TEST_DOTFILES pull --rebase
""dotfiles apply
""agentbrew sync --pull --agentfile $TEST_DOTFILES/Agentfile.yaml
""dotfiles-upgrade --yes
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

  run env PATH="$stub_bin:/usr/bin:/bin" "$TEST_DOTFILES/bin/dotfiles-update" --yes

  expected="git -C $TEST_DOTFILES pull --rebase
""dotfiles apply
""dotfiles-upgrade --yes
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

  run env PATH="$stub_bin:/usr/bin:/bin" "$TEST_DOTFILES/bin/dotfiles-update" --yes

  expected="git -C $TEST_DOTFILES pull --rebase
""dotfiles apply"
  [ "$status" -eq 42 ]
  [[ "$output" == *"✗ Phase failed: apply (exit 42)"* ]]
  [ "$(cat "$invocations")" = "$expected" ]
}

@test "without a terminal and without --yes it refuses and runs no phase" {
  local stub_bin invocations command_name
  stub_bin="$TEST_DIR/bin"
  invocations="$TEST_DIR/invocations"
  mkdir -p "$stub_bin"
  for command_name in git dotfiles agentbrew dotfiles-upgrade dotfiles-doctor; do
    make_recording_stub "$stub_bin/$command_name" "$command_name" "$invocations"
  done
  copy_script_to_test_repo

  run env PATH="$stub_bin:/usr/bin:/bin" "$TEST_DOTFILES/bin/dotfiles-update" --verbose < /dev/null

  [ "$status" -eq 2 ]
  [[ "$output" == *"--yes"* ]]
  [ ! -e "$invocations" ]
}

@test "the gate is in the script, so dotfiles update and dotfiles-update ask the same way" {
  grep -q 'confirm_yes' "$SCRIPT"
  ! awk '/^  update\)$/ { on = 1 } on && /;;/ { exit } on' "$REPO/bin/dotfiles" | grep -q 'confirm_'
}

# The apply fixture creates the merged input after update has already started.
merged_refresh_fixture() {
  local dispatch="$1" name
  STUB_BIN="$TEST_DIR/bin"
  INVOCATIONS="$TEST_DIR/invocations"
  MERGED="$HOME/.config/agentbrew/Agentfile.yaml"
  mkdir -p "$STUB_BIN"
  for name in git dotfiles-upgrade dotfiles-doctor; do
    make_recording_stub "$STUB_BIN/$name" "$name" "$INVOCATIONS"
  done
  copy_script_to_test_repo
  cat > "$STUB_BIN/dotfiles" <<'STUB'
#!/bin/bash
printf 'dotfiles %s\n' "$*" >> "$INVOCATIONS"
mkdir -p "${MERGED%/*}"
printf 'skills: [fixture-shared-skill]\nhooks:\n  - event: PreToolUse\n    matcher: Bash\n    command: echo fixture-shared-hook\n' > "$MERGED"
STUB
  cat > "$STUB_BIN/agentbrew" <<'STUB'
#!/bin/bash
printf 'agentbrew %s\n' "$*" >> "$INVOCATIONS"
while [ "$#" -gt 0 ]; do
  if [ "$1" = --agentfile ]; then cp "$2" "$SELECTED"; break; fi
  shift
done
STUB
  chmod +x "$STUB_BIN/dotfiles" "$STUB_BIN/agentbrew"
  if [ "$dispatch" = checkout ]; then
    cp "$STUB_BIN/agentbrew" "$TEST_DOTFILES/bin/agentbrew"
    printf 'agentbrew_locate() { printf "%%s\\n" "$DOTFILES_DIR"; }\n' > "$TEST_DOTFILES/lib/agentbrew-locate.sh"
  fi
  export INVOCATIONS MERGED SELECTED="$TEST_DIR/selected-agentfile"
  # Owner inputs include a private-looking but synthetic auth placeholder.
  printf 'owner-settings: preserve\n' > "$HOME/owner-settings"
  printf 'synthetic-auth-placeholder\n' > "$HOME/owner-auth"
}

@test "merged refresh keeps apply-created hook and skill through PATH dispatch" {
  merged_refresh_fixture path
  [ ! -f "$MERGED" ]
  run env PATH="$STUB_BIN:/usr/bin:/bin" "$TEST_DOTFILES/bin/dotfiles-update" --yes
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -qF "agentbrew sync --pull --agentfile $MERGED" "$INVOCATIONS"
  cmp "$MERGED" "$SELECTED"
  grep -q fixture-shared-hook "$SELECTED"
  grep -q fixture-shared-skill "$SELECTED"
  [ "$(cat "$HOME/owner-settings")" = 'owner-settings: preserve' ]
  [ "$(cat "$HOME/owner-auth")" = synthetic-auth-placeholder ]
}

@test "merged refresh keeps apply-created configuration through checkout shim dispatch" {
  merged_refresh_fixture checkout
  run env PATH="$STUB_BIN:/usr/bin:/bin" "$TEST_DOTFILES/bin/dotfiles-update" --yes
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -qF "agentbrew sync --pull --agentfile $MERGED" "$INVOCATIONS"
  cmp "$MERGED" "$SELECTED"
}

@test "merged refresh dry-run selects merged input without invoking apply or changing owner files" {
  merged_refresh_fixture path
  mkdir -p "${MERGED%/*}"
  printf 'skills: [fixture-owner-skill]\n' > "$MERGED"
  run env PATH="$STUB_BIN:/usr/bin:/bin" "$TEST_DOTFILES/bin/dotfiles-update" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"agentbrew sync --pull --agentfile $MERGED"* ]]
  [ ! -e "$INVOCATIONS" ]
  [ "$(cat "$MERGED")" = 'skills: [fixture-owner-skill]' ]
}

@test "merged refresh checkout shim falls back to base only when merged input is absent" {
  merged_refresh_fixture checkout
  make_recording_stub "$STUB_BIN/dotfiles" dotfiles "$INVOCATIONS"
  printf 'skills: [fixture-base-skill]\n' > "$TEST_DOTFILES/Agentfile.yaml"
  run env PATH="$STUB_BIN:/usr/bin:/bin" "$TEST_DOTFILES/bin/dotfiles-update" --yes
  [ "$status" -eq 0 ]
  grep -qF "agentbrew sync --pull --agentfile $TEST_DOTFILES/Agentfile.yaml" "$INVOCATIONS"
  cmp "$TEST_DOTFILES/Agentfile.yaml" "$SELECTED"
  [ ! -e "$MERGED" ]
}
