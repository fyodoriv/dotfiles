#!/usr/bin/env bats
# Tests for the stale Amphetamine Single-Use sleep assertion check added to
# modules/resilience/doctor.sh in 2026-09-27.
#
# Sources the doctor.sh and exercises the `_amphetamine_no_stale_single_use_assertion`
# helper directly with a stubbed `pmset` binary and a fake app dir via the
# AMPHETAMINE_APP_PATH env override (the override is a test-only hatch — the
# default points at /Applications/Amphetamine.app).
#
# Each test seeds:
#   - PMSET_STUB_OUTPUT_FILE — file the stub `pmset` cat's on -g assertions
#   - AMPHETAMINE_APP_PATH   — fake "installed" directory
#   - AMPHETAMINE_DISPLAY_SLEEP_MAX_HOURS — threshold to compare against
#
# Acceptance criteria from P2 task `amphetamine-stale-single-use-session-doctor`:
#   - ✓ when held <threshold
#   - ⚠ advisory when held ≥threshold (function returns non-zero so `check_advisory`
#         routes to audit_warn)
#   - clean skip when Amphetamine isn't installed
#   - clean skip when pmset isn't available
#   - threshold tunable via AMPHETAMINE_DISPLAY_SLEEP_MAX_HOURS

setup() {
  TEST_DIR="$(mktemp -d)"
  STUB_BIN="$TEST_DIR/stub-bin"
  FAKE_APP="$TEST_DIR/Amphetamine.app"
  PMSET_STUB_OUTPUT_FILE="$TEST_DIR/pmset-assertions.txt"
  mkdir -p "$STUB_BIN" "$FAKE_APP"

  # Stub pmset that prints whatever PMSET_STUB_OUTPUT_FILE points at when
  # invoked with `-g assertions` (and exits cleanly for any other args).
  cat > "$STUB_BIN/pmset" <<EOF
#!/bin/bash
if [ "\$1" = "-g" ] && [ "\$2" = "assertions" ]; then
  cat "$PMSET_STUB_OUTPUT_FILE" 2>/dev/null || exit 0
  exit 0
fi
exit 0
EOF
  chmod +x "$STUB_BIN/pmset"

  cat > "$STUB_BIN/defaults" <<'EOF'
#!/bin/bash
if [ "$1" = "read" ] && [ "$2" = "com.if.Amphetamine" ]; then
  case "$3" in
    "Trigger Data") printf '%s\n' "${DEFAULTS_TRIGGER_DATA:-()}" ;;
    "Enable Triggers") printf '%s\n' "${DEFAULTS_ENABLE_TRIGGERS:-0}" ;;
    "Start Session At Launch") printf '%s\n' "${DEFAULTS_START_SESSION_AT_LAUNCH:-0}" ;;
    "Start Session On Wake") printf '%s\n' "${DEFAULTS_START_SESSION_ON_WAKE:-0}" ;;
    "Restart DD Session on AC Reconnect") printf '%s\n' "${DEFAULTS_RESTART_ON_AC_RECONNECT:-0}" ;;
  esac
elif [ "$1" = "write" ] && [ "$2" = "com.if.Amphetamine" ]; then
  printf '%s|%s|%s|%s\n' "$2" "$3" "$4" "$5" >> "$DEFAULTS_WRITES_FILE"
