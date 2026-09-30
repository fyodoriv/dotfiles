#!/usr/bin/env bats
# Tests for network-watchdog — verify and restore network connectivity

WATCHDOG="$BATS_TEST_DIRNAME/../bin/network-watchdog"
NETWORK_PLIST="$BATS_TEST_DIRNAME/../launchagents/com.dotfiles.network-resilience.plist.tmpl"

@test "network-watchdog exists and is executable" {
  [ -x "$WATCHDOG" ]
}

@test "network-watchdog has correct shebang" {
  head -1 "$WATCHDOG" | grep -q '#!/bin/bash'
}

@test "network-watchdog uses strict mode" {
  grep -q 'set -euo pipefail' "$WATCHDOG"
}

@test "network-watchdog sources colors.sh" {
  grep -q 'source.*colors.sh' "$WATCHDOG"
}

@test "network-watchdog supports --quiet flag" {
  grep -q '\-\-quiet' "$WATCHDOG"
  grep -q 'QUIET=' "$WATCHDOG"
}

@test "network-watchdog creates log directory with error check" {
  grep -q 'mkdir -p.*|| {' "$WATCHDOG"
}

@test "network-watchdog trims log to 500 lines" {
  grep -q 'tail -n 500' "$WATCHDOG"
}

@test "network-watchdog cleans up tmp file on trim failure" {
  grep -q 'rm -f.*\.tmp' "$WATCHDOG"
}

@test "network-watchdog checks wifi on en0" {
  grep -q 'ipconfig getifaddr en0' "$WATCHDOG"
}

@test "network-watchdog checks secondary interfaces" {
  grep -q 'en1 en2 en3' "$WATCHDOG"
}

@test "network-watchdog flushes dns cache on failure" {
  grep -q 'dscacheutil -flushcache' "$WATCHDOG"
  grep -q 'mDNSResponder' "$WATCHDOG"
}

@test "network-watchdog VPN process check is opt-in via env var" {
  grep -q 'NETWORK_WATCHDOG_VPN_PROCESS:-' "$WATCHDOG"
}

@test "network-watchdog verifies end-to-end connectivity" {
  grep -q '/usr/bin/nc.*-z.*-w' "$WATCHDOG"
}

@test "network-watchdog never spawns curl from its recurring background job" {
  ! grep -vE '^[[:space:]]*#' "$WATCHDOG" | grep -qE '(^|[[:space:]])curl([[:space:]]|$)'
}

@test "network-watchdog requires 2 of 3 endpoints for success" {
  grep -q 'ok_count -ge 2' "$WATCHDOG"
}

@test "network-watchdog treats the VPN process check as non-fatal" {
  grep -q 'check_vpn_process.*|| true' "$WATCHDOG"
}

@test "network-watchdog has wifi wait timeout of 30s" {
  grep -q 'max_wait=30' "$WATCHDOG"
}

@test "network-watchdog has dns wait timeout of 15s" {
  # In wait_for_dns function
  grep -q 'max_wait=15' "$WATCHDOG"
}

# ── --check-only mode ────────────────────────────────────────────────

@test "network-watchdog supports --check-only flag" {
  grep -q '\-\-check-only' "$WATCHDOG"
}

@test "--check-only does not source colors.sh" {
  # --check-only exits before sourcing colors.sh, so it has zero overhead
  # Verify the exit 0 comes before the source line
  local check_exit_line source_line
  check_exit_line=$(grep -n 'exit 0' "$WATCHDOG" | head -1 | cut -d: -f1)
  source_line=$(grep -n 'source.*colors.sh' "$WATCHDOG" | head -1 | cut -d: -f1)
  [ "$check_exit_line" -lt "$source_line" ]
}

@test "--check-only does not use sudo" {
  # Extract only the --check-only block and verify no sudo
  local block
  block=$(awk '/--check-only/,/^fi/' "$WATCHDOG")
  echo "$block" | grep -qv 'sudo'
}

@test "--check-only does not check the VPN process" {
  # The --check-only block (between the if and the first fi) should not mention the VPN check
  local block
  block=$(sed -n '/if.*--check-only/,/^fi/p' "$WATCHDOG" | head -20)
  ! echo "$block" | grep -q 'VPN\|vpn'
}

@test "--check-only checks wifi, dns, and tcp" {
  local block
  block=$(awk '/--check-only/,/^fi/' "$WATCHDOG")
  echo "$block" | grep -q 'ipconfig getifaddr'
  echo "$block" | grep -q 'host -W'
  echo "$block" | grep -q 'probe_target'
}

@test "--check-only produces no output on success" {
  # When network is actually up, should produce zero output
  run "$WATCHDOG" --check-only
  [ ${#output} -eq 0 ] || [ "$status" -eq 1 ]  # either silent success or network actually down
}

# ── Configurable targets ──────────────────────────────────────────

@test "network-watchdog supports configurable targets via env var" {
  grep -q 'DOTFILES_NETWORK_TARGETS' "$WATCHDOG"
}

@test "network-watchdog supports configurable targets via config file" {
  grep -q 'network-targets.txt' "$WATCHDOG"
}

@test "network-watchdog has sensible default targets" {
  # Default targets are universal (no AI service URLs — those are gated on use_ai_tools)
  grep -q 'github.com' "$WATCHDOG"
  grep -q '1.1.1.1' "$WATCHDOG"
}

@test "network-watchdog derives DNS host from first target" {
  grep -q 'DNS_HOST=' "$WATCHDOG"
}

@test "network-watchdog prepends endpoint-security tool paths" {
  grep -q 'dotfiles-endpoint-paths.sh' "$WATCHDOG"
  grep -q 'dotfiles_prepend_endpoint_tool_paths' "$WATCHDOG"
}

@test "network-resilience avoids noisy SystemConfiguration WatchPaths" {
  ! grep -q '<key>WatchPaths</key>' "$NETWORK_PLIST"
  grep -q '<key>StartInterval</key>' "$NETWORK_PLIST"
}
