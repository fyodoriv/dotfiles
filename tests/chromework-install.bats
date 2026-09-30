#!/usr/bin/env bats
# Tests for bin/chromework-install
#
# Locked-in invariants:
#   1. Idempotency — running twice in a row with the same inputs produces
#      no rebuild on the second run.
#   2. Drift detection — when the AppleScript inside the .app no longer
#      mentions --user-data-dir= or the expected --profile-directory=, a
#      rebuild is triggered.
#   3. Privacy/portability — the script reads work_email_domain from
#      `chezmoi execute-template`, so a non-enterprise user gets the
#      "example.com" fallback baked in, NOT a corporate identifier.
#   4. Profile detection — when Local State maps a non-Default profile dir
#      to the work email domain, the generated AppleScript uses that dir.

load test_helper

SCRIPT="$BATS_TEST_DIRNAME/../bin/chromework-install"

# Stub PATH with fakes for chezmoi, osacompile, osadecompile, plutil,
# lsregister, defaultbrowser. Tests can override the chezmoi work_email_domain
# via the WORK_DOMAIN env var.
setup_stubs() {
  local work_domain="${WORK_DOMAIN:-example.com}"
  STUB_BIN="$TEST_DIR/stub-bin"
  mkdir -p "$STUB_BIN"

  cat > "$STUB_BIN/chezmoi" <<EOF
#!/bin/bash
case "\$*" in
  *work_email_domain*) echo "$work_domain" ;;
  *is_enterprise*) echo "true" ;;
  *) echo "" ;;
esac
EOF
  chmod +x "$STUB_BIN/chezmoi"

  # osacompile stub: just record what would have been compiled. The real
  # tool writes a binary .scpt; we just write the source so osadecompile-
  # stub can return it.
  cat > "$STUB_BIN/osacompile" <<'EOF'
#!/bin/bash
# Usage: osacompile -o <out> <in>
out=""; in=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    *) in="$1"; shift ;;
  esac
done
if [[ "$out" == *.app ]]; then
  mkdir -p "$out/Contents/Resources/Scripts" "$out/Contents/MacOS"
  cp "$in" "$out/Contents/Resources/Scripts/main.scpt"
  /usr/bin/plutil -create xml1 "$out/Contents/Info.plist"
else
  mkdir -p "$(dirname "$out")"
  cp "$in" "$out"
fi
EOF
  chmod +x "$STUB_BIN/osacompile"

  # osadecompile stub: read the main.scpt as plain text (since osacompile
  # stub wrote source there).
  cat > "$STUB_BIN/osadecompile" <<'EOF'
#!/bin/bash
app="$1"
cat "$app/Contents/Resources/Scripts/main.scpt" 2>/dev/null
EOF
  chmod +x "$STUB_BIN/osadecompile"

  # plutil stub: log invocations, delegate to the real tool so plist keys persist.
  cat > "$STUB_BIN/plutil" <<'EOF'
#!/bin/bash
echo "plutil $*" >> "$HOME/.plutil-calls"
exec /usr/bin/plutil "$@"
EOF
  chmod +x "$STUB_BIN/plutil"

  # lsregister stub: no-op (it's invoked via absolute path so this only
  # catches accidental PATH calls).
  cat > "$STUB_BIN/lsregister" <<'EOF'
#!/bin/bash
echo "lsregister $*" >> "$HOME/.lsregister-calls"
EOF
  chmod +x "$STUB_BIN/lsregister"
  export CHROMEWORK_LSREGISTER="$STUB_BIN/lsregister"

  # defaultbrowser stub: emulate "no router currently set, will accept switch"
  cat > "$STUB_BIN/defaultbrowser" <<'EOF'
#!/bin/bash
case "${1:-}" in
  browser)
    echo "* browser" > "$HOME/.defaultbrowser-state"
    ;;
  *)
    cat "$HOME/.defaultbrowser-state" 2>/dev/null || echo "* chrome"
    ;;
esac
EOF
  chmod +x "$STUB_BIN/defaultbrowser"

  # Fake a Google Chrome.app so the script doesn't exit 2.
  export CHROME_APP_DIR="$TEST_DIR/Google Chrome.app"
  mkdir -p "$CHROME_APP_DIR/Contents/MacOS"
  touch "$CHROME_APP_DIR/Contents/MacOS/Google Chrome"
  chmod +x "$CHROME_APP_DIR/Contents/MacOS/Google Chrome"

  export CHROME_USER_DATA_DIR="$TEST_HOME/Library/Application Support/Google/Chrome"
  export CHROMEWORK_APP_DIR="$TEST_HOME/Applications/ChromeWork.app"
  export PATH="$STUB_BIN:$PATH"
}