fi
EOF
  chmod +x "$STUB_BIN/defaults"

  export PATH="$STUB_BIN:$PATH"
  export AMPHETAMINE_APP_PATH="$FAKE_APP"
  export DEFAULTS_WRITES_FILE="$TEST_DIR/defaults-writes.txt"
  export DEFAULTS_TRIGGER_DATA="()"
  export DEFAULTS_ENABLE_TRIGGERS=0
  export DEFAULTS_START_SESSION_AT_LAUNCH=0
  export DEFAULTS_START_SESSION_ON_WAKE=0
  export DEFAULTS_RESTART_ON_AC_RECONNECT=0

  # Source the doctor helpers. We avoid sourcing the entire doctor.sh because
  # that would also try to evaluate the `check`/`check_advisory` calls.
  local doctor_sh="$BATS_TEST_DIRNAME/../modules/resilience/doctor.sh"
  [ -f "$doctor_sh" ] || { echo "doctor.sh not found: $doctor_sh"; return 1; }
  # Extract the helper function block bounded by `_amphetamine_no_stale_single_use_assertion() {` and `^}`.
  local helper_src
  helper_src="$(awk '
    /^_amphetamine_no_stale_single_use_assertion\(\)/ { in_func = 1 }
    in_func { print }
    in_func && /^}/ { exit }
  ' "$doctor_sh")"
  [ -n "$helper_src" ] || { echo "helper not found in doctor.sh"; return 1; }
  eval "$helper_src"

  local policy_src
  policy_src="$(awk '
    /^_amphetamine_managed_session_policy\(\)/ { in_func = 1 }
    in_func { print }
    in_func && /^}/ { exit }
  ' "$doctor_sh")"
  [ -n "$policy_src" ] || { echo "policy helper not found in doctor.sh"; return 1; }
  eval "$policy_src"

  local fix_src
  fix_src="$(awk '
    /^_amphetamine_apply_managed_session_policy\(\)/ { in_func = 1 }
    in_func { print }
    in_func && /^}/ { exit }
  ' "$doctor_sh")"
  [ -n "$fix_src" ] || { echo "policy fix helper not found in doctor.sh"; return 1; }
  eval "$fix_src"

  # The stale-session helper recognizes a valid manager-owned session through
  # this library API. Keep it false by default to exercise manual detection.
  dotfiles_agent_amphetamine_session_is_owned() {
    [ "${AMPHETAMINE_MANAGER_OWNS_SESSION:-0}" = "1" ]
  }
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── Skip paths ─────────────────────────────────────────────────────

@test "amphetamine-stale: clean pass when Amphetamine.app is not installed" {
  export AMPHETAMINE_APP_PATH="$TEST_DIR/no-amphetamine.app"
  run _amphetamine_no_stale_single_use_assertion
  [ "$status" -eq 0 ]
}

@test "amphetamine-stale: clean pass when AMPHETAMINE_APP_PATH points at nonexistent dir" {
  export AMPHETAMINE_APP_PATH="$TEST_DIR/nonexistent-app"
  run _amphetamine_no_stale_single_use_assertion
  [ "$status" -eq 0 ]
}

@test "amphetamine-stale: clean pass when pmset is not available" {
  # Empty PATH so command -v pmset returns nothing.
  PATH="" run _amphetamine_no_stale_single_use_assertion
  [ "$status" -eq 0 ]
}

# ── Threshold logic ────────────────────────────────────────────────

@test "amphetamine-stale: passes when held <threshold (default 12h)" {
  # 5h assertion, default 12h threshold → pass
  cat > "$PMSET_STUB_OUTPUT_FILE" <<'EOF'
Assertion status system-wide:
   PreventUserIdleDisplaySleep    1
Listed by owning process:
   pid 1033(Amphetamine): [0x0000003d0005833f] 05:00:00 PreventUserIdleDisplaySleep named: "Amphetamine (Single-Use - Display)"
EOF
  run _amphetamine_no_stale_single_use_assertion
  [ "$status" -eq 0 ]
}

@test "amphetamine-stale: fails when held >threshold (default 12h)" {
  # 66h42m assertion (the original incident) → fail (advisory warn)
  cat > "$PMSET_STUB_OUTPUT_FILE" <<'EOF'
Assertion status system-wide:
   PreventUserIdleDisplaySleep    1
Listed by owning process:
   pid 1033(Amphetamine): [0x0000003d0005833f] 66:42:00 PreventUserIdleDisplaySleep named: "Amphetamine (Single-Use - Display)"
EOF
  run _amphetamine_no_stale_single_use_assertion
  [ "$status" -ne 0 ]
}

