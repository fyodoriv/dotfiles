#!/usr/bin/env bats
# Tests for bin/chrome-enforce-profile
#
# The main regression we lock in: the script must IGNORE agent-browser Chrome
# daemons (those launched with --user-data-dir=<custom>) when deciding whether
# Chrome is "running". Otherwise the launchagent silently bails forever and
# the work profile never gets re-enforced after the user clicks into a
# different profile by accident.

load test_helper

SCRIPT="$BATS_TEST_DIRNAME/../bin/chrome-enforce-profile"

# Set up a fake PATH with stubs for chezmoi + ps. Each test seeds these via
# setup_stubs <ps_output_file> <is_enterprise>.
setup_stubs() {
  local ps_output_file="$1" is_enterprise="${2:-true}"
  STUB_BIN="$TEST_DIR/stub-bin"
  mkdir -p "$STUB_BIN"

  # chezmoi stub — returns is_enterprise / work_email_domain on demand.
  cat > "$STUB_BIN/chezmoi" <<EOF
#!/bin/bash
case "\$*" in
  *is_enterprise*) echo "$is_enterprise" ;;
  *work_email_domain*) echo "company.example" ;;
  *) echo "" ;;
esac
EOF
  chmod +x "$STUB_BIN/chezmoi"

  # ps stub — returns canned process list on `ps -axww -o command=`.
  cat > "$STUB_BIN/ps" <<EOF
#!/bin/bash
cat "$ps_output_file"
EOF
  chmod +x "$STUB_BIN/ps"

  # The dotfiles python3 wrapper (bin/python3) caches its resolved uv-managed
  # python path under \$HOME/.cache/dotfiles/uv-python3-path. With a fresh
  # test HOME the cache is empty and the wrapper calls `uv python find` which
  # spends ~10s seeding ~/.cache/uv on first run. Pre-populate the cache so
  # the wrapper short-circuits to a real interpreter immediately.
  mkdir -p "$HOME/.cache/dotfiles"
  local real_py=""
  for candidate in python3.13 python3 /usr/bin/python3; do
    [ -x "$candidate" ] && { real_py="$candidate"; break; }
  done
  [ -n "$real_py" ] || skip "no system python3 found to bypass uv wrapper"
  echo "$real_py" > "$HOME/.cache/dotfiles/uv-python3-path"

  export PATH="$STUB_BIN:$PATH"
}

write_local_state() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'JSON'
{
  "profile": {
    "info_cache": {
      "Default": {"name": "Work", "user_name": "alice@company.example"},
      "Profile 1": {"name": "Tester", "user_name": ""}
    },
    "last_used": "Profile 1",
    "last_active_profiles": ["Profile 1"],
    "show_picker_on_startup": true
  }
}
JSON
}

@test "chrome-enforce-profile: script exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "chrome-enforce-profile: --help prints comment header" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Enforce Chrome's default profile"
}

@test "chrome-enforce-profile: exits 2 when not enterprise" {
  ps_file="$TEST_DIR/ps_empty"
  : > "$ps_file"
  setup_stubs "$ps_file" "false"
  run "$SCRIPT"
  [ "$status" -eq 2 ]
}

@test "chrome-enforce-profile: exits 2 when Local State missing" {
  ps_file="$TEST_DIR/ps_empty"
  : > "$ps_file"
  setup_stubs "$ps_file" "true"
  run "$SCRIPT"
  [ "$status" -eq 2 ]
}

@test "chrome-enforce-profile: exits 2 when personal Chrome is running" {
  ps_file="$TEST_DIR/ps_personal"
  cat > "$ps_file" <<'EOF'
/Applications/Google Chrome.app/Contents/MacOS/Google Chrome
/Applications/Google Chrome.app/Contents/Frameworks/.../Google Chrome Helper --type=renderer
EOF
  setup_stubs "$ps_file" "true"
  write_local_state "$HOME/Library/Application Support/Google/Chrome/Local State"
  run "$SCRIPT"
  [ "$status" -eq 2 ]
}