write_local_state() {
  local profile_dir="${1:-Default}" user="${2:-alice@example.com}"
  local path="$CHROME_USER_DATA_DIR/Local State"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<JSON
{
  "profile": {
    "info_cache": {
      "$profile_dir": {"name": "Work", "user_name": "$user"},
      "Profile 99": {"name": "Other", "user_name": ""}
    },
    "last_used": "$profile_dir"
  }
}
JSON
}

@test "chromework-install: script exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "chromework-install: --help prints comment header" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "ChromeWork"
}

@test "chromework-install: exits 2 when Chrome.app is missing" {
  setup_stubs
  rm -rf "$CHROME_APP_DIR"
  run "$SCRIPT"
  [ "$status" -eq 2 ]
}

@test "chromework-install: first install builds the .app with correct profile" {
  setup_stubs
  write_local_state "Default" "alice@example.com"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -d "$CHROMEWORK_APP_DIR" ]
  grep -q -- "on routeURL" "$CHROMEWORK_APP_DIR/Contents/Resources/Scripts/main.scpt"
  grep -q 'chromework-open-url' \
    "$CHROMEWORK_APP_DIR/Contents/Resources/Scripts/main.scpt"
  ! grep -q -- "--user-data-dir=" \
    "$CHROMEWORK_APP_DIR/Contents/Resources/Scripts/main.scpt"
  [ "$(plutil -extract OSAAppletShowStartupScreen raw "$CHROMEWORK_APP_DIR/Contents/Info.plist")" = "false" ]
  [ "$(plutil -extract LSUIElement raw "$CHROMEWORK_APP_DIR/Contents/Info.plist")" = "true" ]
}

@test "chromework-install: delegates URL opens to chromework-open-url helper" {
  setup_stubs
  write_local_state "Default" "alice@example.com"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  helper_path="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/bin/chromework-open-url"
  osadecompile "$CHROMEWORK_APP_DIR" | grep -Fq "$helper_path"
}

@test "chromework-install: open-url helper path is baked into the router" {
  setup_stubs
  write_local_state "Profile 3" "alice@example.com"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  helper_path="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/bin/chromework-open-url"
  osadecompile "$CHROMEWORK_APP_DIR" | grep -Fq "$helper_path"
}

@test "chromework-install: routeURL activates Work Chrome in applet context" {
  setup_stubs
  write_local_state "Default" "alice@example.com"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  decompiled="$(osadecompile "$CHROMEWORK_APP_DIR")"
  echo "$decompiled" | grep -q 'on activateWorkChrome'
  echo "$decompiled" | grep -q 'tell application "Google Chrome"'
  echo "$decompiled" | grep -q 'count of windows'
  echo "$decompiled" | grep -q 'chromework-activate'
  echo "$decompiled" | grep -q -- '--survive-handoff'
  echo "$decompiled" | grep -q -- '--no-activate'
}

@test "chromework-install: idempotent — second run reports up-to-date" {
  setup_stubs
  write_local_state "Default" "alice@example.com"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "already up to date"
}

@test "chromework-install: reasserts default browser after an up-to-date install" {
  # LaunchServices can drift independently of the generated router bundle.
  # Keep the repair call after the rebuild/up-to-date branch so both successful
  # install paths repair raw Chrome/Safari without mutating --check runs.
  grep -q '^\[ "$MODE" = "check" \] || _reassert_chromework_default$' "$SCRIPT"
}

@test "chromework-install: repairs a raw Chrome default browser" {
  setup_stubs
  eval "$(awk '/^_reassert_chromework_default\(\)/ {p=1} p {print} p && /^}/ {exit}' "$SCRIPT")"
  _chromework_is_production_router() { return 0; }

  printf '* chrome\n' > "$HOME/.defaultbrowser-state"
  _reassert_chromework_default

  [ "$(cat "$HOME/.defaultbrowser-state")" = "* browser" ]
}

@test "chromework-install: repairs every raw browser drift state on enterprise" {
  setup_stubs
  eval "$(awk '/^_reassert_chromework_default\(\)/ {p=1} p {print} p && /^}/ {exit}' "$SCRIPT")"
  _chromework_is_production_router() { return 0; }

  local current
  for current in safari testing velja finicky ""; do
    printf '* %s\n' "$current" > "$HOME/.defaultbrowser-state"
    _reassert_chromework_default
    [ "$(cat "$HOME/.defaultbrowser-state")" = "* browser" ]
  done
}