@test "amphetamine-stale: fails when held EXACTLY at threshold (>= boundary)" {
  # 12h exactly → fail (the check is "< threshold", so equality is stale)
  cat > "$PMSET_STUB_OUTPUT_FILE" <<'EOF'
Assertion status system-wide:
   PreventUserIdleDisplaySleep    1
Listed by owning process:
   pid 1033(Amphetamine): [0x0000003d0005833f] 12:00:00 PreventUserIdleDisplaySleep named: "Amphetamine (Single-Use - Display)"
EOF
  run _amphetamine_no_stale_single_use_assertion
  [ "$status" -ne 0 ]
}

@test "amphetamine-stale: respects AMPHETAMINE_DISPLAY_SLEEP_MAX_HOURS override (tighter)" {
  # 3h assertion, tighter 2h threshold → fail
  export AMPHETAMINE_DISPLAY_SLEEP_MAX_HOURS=2
  cat > "$PMSET_STUB_OUTPUT_FILE" <<'EOF'
Assertion status system-wide:
   PreventUserIdleDisplaySleep    1
Listed by owning process:
   pid 1033(Amphetamine): [0x0000003d0005833f] 03:00:00 PreventUserIdleDisplaySleep named: "Amphetamine (Single-Use - Display)"
EOF
  run _amphetamine_no_stale_single_use_assertion
  [ "$status" -ne 0 ]
}

@test "amphetamine-stale: respects AMPHETAMINE_DISPLAY_SLEEP_MAX_HOURS override (looser)" {
  # 14h assertion, looser 24h threshold → pass
  export AMPHETAMINE_DISPLAY_SLEEP_MAX_HOURS=24
  cat > "$PMSET_STUB_OUTPUT_FILE" <<'EOF'
Assertion status system-wide:
   PreventUserIdleDisplaySleep    1
Listed by owning process:
   pid 1033(Amphetamine): [0x0000003d0005833f] 14:00:00 PreventUserIdleDisplaySleep named: "Amphetamine (Single-Use - Display)"
EOF
  run _amphetamine_no_stale_single_use_assertion
  [ "$status" -eq 0 ]
}

# ── Edge cases ─────────────────────────────────────────────────────

@test "amphetamine-stale: passes when no Amphetamine assertion is held" {
  # pmset output exists but doesn't mention Amphetamine
  cat > "$PMSET_STUB_OUTPUT_FILE" <<'EOF'
Assertion status system-wide:
   PreventUserIdleDisplaySleep    1
Listed by owning process:
   pid 1234(caffeinate): [0x0000003d000aaaaa] 22:00:00 PreventUserIdleDisplaySleep named: "caffeinate command-line tool"
EOF
  run _amphetamine_no_stale_single_use_assertion
  [ "$status" -eq 0 ]
}

@test "amphetamine-stale: detects a stale Amphetamine system-sleep assertion" {
  # A session configured to allow display sleep still blocks system sleep.
  # It must be caught or an indefinite Single-Use session can recur unseen.
  cat > "$PMSET_STUB_OUTPUT_FILE" <<'EOF'
Assertion status system-wide:
   PreventUserIdleSystemSleep    1
Listed by owning process:
   pid 1033(Amphetamine): [0x0000003d0001833e] 99:00:00 PreventUserIdleSystemSleep named: "Amphetamine (Single-Use - System)"
EOF
  run _amphetamine_no_stale_single_use_assertion
  [ "$status" -ne 0 ]
}

@test "amphetamine-stale: ignores a stale Trigger display assertion" {
  cat > "$PMSET_STUB_OUTPUT_FILE" <<'EOF'
Assertion status system-wide:
   PreventUserIdleDisplaySleep    1
Listed by owning process:
   pid 1033(Amphetamine): [0x0000003d0005833f] 50:00:00 PreventUserIdleDisplaySleep named: "Amphetamine (Trigger A)"
EOF
  run _amphetamine_no_stale_single_use_assertion
  [ "$status" -eq 0 ]
}

