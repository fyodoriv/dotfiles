#!/usr/bin/env bats
# bin/dotfiles-mcp-launch: secrets by reference, CA bundle, minimal PATH,
# and refusal of unpinned packages (issue #145, step 8).

load test_helper

LAUNCH="$BATS_TEST_DIRNAME/../bin/dotfiles-mcp-launch"

setup() {
  TEST_DIR="$(mktemp -d)"
  mkdir -p "$TEST_DIR/stub"
  cat > "$TEST_DIR/stub/security" <<'STUB'
#!/bin/sh
[ "$1" = find-generic-password ] && [ "$3" = acme-jira-token ] && { echo s3cr3t-value; exit 0; }
exit 44
STUB
  chmod +x "$TEST_DIR/stub/security"
  export DOTFILES_SECURITY_BIN="$TEST_DIR/stub/security"
  unset JIRA_TOKEN
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "a keychain secret reaches only the launched command" {
  run "$LAUNCH" --secret JIRA_TOKEN=keychain:acme-jira-token -- /bin/sh -c 'printf %s "$JIRA_TOKEN"'
  [ "$status" -eq 0 ]
  [ "$output" = s3cr3t-value ]
  [ -z "${JIRA_TOKEN:-}" ]
}

@test "a missing keychain item fails without starting the command" {
  run "$LAUNCH" --secret JIRA_TOKEN=keychain:nope -- /usr/bin/touch "$TEST_DIR/ran"
  [ "$status" -eq 2 ]
  [[ "$output" == *"keychain item not found: nope"* ]]
  [ ! -f "$TEST_DIR/ran" ]
}

@test "only keychain references are accepted" {
  run "$LAUNCH" --secret JIRA_TOKEN=plain-value -- /usr/bin/true
  [ "$status" -eq 2 ]
  [[ "$output" == *"only keychain:<item>"* ]]
}

@test "--ca-bundle sets the three CA variables" {
  touch "$TEST_DIR/ca.pem"
  run "$LAUNCH" --ca-bundle "$TEST_DIR/ca.pem" -- /bin/sh -c 'echo "$SSL_CERT_FILE|$NODE_EXTRA_CA_CERTS|$REQUESTS_CA_BUNDLE"'
  [ "$output" = "$TEST_DIR/ca.pem|$TEST_DIR/ca.pem|$TEST_DIR/ca.pem" ]
}

@test "--path-minimal keeps only the command folder and system dirs" {
  run "$LAUNCH" --path-minimal -- /usr/bin/env
  [[ "$output" == *"PATH=/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin"* ]]
}

@test "@latest and unpinned npx -y are refused" {
  run "$LAUNCH" -- npx -y some-mcp@latest
  [ "$status" -eq 2 ]
  [[ "$output" == *"unpinned package: some-mcp@latest"* ]]
  run "$LAUNCH" -- npx -y some-mcp
  [ "$status" -eq 2 ]
  [[ "$output" == *"unpinned package: npx -y some-mcp"* ]]
  run "$LAUNCH" -- /bin/echo -y some-mcp
  [ "$status" -eq 0 ]
}