@test "chromework-install: leaves ChromeWork as the default when already selected" {
  setup_stubs
  printf '%s\n' "* browser" > "$HOME/.defaultbrowser-state"
  eval "$(awk '/^_reassert_chromework_default\(\)/ {p=1} p {print} p && /^}/ {exit}' "$SCRIPT")"
  _chromework_is_production_router() { return 0; }

  run _reassert_chromework_default

  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.defaultbrowser-state")" = "* browser" ]
  [ -z "$output" ]
}

@test "chromework-install: skips default repair without defaultbrowser" {
  setup_stubs
  eval "$(awk '/^_reassert_chromework_default\(\)/ {p=1} p {print} p && /^}/ {exit}' "$SCRIPT")"
  _chromework_is_production_router() { return 0; }
  local empty_path="$TEST_DIR/empty"
  local original_path="$PATH"
  mkdir -p "$empty_path"
  PATH="$empty_path"

  run _reassert_chromework_default

  PATH="$original_path"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.defaultbrowser-state" ]
}

@test "chromework-install: skips default repair on non-enterprise Macs" {
  setup_stubs
  STUB_BIN="$TEST_DIR/stub-bin"
  cat > "$STUB_BIN/chezmoi" <<'EOF'
#!/bin/bash
case "$*" in
  *is_enterprise*) echo "false" ;;
  *work_email_domain*) echo "example.com" ;;
  *) echo "" ;;
esac
EOF
  chmod +x "$STUB_BIN/chezmoi"
  export PATH="$STUB_BIN:$PATH"
  printf '* velja\n' > "$HOME/.defaultbrowser-state"
  eval "$(awk '/^_reassert_chromework_default\(\)/ {p=1} p {print} p && /^}/ {exit}' "$SCRIPT")"
  _chromework_is_production_router() { return 0; }

  _reassert_chromework_default

  [ "$(cat "$HOME/.defaultbrowser-state")" = "* velja" ]
}

@test "chromework-install: never changes default from a non-production router" {
  setup_stubs
  printf '%s\n' "* chrome" > "$HOME/.defaultbrowser-state"
  eval "$(awk '/^_reassert_chromework_default\(\)/ {p=1} p {print} p && /^}/ {exit}' "$SCRIPT")"
  _chromework_is_production_router() { return 1; }

  _reassert_chromework_default

  [ "$(cat "$HOME/.defaultbrowser-state")" = "* chrome" ]
}

@test "chromework-install: rejects temporary Chrome app and data paths" {
  setup_stubs
  eval "$(awk '/^_chromework_paths_look_like_test\(\)/ {p=1} p {print} p && /^}/ {exit}' "$SCRIPT")"

  CHROME_APP_DIR="/var/folders/example/T/chromework.app"
  CHROME_USER_DATA_DIR="$TEST_HOME/Chrome"
  run _chromework_paths_look_like_test
  [ "$status" -eq 0 ]

  CHROME_APP_DIR="$TEST_DIR/Google Chrome.app"
  CHROME_USER_DATA_DIR="/tmp/chromework-profile"
  run _chromework_paths_look_like_test
  [ "$status" -eq 0 ]
}

@test "chromework-install: routeURL runs open-url synchronously (no shell background)" {
  setup_stubs
  write_local_state "Default" "alice@example.com"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  decompiled="$(osadecompile "$CHROMEWORK_APP_DIR")"
  echo "$decompiled" | grep -Fq 'chromework-open-url'
  ! echo "$decompiled" | grep -q ' >/dev/null 2>&1 &'
}

@test "chromework-install: missing survive-handoff triggers rebuild" {
  setup_stubs
  write_local_state "Default" "alice@example.com"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  cat > "$CHROMEWORK_APP_DIR/Contents/Resources/Scripts/main.scpt" <<'EOF'
on routeURL(this_URL)
  my activateWorkChrome()
  do shell script "true"
end routeURL

on activateWorkChrome()
end activateWorkChrome
EOF
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Building ChromeWork.app"
  osadecompile "$CHROMEWORK_APP_DIR" | grep -q -- '--survive-handoff'
}

