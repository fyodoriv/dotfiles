#!/usr/bin/env bats
# The doctor expects com.dotfiles.endpoint-bootstrap only when apply installs
# it: endpoint_hardening on (same default as apply).

load test_helper

@test "security doctor checks endpoint-bootstrap only with endpoint_hardening on" {
  DOCTOR="$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  grep -B2 '"security.endpoint_bootstrap_la"' "$DOCTOR" | grep -q 'if \[ "$_endpoint_hardening_on" = "true" \]; then'
}

@test "doctor reads endpoint_hardening with the launchagents default" {
  grep -q 'dig "endpoint_hardening" true .' "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor"
  grep -q 'dig "endpoint_hardening" true .' "$BATS_TEST_DIRNAME/../.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
}

# Run the gated block with stub check functions; print the check ids it adds.
_bootstrap_checks() {
  local block
  block="$(sed -n '/^# Apply installs endpoint-bootstrap only/,/^fi$/p' "$BATS_TEST_DIRNAME/../modules/security/doctor.sh")"
  ( ENDPOINT_HARDENING="$1"; check() { echo "$1"; }; check_advisory() { echo "$1"; }; eval "$block" )
}

@test "endpoint_hardening on (true or 1) runs the endpoint-bootstrap checks" {
  for v in true 1 ""; do
    run _bootstrap_checks "$v"
    [[ "$output" == *"security.endpoint_bootstrap_la"* ]]
    [[ "$output" == *"security.endpoint_bootstrap_sentinel"* ]]
  done
}

@test "endpoint_hardening off (false or 0) skips the endpoint-bootstrap checks" {
  for v in false 0; do
    run _bootstrap_checks "$v"
    [ -z "$output" ]
  done
}

# Endpoint-agent PATH and publisher checks warn only where an endpoint agent
# runs; a Mac with endpoint_hardening off got about 10 warnings it never needs.
@test "bash minimal-PATH and Homebrew-sandbox checks run only with endpoint_hardening on" {
  DOCTOR="$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  grep -B3 '"security.bash_minimal_path_endpoint"' "$DOCTOR" | grep -q 'if \[ "$_endpoint_hardening_on" = "true" \]; then'
  grep -q 'if \[ "$_endpoint_hardening_on" = "true" \] && \[ -d /opt/homebrew/bin \]; then' "$DOCTOR"
  grep -B2 '"security.python3_publisher_authority"' "$DOCTOR" | grep -q 'case "${ENDPOINT_HARDENING:-true}" in true|1)'
}

_path_check_ids() {
  _endpoint_hardening_on="$1"
  check_advisory() { printf '%s\n' "$1"; }
  source <(sed -n '/^# Agent \/ CI sandboxes/,/^# Agent tool shells/p' "$BATS_TEST_DIRNAME/../modules/security/doctor.sh")
}

@test "endpoint hardening off keeps common zsh PATH checks and skips bash endpoint checks" {
  run _path_check_ids false
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^security.zsh_minimal_path_')" -eq 4 ]
  [[ "$output" != *security.bash_minimal_path_* ]]
}

@test "endpoint hardening on registers both shell PATH check sets" {
  run _path_check_ids true
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^security.zsh_minimal_path_')" -eq 4 ]
  [ "$(printf '%s\n' "$output" | grep -c '^security.bash_minimal_path_')" -eq 4 ]
}
