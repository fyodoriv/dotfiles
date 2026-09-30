#!/usr/bin/env bats
# Regression tests for the successful-only Homebrew bottle signature cache.

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_BIN="$TEST_DIR/bin"
  TEST_CELLAR="$TEST_DIR/Cellar"
  CODESIGN_LOG="$TEST_DIR/codesign.log"

  mkdir -p "$TEST_HOME" "$TEST_BIN" "$TEST_CELLAR/demo/1.0/bin"
  cp /bin/echo "$TEST_CELLAR/demo/1.0/bin/demo"
  chmod +x "$TEST_CELLAR/demo/1.0/bin/demo"
  : > "$CODESIGN_LOG"

  cat > "$TEST_BIN/file" <<'EOF'
#!/bin/bash
printf '%s\n' 'Mach-O 64-bit executable arm64'
EOF
  cat > "$TEST_BIN/codesign" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$CODESIGN_LOG"
case "$1" in
  -dvv)
    case "${MOCK_CODESIGN_RESULT:-signed}" in
      unsigned)
        printf '%s\n' 'code object is not signed at all'
        exit 1
        ;;
      unverifiable)
        printf '%s\n' 'codesign could not inspect this file'
        exit 1
        ;;
      developer)
        printf '%s\n' 'Signature size=4567'
        ;;
      *)
        printf '%s\n' 'Signature=adhoc'
        ;;
    esac
    ;;
  --sign)
    exit "${MOCK_CODESIGN_SIGN_STATUS:-0}"
    ;;
esac
EOF
  chmod +x "$TEST_BIN/file" "$TEST_BIN/codesign"

  export HOME="$TEST_HOME"
  export PATH="$TEST_BIN:$PATH"
  export CODESIGN_LOG
  export DOTFILES_BREW_BOTTLE_AUDIT_PREFIXES="$TEST_CELLAR"
  export DOTFILES_BREW_BOTTLE_AUDIT_CACHE_DIR="$TEST_DIR/cache"
  export DOTFILES_BREW_BOTTLE_AUDIT_FILE_BIN="$TEST_BIN/file"
  export DOTFILES_BREW_BOTTLE_AUDIT_CODESIGN_BIN="$TEST_BIN/codesign"
  export DOTFILES_BREW_BOTTLE_AUDIT_FIND_BIN="/usr/bin/find"

  source "$BATS_TEST_DIRNAME/../lib/brew-bottle-audit.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

codesign_call_count() {
  wc -l < "$CODESIGN_LOG" | tr -d ' '
}

@test "successful audit is reused while the Cellar inventory is unchanged" {
  export MOCK_CODESIGN_RESULT=developer
  dotfiles_brew_bottle_audit
  [ "$DOTFILES_BREW_BOTTLE_AUDIT_TOTAL" -eq 1 ]
  [ "$DOTFILES_BREW_BOTTLE_AUDIT_CACHE_HIT" -eq 0 ]
  [ "$(codesign_call_count)" -eq 1 ]

  dotfiles_brew_bottle_audit
  [ "$DOTFILES_BREW_BOTTLE_AUDIT_CACHE_HIT" -eq 1 ]
  [ "$(codesign_call_count)" -eq 1 ]
}

@test "a changed Cellar inventory forces a fresh audit" {
  dotfiles_brew_bottle_audit
  mkdir -p "$TEST_CELLAR/another-formula/1.0/bin"
  : > "$TEST_CELLAR/another-formula/1.0/bin/another"
  chmod +x "$TEST_CELLAR/another-formula/1.0/bin/another"

  dotfiles_brew_bottle_audit

  [ "$DOTFILES_BREW_BOTTLE_AUDIT_CACHE_HIT" -eq 0 ]
  [ "$(codesign_call_count)" -eq 3 ]
}

@test "explicit invalidation and refresh both force a fresh audit" {
  dotfiles_brew_bottle_audit
  dotfiles_brew_bottle_audit_cache_invalidate
  dotfiles_brew_bottle_audit
  [ "$(codesign_call_count)" -eq 2 ]

  DOTFILES_DOCTOR_REFRESH=1 dotfiles_brew_bottle_audit
  [ "$DOTFILES_BREW_BOTTLE_AUDIT_CACHE_HIT" -eq 0 ]
  [ "$(codesign_call_count)" -eq 3 ]
}

@test "the signing repair invalidates the successful audit cache" {
  dotfiles_brew_bottle_audit
  [ -f "$(dotfiles_brew_bottle_audit_cache_file)" ]

  export MOCK_CODESIGN_RESULT=unsigned
  run bash "$BATS_TEST_DIRNAME/../bin/dotfiles-adhoc-sign-bottles"
  [ "$status" -eq 0 ]
  [ ! -f "$(dotfiles_brew_bottle_audit_cache_file)" ]

  unset MOCK_CODESIGN_RESULT
  dotfiles_brew_bottle_audit
  [ "$DOTFILES_BREW_BOTTLE_AUDIT_CACHE_HIT" -eq 0 ]
  [ "$(codesign_call_count)" -eq 4 ]
}

@test "a no-op signing sweep preserves the successful audit cache" {
  dotfiles_brew_bottle_audit

  run bash "$BATS_TEST_DIRNAME/../bin/dotfiles-adhoc-sign-bottles"
  [ "$status" -eq 0 ]
  [ -f "$(dotfiles_brew_bottle_audit_cache_file)" ]

  dotfiles_brew_bottle_audit
  [ "$DOTFILES_BREW_BOTTLE_AUDIT_CACHE_HIT" -eq 1 ]
  [ "$(codesign_call_count)" -eq 2 ]
}

@test "unsigned and unverifiable audit results are never cached" {
  local result
  for result in unsigned unverifiable; do
    : > "$CODESIGN_LOG"
    dotfiles_brew_bottle_audit_cache_invalidate
    export MOCK_CODESIGN_RESULT="$result"

    dotfiles_brew_bottle_audit
    [ ! -f "$(dotfiles_brew_bottle_audit_cache_file)" ]
    dotfiles_brew_bottle_audit
    [ "$(codesign_call_count)" -eq 2 ]
  done
}