@test "amphetamine-stale: fails when a stale Single-Use assertion accompanies a fresh Trigger" {
  # The trigger is intentional; the stale Single-Use assertion is not.
  cat > "$PMSET_STUB_OUTPUT_FILE" <<'EOF'
Assertion status system-wide:
   PreventUserIdleDisplaySleep    2
Listed by owning process:
   pid 1033(Amphetamine): [0x0000003d0005833f] 01:00:00 PreventUserIdleDisplaySleep named: "Amphetamine (Trigger A)"
   pid 1033(Amphetamine): [0x0000003d0005833a] 50:00:00 PreventUserIdleDisplaySleep named: "Amphetamine (Single-Use - Display)"
EOF
  run _amphetamine_no_stale_single_use_assertion
  [ "$status" -ne 0 ]
}

@test "amphetamine-stale: accepts a valid manager-owned long-running session" {
  export AMPHETAMINE_MANAGER_OWNS_SESSION=1
  cat > "$PMSET_STUB_OUTPUT_FILE" <<'EOF'
Assertion status system-wide:
   PreventUserIdleSystemSleep    1
Listed by owning process:
   pid 1033(Amphetamine): [0x0000003d0001833e] 99:00:00 PreventUserIdleSystemSleep named: "Amphetamine (Single-Use - System)"
EOF
  run _amphetamine_no_stale_single_use_assertion
  [ "$status" -eq 0 ]
}

@test "amphetamine-stale: handles minutes-and-seconds precision correctly" {
  # 11h59m59s — just under 12h threshold → pass
  cat > "$PMSET_STUB_OUTPUT_FILE" <<'EOF'
Assertion status system-wide:
   PreventUserIdleDisplaySleep    1
Listed by owning process:
   pid 1033(Amphetamine): [0x0000003d0005833f] 11:59:59 PreventUserIdleDisplaySleep named: "Amphetamine (Single-Use - Display)"
EOF
  run _amphetamine_no_stale_single_use_assertion
  [ "$status" -eq 0 ]
}

# ── Automatic-session policy ────────────────────────────────────────

@test "amphetamine-policy: passes the manager-owned baseline" {
  run _amphetamine_managed_session_policy
  [ "$status" -eq 0 ]
}

@test "amphetamine-policy: rejects generic Trigger sessions" {
  export DEFAULTS_TRIGGER_DATA="({})"
  export DEFAULTS_ENABLE_TRIGGERS=1
  export DEFAULTS_START_SESSION_AT_LAUNCH=1
  run _amphetamine_managed_session_policy
  [ "$status" -ne 0 ]
}

@test "amphetamine-policy: fails an unbounded automatic Single-Use policy" {
  export DEFAULTS_START_SESSION_AT_LAUNCH=1
  run _amphetamine_managed_session_policy
  [ "$status" -ne 0 ]
}

@test "amphetamine-policy: fix restores the manager-owned settings" {
  run _amphetamine_apply_managed_session_policy
  [ "$status" -eq 0 ]
  grep -Fx 'com.if.Amphetamine|Start Session At Launch|-bool|false' "$DEFAULTS_WRITES_FILE"
  grep -Fx 'com.if.Amphetamine|Start Session On Wake|-bool|false' "$DEFAULTS_WRITES_FILE"
  grep -Fx 'com.if.Amphetamine|Restart DD Session on AC Reconnect|-bool|false' "$DEFAULTS_WRITES_FILE"
  grep -Fx 'com.if.Amphetamine|Allow Display Sleep|-bool|true' "$DEFAULTS_WRITES_FILE"
  grep -Fx 'com.if.Amphetamine|Allow Closed-Display Sleep|-bool|false' "$DEFAULTS_WRITES_FILE"
  grep -Fx 'com.if.Amphetamine|Enable Triggers|-bool|false' "$DEFAULTS_WRITES_FILE"
  grep -Fx 'com.if.Amphetamine|Trigger Data|-array|' "$DEFAULTS_WRITES_FILE"
}
