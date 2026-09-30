#!/usr/bin/env bats

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"
  mkdir -p "$TEST_HOME/.local/state/dotfiles" "$TEST_DOTFILES/bin" "$TEST_DOTFILES/lib"
  cp "$BATS_TEST_DIRNAME/../lib/dotfiles-endpoint-paths.sh" "$TEST_DOTFILES/lib/"
  mkdir -p "$TEST_DOTFILES/stubs/opt/homebrew/bin"
  cp /bin/echo "$TEST_DOTFILES/stubs/opt/homebrew/bin/jq"
  chmod +x "$TEST_DOTFILES/stubs/opt/homebrew/bin/jq"
  codesign --sign - --force "$TEST_DOTFILES/stubs/opt/homebrew/bin/jq" >/dev/null 2>&1 || true
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "dotfiles-adhoc-sign-jq: signs Homebrew jq when unsigned" {
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-adhoc-sign-jq" "$TEST_DOTFILES/bin/"
  chmod +x "$TEST_DOTFILES/bin/dotfiles-adhoc-sign-jq"
  run env HOME="$TEST_HOME" DOTFILES_BREW_PREFIX="$TEST_DOTFILES/stubs/opt/homebrew" \
    "$TEST_DOTFILES/bin/dotfiles-adhoc-sign-jq"
  [ "$status" -eq 0 ]
  run codesign -dvv "$TEST_DOTFILES/stubs/opt/homebrew/bin/jq" 2>&1
  [[ "$output" == *"Signature=adhoc"* ]]
}

@test "dotfiles-adhoc-sign-ggrep: signs Homebrew ggrep when unsigned" {
  cp /bin/echo "$TEST_DOTFILES/stubs/opt/homebrew/bin/ggrep"
  chmod +x "$TEST_DOTFILES/stubs/opt/homebrew/bin/ggrep"
  codesign --remove-signature "$TEST_DOTFILES/stubs/opt/homebrew/bin/ggrep" >/dev/null 2>&1 || true
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-adhoc-sign-ggrep" "$TEST_DOTFILES/bin/"
  chmod +x "$TEST_DOTFILES/bin/dotfiles-adhoc-sign-ggrep"
  run env HOME="$TEST_HOME" DOTFILES_BREW_PREFIX="$TEST_DOTFILES/stubs/opt/homebrew" \
    "$TEST_DOTFILES/bin/dotfiles-adhoc-sign-ggrep"
  [ "$status" -eq 0 ]
  run codesign -dvv "$TEST_DOTFILES/stubs/opt/homebrew/bin/ggrep" 2>&1
  [[ "$output" == *"Signature=adhoc"* ]]
}

@test "dotfiles-adhoc-sign-curl: signs Homebrew curl keg when unsigned" {
  mkdir -p "$TEST_DOTFILES/stubs/opt/homebrew/opt/curl/bin"
  cp /bin/echo "$TEST_DOTFILES/stubs/opt/homebrew/opt/curl/bin/curl"
  chmod +x "$TEST_DOTFILES/stubs/opt/homebrew/opt/curl/bin/curl"
  codesign --remove-signature "$TEST_DOTFILES/stubs/opt/homebrew/opt/curl/bin/curl" >/dev/null 2>&1 || true
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-adhoc-sign-curl" "$TEST_DOTFILES/bin/"
  chmod +x "$TEST_DOTFILES/bin/dotfiles-adhoc-sign-curl"
  run env HOME="$TEST_HOME" DOTFILES_BREW_PREFIX="$TEST_DOTFILES/stubs/opt/homebrew" \
    "$TEST_DOTFILES/bin/dotfiles-adhoc-sign-curl"
  [ "$status" -eq 0 ]
  run codesign -dvv "$TEST_DOTFILES/stubs/opt/homebrew/opt/curl/bin/curl" 2>&1
  [[ "$output" == *"Signature=adhoc"* ]]
}

@test "run_at_login_endpoint-bootstrap: writes endpoint-ready sentinel" {
  cat > "$TEST_DOTFILES/bin/dotfiles-adhoc-sign-uv-pythons" <<'EOF'
#!/bin/bash
exit 0
EOF
  cat > "$TEST_DOTFILES/bin/dotfiles-adhoc-sign-jq" <<'EOF'
#!/bin/bash
exit 0
EOF
  cat > "$TEST_DOTFILES/bin/dotfiles-adhoc-sign-curl" <<'EOF'
#!/bin/bash
exit 0
EOF
  cat > "$TEST_DOTFILES/bin/dotfiles-adhoc-sign-ggrep" <<'EOF'
#!/bin/bash
exit 0
EOF
  cat > "$TEST_DOTFILES/bin/dotfiles-link-python-shim" <<'EOF'
#!/bin/bash
exit 0
EOF
  cat > "$TEST_DOTFILES/bin/dotfiles-link-jq-shim" <<'EOF'
#!/bin/bash
set -euo pipefail
SHIM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BREW_JQ="${DOTFILES_BREW_PREFIX:-/opt/homebrew}/bin/jq"
ln -sfn "$BREW_JQ" "$SHIM_DIR/jq"
EOF
  cat > "$TEST_DOTFILES/bin/dotfiles-link-curl-shim" <<'EOF'
#!/bin/bash
set -euo pipefail
SHIM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BREW_CURL="${DOTFILES_BREW_PREFIX:-/opt/homebrew}/opt/curl/bin/curl"
ln -sfn "$BREW_CURL" "$SHIM_DIR/curl"
EOF
  cat > "$TEST_DOTFILES/bin/dotfiles-link-grep-shim" <<'EOF'
#!/bin/bash
set -euo pipefail
SHIM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BREW_GREP="${DOTFILES_BREW_PREFIX:-/opt/homebrew}/bin/ggrep"
ln -sfn "$BREW_GREP" "$SHIM_DIR/grep"
ln -sfn "$BREW_GREP" "$SHIM_DIR/ggrep"
EOF
  chmod +x "$TEST_DOTFILES/bin/"*
  mkdir -p "$TEST_DOTFILES/.chezmoiscripts"
  cp "$BATS_TEST_DIRNAME/../.chezmoiscripts/run_at_login_endpoint-bootstrap.sh" \
    "$TEST_DOTFILES/.chezmoiscripts/run_at_login_endpoint-bootstrap.sh"
  chmod +x "$TEST_DOTFILES/.chezmoiscripts/run_at_login_endpoint-bootstrap.sh"
  rm -f "$TEST_HOME/.local/state/dotfiles/endpoint-ready"
  run env HOME="$TEST_HOME" DOTFILES_DIR="$TEST_DOTFILES" DOTFILES_BREW_PREFIX="$TEST_DOTFILES/stubs/opt/homebrew" \
    bash "$TEST_DOTFILES/.chezmoiscripts/run_at_login_endpoint-bootstrap.sh"
  [ "$status" -eq 0 ]
  [ -f "$TEST_HOME/.local/state/dotfiles/endpoint-ready" ]
}

@test "endpoint-bootstrap plist template exists" {
  [ -f "$BATS_TEST_DIRNAME/../launchagents/com.dotfiles.endpoint-bootstrap.plist.tmpl" ]
  grep -q 'run_at_login_endpoint-bootstrap.sh' \
    "$BATS_TEST_DIRNAME/../launchagents/com.dotfiles.endpoint-bootstrap.plist.tmpl"
}
