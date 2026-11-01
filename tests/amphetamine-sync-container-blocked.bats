#!/usr/bin/env bats
# Tests for bin/dotfiles-amphetamine-sync when macOS privacy protection
# blocks the Amphetamine app container.
#
# In that state `defaults export com.if.Amphetamine` prints an empty dict
# and exits 0. Before the fix, `diff` compared that empty dict with the
# committed baseline and reported false drift, as if the user had to pick a
# sync direction.
#
# Each test copies the script into a fake dotfiles dir and stubs
# `defaults` so it behaves like the blocked container.

setup() {
  TEST_DIR="$(mktemp -d)"
  FAKE_DOTFILES="$TEST_DIR/dotfiles"
  STUB_BIN="$TEST_DIR/stub-bin"
  mkdir -p "$FAKE_DOTFILES/bin" "$FAKE_DOTFILES/data" "$STUB_BIN" "$TEST_DIR/Amphetamine.app"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-amphetamine-sync" "$FAKE_DOTFILES/bin/"
  mkdir -p "$FAKE_DOTFILES/lib"
  cp "$BATS_TEST_DIRNAME/../lib/run-with-timeout.sh" "$FAKE_DOTFILES/lib/"
  cat > "$FAKE_DOTFILES/data/amphetamine-prefs.json" <<'EOF'
{
  "Enable Triggers": 0,
  "Trigger Data": []
}
EOF

  # Blocked-container `defaults`: export writes an empty plist and exits 0.
  cat > "$STUB_BIN/defaults" <<'EOF'
#!/bin/bash
if [ -n "${DEFAULTS_HANG:-}" ]; then
  # Simulates the unanswerable macOS privacy prompt (issue #359).
  sleep 30
  exit 0
fi
if [ "$1" = "export" ] && [ -n "${DEFAULTS_WITH_DATE:-}" ]; then
  # Readable container whose plist holds a date in a key we do not sync.
  cat > "$3" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
<key>Enable Triggers</key>
<integer>0</integer>
<key>Other Time Clock Last Selection</key>
<date>2026-10-29T21:58:00Z</date>
<key>Trigger Data</key>
<array/>
</dict>
</plist>
PLIST
  exit 0
fi
if [ "$1" = "export" ]; then
  cat > "$3" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
PLIST
  exit 0
fi
exit 0
EOF
  chmod +x "$STUB_BIN/defaults"
  export PATH="$STUB_BIN:$PATH"
  export AMPHETAMINE_APP_PATH="$TEST_DIR/Amphetamine.app"

  CONTAINER="$TEST_DIR/Containers/com.if.Amphetamine"
  mkdir -p "$CONTAINER/Data/Library/Preferences"
  export AMPHETAMINE_CONTAINER_DIR="$CONTAINER"
}

teardown() {
  chmod -R u+rwx "$TEST_DIR" 2>/dev/null || true
  rm -rf "$TEST_DIR"
}

@test "diff reports a blocked container instead of false drift" {
  chmod 000 "$CONTAINER/Data/Library/Preferences"
  run "$FAKE_DOTFILES/bin/dotfiles-amphetamine-sync" diff
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot read Amphetamine preferences"* ]]
  [[ "$output" == *"Full Disk Access"* ]]
  [[ "$output" != *"drift detected"* ]]
}

@test "export refuses to overwrite the baseline when the container is blocked" {
  chmod 000 "$CONTAINER/Data/Library/Preferences"
  run "$FAKE_DOTFILES/bin/dotfiles-amphetamine-sync" export
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot read Amphetamine preferences"* ]]
  run jq -r '."Enable Triggers"' "$FAKE_DOTFILES/data/amphetamine-prefs.json"
  [ "$output" = "0" ]
}

@test "apply fails instead of reporting success when the container is blocked" {
  chmod 000 "$CONTAINER/Data/Library/Preferences"
  run "$FAKE_DOTFILES/bin/dotfiles-amphetamine-sync" apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot read Amphetamine preferences"* ]]
  [[ "$output" != *"apply complete"* ]]
}

@test "diff still reports real drift when the container is readable" {
  run "$FAKE_DOTFILES/bin/dotfiles-amphetamine-sync" diff
  [ "$status" -ne 0 ]
  [[ "$output" == *"drift detected"* ]]
  [[ "$output" != *"cannot read Amphetamine preferences"* ]]
}

@test "diff warns and stops when defaults hangs on the privacy prompt (issue #359)" {
  export DEFAULTS_HANG=1 AMPHETAMINE_DEFAULTS_TIMEOUT_SEC=1
  local start=$SECONDS
  run "$FAKE_DOTFILES/bin/dotfiles-amphetamine-sync" diff
  [ "$status" -ne 0 ]
  [ $((SECONDS - start)) -lt 10 ]
  [[ "$output" == *"cannot read Amphetamine prefs (privacy prompt?)"* ]]
}

@test "status warns instead of hanging when defaults hangs (issue #359)" {
  export DEFAULTS_HANG=1 AMPHETAMINE_DEFAULTS_TIMEOUT_SEC=1
  local start=$SECONDS
  run "$FAKE_DOTFILES/bin/dotfiles-amphetamine-sync" status
  [ "$status" -eq 0 ]
  [ $((SECONDS - start)) -lt 10 ]
  [[ "$output" == *"cannot read Amphetamine prefs (privacy prompt?)"* ]]
}

# plutil cannot turn a plist with a date into JSON. Amphetamine writes a date
# when you pick a time in its menu, and diff then failed on every run.
@test "diff ignores a date in a key it does not sync" {
  export DEFAULTS_WITH_DATE=1
  run "$FAKE_DOTFILES/bin/dotfiles-amphetamine-sync" diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"no drift"* ]]
}
