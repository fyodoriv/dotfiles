#!/usr/bin/env bats

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home" VERIFY_REPO="$TEST_DIR/repo"
  export VERIFY_MARKER="$TEST_DIR/repaired"
  mkdir -p "$HOME" "$VERIFY_REPO/bin" "$VERIFY_REPO/modules/probe" "$TEST_DIR/bin"
  cp -R "$BATS_TEST_DIRNAME/../lib" "$VERIFY_REPO/lib"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor" "$VERIFY_REPO/bin/dotfiles-doctor"
  printf '#!/bin/sh\ncase "$1" in source-path) printf "%%s\\n" "$VERIFY_REPO";; *) exit 1;; esac\n' > "$TEST_DIR/bin/chezmoi"
  chmod +x "$TEST_DIR/bin/chezmoi"
  export PATH="$TEST_DIR/bin:$PATH" DOTFILES_DOCTOR_NOTIFY=0
}

teardown() { rm -rf "$TEST_DIR"; }

@test "a successful no-op repair remains failed in JSON" {
  printf 'check "probe.noop" "ineffective repair" "false" "true"\n' > "$VERIFY_REPO/modules/probe/doctor.sh"
  run bash "$VERIFY_REPO/bin/dotfiles-doctor" --module probe --fix --json
  [ "$status" -ne 0 ]
  [ "$(printf '%s' "$output" | jq -r '.[] | select(.id == "probe.noop") | .status')" = fail ]
}

@test "an effective repair is fixed after the check passes" {
  cat > "$VERIFY_REPO/modules/probe/doctor.sh" <<'SH'
check "probe.effective" "effective repair" '[ -f "$VERIFY_MARKER" ]' 'touch "$VERIFY_MARKER"'
SH
  run bash "$VERIFY_REPO/bin/dotfiles-doctor" --module probe --fix --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.[] | select(.id == "probe.effective") | .status')" = fixed ]
}

@test "a successful no-op repair explains its verification failure" {
  printf 'check "probe.noop" "ineffective repair" "false" "true"\n' > "$VERIFY_REPO/modules/probe/doctor.sh"
  run bash "$VERIFY_REPO/bin/dotfiles-doctor" --module probe --fix
  [ "$status" -ne 0 ]
  [[ "$output" == *"fix ran but the check still fails"* ]]
}

@test "a failed repair remains failed" {
  printf 'check "probe.failed" "failed repair" "false" "false"\n' > "$VERIFY_REPO/modules/probe/doctor.sh"
  run bash "$VERIFY_REPO/bin/dotfiles-doctor" --module probe --fix --json
  [ "$status" -ne 0 ]
  [ "$(printf '%s' "$output" | jq -r '.[] | select(.id == "probe.failed") | .status')" = fail ]
}

managed_fixture() {
  export VERIFY_SOURCE="$TEST_DIR/source" VERIFY_DEST="$TEST_DIR/managed"
  printf 'expected\n' > "$VERIFY_SOURCE"
  printf 'different\n' > "$VERIFY_DEST"
  cat > "$VERIFY_REPO/bin/chezmoi" <<'SH'
#!/bin/sh
case "$1" in
  source-path) printf '%s\n' "$VERIFY_REPO";;
  diff) [ -z "${VERIFY_DIFF_ERROR:-}" ] || exit 1; diff "$VERIFY_SOURCE" "$2";;
  apply) [ -n "${VERIFY_APPLY_NOOP:-}" ] || cp "$VERIFY_SOURCE" "$2";;
  *) exit 1;;
esac
SH
  chmod +x "$VERIFY_REPO/bin/chezmoi"
  printf 'check_managed "probe.managed" "$VERIFY_SOURCE" "$VERIFY_DEST"\n' > "$VERIFY_REPO/modules/probe/doctor.sh"
}

@test "a managed-file repair must leave no diff" {
  managed_fixture
  export VERIFY_APPLY_NOOP=1
  run bash "$VERIFY_REPO/bin/dotfiles-doctor" --module probe --fix --json
  [ "$status" -ne 0 ]
  [ "$(printf '%s' "$output" | jq -r '.[] | select(.id == "probe.managed") | .status')" = fail ]
}

@test "an effective managed-file repair is fixed" {
  managed_fixture
  run bash "$VERIFY_REPO/bin/dotfiles-doctor" --module probe --fix --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.[] | select(.id == "probe.managed") | .status')" = fixed ]
}

@test "an unreadable managed-file diff never counts as healthy" {
  managed_fixture
  export VERIFY_DIFF_ERROR=1 VERIFY_APPLY_NOOP=1
  run bash "$VERIFY_REPO/bin/dotfiles-doctor" --module probe --fix --json
  [ "$status" -ne 0 ]
  [ "$(printf '%s' "$output" | jq -r '.[] | select(.id == "probe.managed") | .status')" = fail ]
}

@test "repair verification refreshes the module-scoped Amphetamine preference snapshot" {
  export AMPHETAMINE_APP_PATH="$TEST_DIR/Amphetamine.app" CACHED_PREFS_STATE="$TEST_DIR/prefs"
  export VERIFY_MODULE_FUNCTIONS="$TEST_DIR/policy-functions.sh"
  mkdir -p "$AMPHETAMINE_APP_PATH"
  printf '1\n' > "$CACHED_PREFS_STATE"
  for fn in _amphetamine_read_prefs_domain _amphetamine_prefs_value _amphetamine_managed_session_policy _amphetamine_apply_managed_session_policy; do
    sed -n "/^$fn() {/,/^}/p" "$BATS_TEST_DIRNAME/../modules/resilience/doctor.sh" >> "$VERIFY_MODULE_FUNCTIONS"
  done
  cat > "$VERIFY_REPO/bin/defaults" <<'SH'
#!/bin/sh
if [ "$1" = write ]; then
  printf '0\n' > "$CACHED_PREFS_STATE"
else
  printf '{\n    "Start Session At Launch" = %s;\n    "Enable Triggers" = 0;\n    "Trigger Data" = ();\n}\n' "$(cat "$CACHED_PREFS_STATE")"
fi
SH
  chmod +x "$VERIFY_REPO/bin/defaults"
  cat > "$VERIFY_REPO/modules/probe/doctor.sh" <<'SH'
source "$DOTFILES_DIR/lib/run-with-timeout.sh"
source "$VERIFY_MODULE_FUNCTIONS"
_AMPHETAMINE_PREFS="$(_amphetamine_read_prefs_domain)"
_AMPHETAMINE_PREFS_READ=1
export -f _amphetamine_apply_managed_session_policy
check "probe.policy" "cached policy repair" "_amphetamine_managed_session_policy" "_amphetamine_apply_managed_session_policy"
SH
  run bash "$VERIFY_REPO/bin/dotfiles-doctor" --module probe --fix --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.[] | select(.id == "probe.policy") | .status')" = fixed ]
  [ "$(cat "$CACHED_PREFS_STATE")" = 0 ]
}