@test "chrome-enforce-profile: PROCEEDS when ONLY agent-browser Chromes are running" {
  # This is the bug fix: agent-browser daemons have --user-data-dir=<custom>
  # and must NOT block the enforce pass.
  ps_file="$TEST_DIR/ps_agent_only"
  cat > "$ps_file" <<'EOF'
/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --remote-debugging-port=9223 --user-data-dir=/Users/x/.agent-browser/chrome-profile --no-first-run
/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --remote-debugging-port=9224 --user-data-dir=/Users/x/.agent-browser/debug-profile
/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --remote-debugging-port=9225 --user-data-dir=/Users/x/.agent-browser/tooling-profile
/Applications/Google Chrome.app/Contents/Frameworks/.../Google Chrome Helper --type=renderer --user-data-dir=/Users/x/.agent-browser/chrome-profile
EOF
  setup_stubs "$ps_file" "true"
  write_local_state "$HOME/Library/Application Support/Google/Chrome/Local State"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  # Local State should now be patched with Default + show_picker_on_startup=false.
  # Use jq (no fresh-HOME init cost) rather than the dotfiles python3 wrapper.
  [ "$(jq -r '.profile.last_used' "$HOME/Library/Application Support/Google/Chrome/Local State")" = "Default" ]
  [ "$(jq -r '.profile.last_active_profiles | join(",")' "$HOME/Library/Application Support/Google/Chrome/Local State")" = "Default" ]
  [ "$(jq -r '.profile.show_picker_on_startup' "$HOME/Library/Application Support/Google/Chrome/Local State")" = "false" ]
}

@test "chrome-enforce-profile: PROCEEDS when no Chrome at all is running" {
  ps_file="$TEST_DIR/ps_nothing"
  : > "$ps_file"
  setup_stubs "$ps_file" "true"
  write_local_state "$HOME/Library/Application Support/Google/Chrome/Local State"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "chrome-enforce-profile: idempotent — exits 0 when already correct" {
  ps_file="$TEST_DIR/ps_nothing"
  : > "$ps_file"
  setup_stubs "$ps_file" "true"
  mkdir -p "$HOME/Library/Application Support/Google/Chrome"
  cat > "$HOME/Library/Application Support/Google/Chrome/Local State" <<'JSON'
{
  "profile": {
    "info_cache": {"Default": {"name": "Work", "user_name": "alice@company.example"}},
    "last_used": "Default",
    "last_active_profiles": ["Default"],
    "show_picker_on_startup": false
  }
}
JSON
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]  # no "Enforced Chrome work profile" line — already correct
}

@test "chrome-enforce-profile: matches Work profile by configured work_email_domain" {
  # User signed into multiple profiles — script must pick the one whose
  # user_name contains the work domain, not blindly default to Default.
  ps_file="$TEST_DIR/ps_nothing"
  : > "$ps_file"
  setup_stubs "$ps_file" "true"
  mkdir -p "$HOME/Library/Application Support/Google/Chrome"
  cat > "$HOME/Library/Application Support/Google/Chrome/Local State" <<'JSON'
{
  "profile": {
    "info_cache": {
      "Default": {"name": "Personal", "user_name": "alice@gmail.com"},
      "Profile 2": {"name": "Work", "user_name": "alice@company.example"}
    },
    "last_used": "Default",
    "last_active_profiles": ["Default"],
    "show_picker_on_startup": true
  }
}
JSON
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.profile.last_used' "$HOME/Library/Application Support/Google/Chrome/Local State")" = "Profile 2" ]
}

@test "chrome-enforce-profile: skips patch when no work profile is found" {
  ps_file="$TEST_DIR/ps_nothing"
  : > "$ps_file"
  setup_stubs "$ps_file" "true"
  mkdir -p "$HOME/Library/Application Support/Google/Chrome"
  cat > "$HOME/Library/Application Support/Google/Chrome/Local State" <<'JSON'
{
  "profile": {
    "info_cache": {
      "Default": {"name": "Personal", "user_name": "alice@gmail.com"}
    },
    "last_used": "Default",
    "last_active_profiles": ["Default"],
    "show_picker_on_startup": true
  }
}
JSON
  run bash -c '"$1" 2>&1' _ "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.profile.last_used' "$HOME/Library/Application Support/Google/Chrome/Local State")" = "Default" ]
  echo "$output" | grep -q "skipping"
}
