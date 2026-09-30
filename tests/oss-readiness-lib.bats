#!/usr/bin/env bats

setup() {
  REPO_ROOT="$BATS_TEST_DIRNAME/.."
  # shellcheck source=../lib/oss-readiness.sh
  source "$REPO_ROOT/lib/oss-readiness.sh"
  TMP_FILE="$(mktemp -t oss-readiness-lib-test.XXXXXX)"
}

teardown() {
  [ -n "${TMP_FILE:-}" ] && rm -f "$TMP_FILE"
}

@test "email_is_safe: rejects configured private email domain" {
  OSS_READINESS_PRIVATE_EMAIL_PATTERN='@company\.example$'
  run oss_readiness_email_is_safe "alice@company.example"
  [ "$status" -ne 0 ]
}

@test "email_is_safe: accepts public domains" {
  OSS_READINESS_PRIVATE_EMAIL_PATTERN='@company\.example$'
  run oss_readiness_email_is_safe "alice@gmail.com"
  [ "$status" -eq 0 ]
  run oss_readiness_email_is_safe "alice@sent.com"
  [ "$status" -eq 0 ]
  run oss_readiness_email_is_safe "alice@users.noreply.github.com"
  [ "$status" -eq 0 ]
}

@test "email_is_safe: no configured private pattern treats email as safe" {
  OSS_READINESS_PRIVATE_EMAIL_PATTERN=''
  run oss_readiness_email_is_safe "alice@company.example"
  [ "$status" -eq 0 ]
}

@test "scan_internal_refs: catches configured private pattern" {
  OSS_READINESS_INTERNAL_PATTERN='company-private|PROJ-'
  printf 'See PROJ-123 for context.\n' > "$TMP_FILE"
  run oss_readiness_scan_internal_refs "$TMP_FILE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$TMP_FILE"* ]]
}

@test "scan_internal_refs: clean file returns no matches" {
  OSS_READINESS_INTERNAL_PATTERN='company-private|PROJ-'
  printf 'This is a generic shell script with no leaks.\n' > "$TMP_FILE"
  run oss_readiness_scan_internal_refs "$TMP_FILE"
  [ "$status" -ne 0 ]
}

@test "scan_internal_refs: no configured pattern is a no-op" {
  OSS_READINESS_INTERNAL_PATTERN=''
  printf 'company-private\n' > "$TMP_FILE"
  run oss_readiness_scan_internal_refs "$TMP_FILE"
  [ "$status" -ne 0 ]
}

@test "load_private_env: reads well-known local file under XDG_CONFIG_HOME" {
  local xdg
  xdg="$(mktemp -d)"
  mkdir -p "$xdg/oss-readiness"
  printf "OSS_READINESS_INTERNAL_PATTERN='xdg-marker'\n" > "$xdg/oss-readiness/oss-readiness.env"
  OSS_READINESS_ENV_FILE='' OSS_READINESS_INTERNAL_PATTERN='' XDG_CONFIG_HOME="$xdg" \
    run bash -c 'source "$1"; oss_readiness_load_private_env dotfiles && printf %s "$OSS_READINESS_INTERNAL_PATTERN"' _ "$REPO_ROOT/lib/oss-readiness.sh"
  rm -rf "$xdg"
  [ "$status" -eq 0 ]
  [ "$output" = "xdg-marker" ]
}

_mk_ghp() { printf '%s_%s' 'ghp' 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef0123'; }
_mk_akia() { printf '%s%s' 'AKIA' 'IOSFODNN7EXAMPLE'; }
_mk_pem_header() { printf -- '-----BEGIN %s-----' 'OPENSSH PRIVATE KEY'; }

@test "scan_secrets: catches GitHub PAT" {
  printf 'TOKEN=%s\n' "$(_mk_ghp)" > "$TMP_FILE"
  run oss_readiness_scan_secrets "$TMP_FILE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ghp_"* ]]
}

@test "scan_secrets: catches AWS access key" {
  printf 'AWS_KEY=%s\n' "$(_mk_akia)" > "$TMP_FILE"
  run oss_readiness_scan_secrets "$TMP_FILE"
  [ "$status" -eq 0 ]
}

@test "scan_secrets: catches PEM private key block" {
  printf '%s\n' "$(_mk_pem_header)" > "$TMP_FILE"
  run oss_readiness_scan_secrets "$TMP_FILE"
  [ "$status" -eq 0 ]
}

@test "scan_secrets: respects inline allowlist comment" {
  printf 'TOKEN=%s  # dotfiles-secret-allowlist: test fixture\n' "$(_mk_ghp)" > "$TMP_FILE"
  run oss_readiness_scan_secrets "$TMP_FILE"
  [ "$status" -ne 0 ]
}

@test "scan_secrets: skips *.example files" {
  local example_file="${BATS_TMPDIR}/zshenv.secrets.example"
  printf 'TOKEN=%s\n' "$(_mk_ghp)" > "$example_file"
  run oss_readiness_scan_secrets "$example_file"
  [ "$status" -ne 0 ]
  rm -f "$example_file"
}

@test "scan_secrets: clean file returns no matches" {
  printf 'echo "hello world"\n' > "$TMP_FILE"
  run oss_readiness_scan_secrets "$TMP_FILE"
  [ "$status" -ne 0 ]
}