@test "chromework-install: missing activateWorkChrome triggers rebuild" {
  setup_stubs
  write_local_state "Default" "alice@example.com"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  cat > "$CHROMEWORK_APP_DIR/Contents/Resources/Scripts/main.scpt" <<'EOF'
on routeURL(this_URL)
  do shell script "true"
end routeURL
EOF
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Building ChromeWork.app"
  osadecompile "$CHROMEWORK_APP_DIR" | grep -q 'on activateWorkChrome'
}

@test "chromework-install: missing chromework-open-url delegation triggers rebuild" {
  setup_stubs
  write_local_state "Default" "alice@example.com"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  cat > "$CHROMEWORK_APP_DIR/Contents/Resources/Scripts/main.scpt" <<'EOF'
on routeURL(this_URL)
  do shell script "true"
end routeURL
EOF
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Building ChromeWork.app"
  grep -q 'chromework-open-url' "$CHROMEWORK_APP_DIR/Contents/Resources/Scripts/main.scpt"
}

@test "chromework-install: legacy inline chrome launch triggers rebuild" {
  setup_stubs
  write_local_state "Default" "alice@example.com"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  cat > "$CHROMEWORK_APP_DIR/Contents/Resources/Scripts/main.scpt" <<'EOF'
on routeURL(this_URL)
  do shell script "'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' --user-data-dir=/tmp " & quoted form of this_URL
end routeURL
EOF
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Building ChromeWork.app"
  grep -q 'chromework-open-url' "$CHROMEWORK_APP_DIR/Contents/Resources/Scripts/main.scpt"
}

@test "chromework-install: --force rebuilds even when up to date" {
  setup_stubs
  write_local_state "Default" "alice@example.com"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  run "$SCRIPT" --force
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Building ChromeWork.app"
}

@test "chromework-install: --check reports state without rebuilding" {
  setup_stubs
  write_local_state "Default" "alice@example.com"
  # First, install for real.
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  # Now --check should be a no-op reporting up-to-date.
  run "$SCRIPT" --check
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "up to date"
}

@test "chromework-install: --check reports rebuild needed when .app missing" {
  setup_stubs
  write_local_state "Default" "alice@example.com"
  run "$SCRIPT" --check
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "would rebuild"
}

@test "chromework-install: rejects unknown flags" {
  setup_stubs
  run "$SCRIPT" --bogus
  [ "$status" -eq 2 ]
}

@test "chromework-install: OSAAppletShowStartupScreen true triggers rebuild" {
  setup_stubs
  write_local_state "Default" "alice@example.com"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  plutil -replace OSAAppletShowStartupScreen -bool true "$CHROMEWORK_APP_DIR/Contents/Info.plist"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Building ChromeWork.app"
  [ "$(plutil -extract OSAAppletShowStartupScreen raw "$CHROMEWORK_APP_DIR/Contents/Info.plist")" = "false" ]
}

@test "chromework-install: stale helper path triggers rebuild" {
  setup_stubs
  write_local_state "Default" "alice@example.com"
  stale_helper="$TEST_DIR/stale/chromework-open-url"
  mkdir -p "$(dirname "$stale_helper")"
  printf '#!/bin/sh\n' >"$stale_helper"
  chmod +x "$stale_helper"
  CHROMEWORK_OPEN_URL_HELPER="$stale_helper" run "$SCRIPT"
  [ "$status" -eq 0 ]
  osadecompile "$CHROMEWORK_APP_DIR" | grep -Fq "$stale_helper"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Building ChromeWork.app"
  decompiled="$(osadecompile "$CHROMEWORK_APP_DIR")"
  echo "$decompiled" | grep -q 'chromework-open-url'
  ! echo "$decompiled" | grep -Fq "$stale_helper"
}

@test "chromework-install: refuses to bake bats temp paths into production router" {
  setup_stubs
  write_local_state "Default" "alice@example.com"
  export CHROME_APP_DIR="$TEST_DIR/T/tmp.testpoison/Google Chrome.app"
  export CHROME_USER_DATA_DIR="$TEST_DIR/T/tmp.testpoison/home/Library/Application Support/Google/Chrome"
  mkdir -p "$CHROME_APP_DIR/Contents/MacOS"
  touch "$CHROME_APP_DIR/Contents/MacOS/Google Chrome"
  chmod +x "$CHROME_APP_DIR/Contents/MacOS/Google Chrome"
  # Simulate leaked test env: real /Users/* HOME with temp CHROME_* paths.
  export HOME="/Users/chromework-test-user"
  export CHROMEWORK_APP_DIR="$HOME/Applications/ChromeWork.app"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "refusing to install"
}
