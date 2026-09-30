#!/usr/bin/env bats
# Functional tests for modules/security/doctor.sh

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"

  mkdir -p "$TEST_HOME/.ssh" "$TEST_DIR/fakebin"
  mkdir -p "$TEST_DOTFILES/lib"
  mkdir -p "$TEST_DOTFILES/bin"
  cp "$BATS_TEST_DIRNAME/../lib/brew-bottle-audit.sh" "$TEST_DOTFILES/lib/brew-bottle-audit.sh"
  cp "$BATS_TEST_DIRNAME/../lib/secret-scan.sh" "$TEST_DOTFILES/lib/secret-scan.sh"
  cp "$BATS_TEST_DIRNAME/../lib/heal-stuck-agents.sh" "$TEST_DOTFILES/lib/heal-stuck-agents.sh"
  cp "$BATS_TEST_DIRNAME/../lib/dotfiles-endpoint-paths.sh" "$TEST_DOTFILES/lib/dotfiles-endpoint-paths.sh"
  cp "$BATS_TEST_DIRNAME/../lib/launchctl-timeout.sh" "$TEST_DOTFILES/lib/launchctl-timeout.sh"
  cp "$BATS_TEST_DIRNAME/../lib/dotfiles-source-dir.sh" "$TEST_DOTFILES/lib/dotfiles-source-dir.sh"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-link-curl-shim" "$TEST_DOTFILES/bin/dotfiles-link-curl-shim"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-link-jq-shim" "$TEST_DOTFILES/bin/dotfiles-link-jq-shim"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-link-python-shim" "$TEST_DOTFILES/bin/dotfiles-link-python-shim"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-link-grep-shim" "$TEST_DOTFILES/bin/dotfiles-link-grep-shim"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-link-perl-shim" "$TEST_DOTFILES/bin/dotfiles-link-perl-shim"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-link-find-shim" "$TEST_DOTFILES/bin/dotfiles-link-find-shim"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-link-sed-shim" "$TEST_DOTFILES/bin/dotfiles-link-sed-shim"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-link-awk-shim" "$TEST_DOTFILES/bin/dotfiles-link-awk-shim"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-link-git-shim" "$TEST_DOTFILES/bin/dotfiles-link-git-shim"
  chmod +x "$TEST_DOTFILES/bin/dotfiles-link-curl-shim" "$TEST_DOTFILES/bin/dotfiles-link-jq-shim" "$TEST_DOTFILES/bin/dotfiles-link-python-shim" "$TEST_DOTFILES/bin/dotfiles-link-grep-shim" "$TEST_DOTFILES/bin/dotfiles-link-perl-shim" "$TEST_DOTFILES/bin/dotfiles-link-sed-shim" "$TEST_DOTFILES/bin/dotfiles-link-awk-shim" "$TEST_DOTFILES/bin/dotfiles-link-git-shim"
  mkdir -p "$TEST_DOTFILES/stubs/opt/homebrew/opt/curl/bin"
  cp /bin/echo "$TEST_DOTFILES/stubs/opt/homebrew/opt/curl/bin/curl"
  chmod +x "$TEST_DOTFILES/stubs/opt/homebrew/opt/curl/bin/curl"
  codesign --sign - --force "$TEST_DOTFILES/stubs/opt/homebrew/opt/curl/bin/curl" >/dev/null 2>&1 || true
  mkdir -p "$TEST_DOTFILES/stubs/opt/homebrew/bin"
  cp /bin/echo "$TEST_DOTFILES/stubs/opt/homebrew/bin/jq"
  chmod +x "$TEST_DOTFILES/stubs/opt/homebrew/bin/jq"
  codesign --sign - --force "$TEST_DOTFILES/stubs/opt/homebrew/bin/jq" >/dev/null 2>&1 || true
  cp /bin/echo "$TEST_DOTFILES/stubs/opt/homebrew/bin/ggrep"
  chmod +x "$TEST_DOTFILES/stubs/opt/homebrew/bin/ggrep"
  codesign --sign - --force "$TEST_DOTFILES/stubs/opt/homebrew/bin/ggrep" >/dev/null 2>&1 || true
  cp /bin/echo "$TEST_DOTFILES/stubs/opt/homebrew/bin/perl"
  chmod +x "$TEST_DOTFILES/stubs/opt/homebrew/bin/perl"
  codesign --sign - --force "$TEST_DOTFILES/stubs/opt/homebrew/bin/perl" >/dev/null 2>&1 || true
  cp /bin/echo "$TEST_DOTFILES/stubs/opt/homebrew/bin/gsed"
  chmod +x "$TEST_DOTFILES/stubs/opt/homebrew/bin/gsed"
  codesign --sign - --force "$TEST_DOTFILES/stubs/opt/homebrew/bin/gsed" >/dev/null 2>&1 || true
  cp /bin/echo "$TEST_DOTFILES/stubs/opt/homebrew/bin/gawk"
  chmod +x "$TEST_DOTFILES/stubs/opt/homebrew/bin/gawk"
  codesign --sign - --force "$TEST_DOTFILES/stubs/opt/homebrew/bin/gawk" >/dev/null 2>&1 || true
  DOTFILES_BREW_PREFIX="$TEST_DOTFILES/stubs/opt/homebrew" "$TEST_DOTFILES/bin/dotfiles-link-curl-shim"
  DOTFILES_BREW_PREFIX="$TEST_DOTFILES/stubs/opt/homebrew" "$TEST_DOTFILES/bin/dotfiles-link-jq-shim"
  DOTFILES_BREW_PREFIX="$TEST_DOTFILES/stubs/opt/homebrew" "$TEST_DOTFILES/bin/dotfiles-link-grep-shim"
  _rg="/usr/bin/find"; [ -x /opt/homebrew/bin/gfind ] && _rg=/opt/homebrew/bin/gfind
  cp "$_rg" "$TEST_DOTFILES/stubs/opt/homebrew/bin/gfind"
  chmod +x "$TEST_DOTFILES/stubs/opt/homebrew/bin/gfind"
  codesign --sign - --force "$TEST_DOTFILES/stubs/opt/homebrew/bin/gfind" >/dev/null 2>&1 || true
  DOTFILES_BREW_PREFIX="$TEST_DOTFILES/stubs/opt/homebrew" "$TEST_DOTFILES/bin/dotfiles-link-perl-shim"
  DOTFILES_BREW_PREFIX="$TEST_DOTFILES/stubs/opt/homebrew" "$TEST_DOTFILES/bin/dotfiles-link-find-shim"
  DOTFILES_BREW_PREFIX="$TEST_DOTFILES/stubs/opt/homebrew" "$TEST_DOTFILES/bin/dotfiles-link-sed-shim"
  DOTFILES_BREW_PREFIX="$TEST_DOTFILES/stubs/opt/homebrew" "$TEST_DOTFILES/bin/dotfiles-link-awk-shim"
  cat > "$TEST_DOTFILES/bin/git" <<'EOF'
#!/bin/bash
true
EOF
  chmod +x "$TEST_DOTFILES/bin/git"
  DOTFILES_BREW_PREFIX="$TEST_DOTFILES/stubs/opt/homebrew" "$TEST_DOTFILES/bin/dotfiles-link-git-shim"
  mkdir -p "$TEST_HOME/.local/share/uv/python/cpython-3.13.13-macos-aarch64-none/bin"
  cp /bin/echo "$TEST_HOME/.local/share/uv/python/cpython-3.13.13-macos-aarch64-none/bin/python3.13"
  chmod +x "$TEST_HOME/.local/share/uv/python/cpython-3.13.13-macos-aarch64-none/bin/python3.13"
  codesign --sign - --force "$TEST_HOME/.local/share/uv/python/cpython-3.13.13-macos-aarch64-none/bin/python3.13" >/dev/null 2>&1 || true
  DOTFILES_UV_PYTHON="$TEST_HOME/.local/share/uv/python/cpython-3.13.13-macos-aarch64-none/bin/python3.13" \
    "$TEST_DOTFILES/bin/dotfiles-link-python-shim"

  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"
  cat > "$TEST_DIR/fakebin/chezmoi" <<FAKE
#!/bin/bash
[ "\${1:-}" = "source-path" ] && printf '%s\n' "$TEST_DOTFILES"
FAKE
  chmod +x "$TEST_DIR/fakebin/chezmoi"
  # Keep /usr/bin/grep ahead of dotfiles shims so doctor.sh and secret-scan use real grep.
  export PATH="$TEST_DIR/fakebin:$TEST_HOME/.local/bin:${PATH:-}"

  # Doctor framework state
  pass_count=0
  fail_count=0
  warn_count=0
  warn_messages=()
  failed_ids=()

  pass()       { pass_count=$((pass_count + 1)); }
  fail()       { fail_count=$((fail_count + 1)); }
  audit_warn() {
    warn_count=$((warn_count + 1))
    warn_messages+=("$1 ${2:-}")
  }

  # Provide check()/check_advisory() stubs matching dotfiles-doctor signatures
  failed_ids_contains() {
    local want="$1" id
    for id in "${failed_ids[@]:-}"; do
      [ "$id" = "$want" ] && return 0
    done
    return 1
  }

  secret_scan_failures() {
    local id
    for id in "${failed_ids[@]:-}"; do
      case "$id" in
        security.secret_in_file.*|security.no_secrets) return 0 ;;
      esac
    done
    return 1
  }

  check() {
    local id="$1" desc="$2" test_cmd="$3"
    if eval "$test_cmd" >/dev/null 2>&1; then
      pass "$desc"
    else
      fail "$desc"
      failed_ids+=("$id")
    fi
  }

  check_advisory() {
    local id="$1" desc="$2" test_cmd="$3" remediation="${4:-}"
    if eval "$test_cmd" >/dev/null 2>&1; then
      pass "$desc"
    else
      audit_warn "$desc" "$remediation"
    fi
  }

  # Initialize a git repo in the dotfiles dir so git ls-files works
  git -C "$TEST_DOTFILES" init -q
  # Use isolated git config with user identity
  export GIT_CONFIG_GLOBAL="$TEST_DIR/gitconfig"
  touch "$GIT_CONFIG_GLOBAL"
  git config --global user.name "Test User"
  git config --global user.email "test@example.com"

  # Mock fd directly so the SSH key scan tests the supported scanner.
  fd() {
    local dir="." candidate
    while [ $# -gt 0 ]; do
      case "$1" in
        -t|--type|-d|--max-depth) shift ;;
        .) ;;
        *) dir="$1" ;;
      esac
      shift || break
    done
    for candidate in "$dir"/*; do
      [ -f "$candidate" ] && printf '%s\n' "$candidate"
    done
  }
  export -f fd 2>/dev/null || true

  # Doctor reads real launchctl PATH; in isolated TEST_HOME that would not include
  # TEST_DOTFILES/bin and falsely fails security.launchctl_path_dotfiles_first.
  launchctl() {
    case "${1:-}" in
      getenv)
        if [ "${2:-}" = PATH ]; then
          printf '%s\n' "$TEST_DOTFILES/bin:/usr/local/bin:/usr/bin:/bin"
        fi
        ;;
    esac
  }
  export -f launchctl 2>/dev/null || true

  command() {
    if [ "${1:-}" = "-v" ]; then
      case "${2:-}" in
        brew) return 1 ;;
        ggrep)
          if [ -n "${PATH:-}" ] && ! echo "$PATH" | tr ':' '\n' | grep -qx "$TEST_DOTFILES/bin"; then
            [ -x "$TEST_DOTFILES/stubs/opt/homebrew/bin/ggrep" ] \
              && printf '%s\n' "$TEST_DOTFILES/stubs/opt/homebrew/bin/ggrep" && return 0
          fi
          [ -x "$TEST_DOTFILES/bin/ggrep" ] && printf '%s\n' "$TEST_DOTFILES/bin/ggrep" && return 0
          ;;
        grep)
          if [ -n "${PATH:-}" ] && ! echo "$PATH" | tr ':' '\n' | grep -qx "$TEST_DOTFILES/bin"; then
            [ -x /usr/bin/grep ] && printf '%s\n' /usr/bin/grep && return 0
          fi
          [ -x "$TEST_DOTFILES/bin/grep" ] && printf '%s\n' "$TEST_DOTFILES/bin/grep" && return 0
          ;;
        jq)
          if [ -n "${PATH:-}" ] && ! echo "$PATH" | tr ':' '\n' | grep -qx "$TEST_DOTFILES/bin"; then
            [ -x "$TEST_DOTFILES/stubs/opt/homebrew/bin/jq" ] \
              && printf '%s\n' "$TEST_DOTFILES/stubs/opt/homebrew/bin/jq" && return 0
          fi
          [ -x "$TEST_DOTFILES/bin/jq" ] && printf '%s\n' "$TEST_DOTFILES/bin/jq" && return 0
          ;;
        python3)
          [ -x "$TEST_DOTFILES/bin/python3" ] && printf '%s\n' "$TEST_DOTFILES/bin/python3" && return 0
          ;;
        python3.13)
          [ -x "$TEST_DOTFILES/bin/python3.13" ] && printf '%s\n' "$TEST_DOTFILES/bin/python3.13" && return 0
          ;;
        perl)
          if [ -n "${PATH:-}" ] && ! echo "$PATH" | tr ':' '\n' | grep -qx "$TEST_DOTFILES/bin"; then
            [ -x "$TEST_DOTFILES/stubs/opt/homebrew/bin/perl" ] \
              && printf '%s\n' "$TEST_DOTFILES/stubs/opt/homebrew/bin/perl" && return 0
          fi
          [ -x "$TEST_DOTFILES/bin/perl" ] && printf '%s\n' "$TEST_DOTFILES/bin/perl" && return 0
          ;;
        curl)
          if [ -n "${PATH:-}" ] && ! echo "$PATH" | tr ':' '\n' | grep -qx "$TEST_DOTFILES/bin"; then
            if echo "$PATH" | tr ':' '\n' | grep -q 'opt/curl/bin'; then
              [ -x "$TEST_DOTFILES/stubs/opt/homebrew/opt/curl/bin/curl" ] \
                && printf '%s\n' "$TEST_DOTFILES/stubs/opt/homebrew/opt/curl/bin/curl" && return 0
            fi
            [ -x /usr/bin/curl ] && printf '%s\n' /usr/bin/curl && return 0
          fi
          [ -x "$TEST_DOTFILES/bin/curl" ] && printf '%s\n' "$TEST_DOTFILES/bin/curl" && return 0
          ;;
      esac
    fi
    builtin command "$@"
  }
}

teardown() {
  rm -rf "$TEST_DIR"
}

# The setup mock pins `command -v jq` to $TEST_DOTFILES/bin; tests that model a
# separate applied checkout need the real PATH lookup for jq.
use_real_jq_lookup() {
  eval "_setup_$(declare -f command)"
  command() {
    if [ "${1:-}" = "-v" ] && [ "${2:-}" = "jq" ]; then
      builtin command -v jq
      return
    fi
    _setup_command "$@"
  }
}

install_launchagent_path_repair() {
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-fix-launchagent-endpoint-path" \
    "$TEST_DOTFILES/bin/dotfiles-fix-launchagent-endpoint-path"
  chmod +x "$TEST_DOTFILES/bin/dotfiles-fix-launchagent-endpoint-path"
}

write_path_repair_plist() {
  local label="$1"
  mkdir -p "$TEST_HOME/Library/LaunchAgents"
  cat > "$TEST_HOME/Library/LaunchAgents/$label.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>$TEST_HOME/apps/dotfiles/bin:/usr/bin:/bin</string></dict>
</dict></plist>
EOF
}

write_launchctl_reload_stub() {
  mkdir -p "$TEST_DIR/stub-bin"
  cat > "$TEST_DIR/stub-bin/launchctl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$LAUNCHCTL_LOG"
if [ "${1:-}" = "print" ]; then
  if [ "${LAUNCHCTL_CREATE_NODE_BLOCK_AFTER_PRINT:-0}" = "1" ]; then
    mkdir -p "$HOME/.local/state/dotfiles"
    : > "$HOME/.local/state/dotfiles/endpoint-node-publisher-blocked"
  fi
  [ "${LAUNCHCTL_PRINT_LOADED:-0}" = "1" ]
  exit
fi
exit 0
EOF
  chmod +x "$TEST_DIR/stub-bin/launchctl"
}

run_path_repair_with_launchctl_stub() {
  local loaded="$1"
  run bash -c 'unset -f launchctl 2>/dev/null || true; exec "$@"' bash \
    env PATH="$TEST_DIR/stub-bin:$PATH" HOME="$TEST_HOME" \
    LAUNCHCTL_LOG="$TEST_DIR/launchctl.log" LAUNCHCTL_PRINT_LOADED="$loaded" \
    "$TEST_DOTFILES/bin/dotfiles-fix-launchagent-endpoint-path"
}

run_path_repair_with_late_node_block() {
  run bash -c 'unset -f launchctl 2>/dev/null || true; exec "$@"' bash \
    env PATH="$TEST_DIR/stub-bin:$PATH" HOME="$TEST_HOME" \
    LAUNCHCTL_LOG="$TEST_DIR/launchctl.log" LAUNCHCTL_PRINT_LOADED=1 \
    LAUNCHCTL_CREATE_NODE_BLOCK_AFTER_PRINT=1 \
    "$TEST_DOTFILES/bin/dotfiles-fix-launchagent-endpoint-path"
}

@test "security: ssh directory permissions pass when 700" {
  chmod 700 "$TEST_HOME/.ssh"
  # Create an ssh config with correct permissions
  echo "Host *" > "$TEST_HOME/.ssh/config"
  chmod 600 "$TEST_HOME/.ssh/config"
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  [ "$pass_count" -ge 1 ]
}

@test "security: ssh directory permissions fail when wrong" {
  chmod 755 "$TEST_HOME/.ssh"
  echo "Host *" > "$TEST_HOME/.ssh/config"
  chmod 644 "$TEST_HOME/.ssh/config"
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "security: private key permissions pass when 600" {
  chmod 700 "$TEST_HOME/.ssh"
  # Create a fake private key with correct permissions
  cat > "$TEST_HOME/.ssh/id_test" <<'KEY'
-----BEGIN OPENSSH PRIVATE KEY----- # dotfiles-secret-allowlist: bats fixture fake key
fake-key-data-for-testing
-----END OPENSSH PRIVATE KEY-----
KEY
  chmod 600 "$TEST_HOME/.ssh/id_test"
  echo "Host *" > "$TEST_HOME/.ssh/config"
  chmod 600 "$TEST_HOME/.ssh/config"
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  # ssh dir + private key + config perms + forwarding + secrets + .env + git safety
  [ "$pass_count" -ge 3 ]
}

@test "security: private key permissions fail when wrong" {
  chmod 700 "$TEST_HOME/.ssh"
  cat > "$TEST_HOME/.ssh/id_bad" <<'KEY'
-----BEGIN OPENSSH PRIVATE KEY----- # dotfiles-secret-allowlist: bats fixture fake key
fake-key-data-for-testing
-----END OPENSSH PRIVATE KEY-----
KEY
  chmod 644 "$TEST_HOME/.ssh/id_bad"
  echo "Host *" > "$TEST_HOME/.ssh/config"
  chmod 600 "$TEST_HOME/.ssh/config"
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "security: fd unavailable warns instead of using a fallback scanner" {
  chmod 700 "$TEST_HOME/.ssh"
  echo "Host *" > "$TEST_HOME/.ssh/config"
  chmod 600 "$TEST_HOME/.ssh/config"
  unset -f fd
  command() {
    if [ "${1:-}" = "-v" ] && [ "${2:-}" = "fd" ]; then return 1; fi
    if [ "${1:-}" = "-v" ] && [ "${2:-}" = "brew" ]; then return 1; fi
    builtin command "$@"
  }

  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"

  [ "$warn_count" -ge 1 ]
}

@test "security: ssh key scan has no shell find fallback" {
  ! /usr/bin/grep -q '||[[:space:]]*find' "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
}

@test "security: no secrets detected in clean tracked files" {
  chmod 700 "$TEST_HOME/.ssh"
  echo "Host *" > "$TEST_HOME/.ssh/config"
  chmod 600 "$TEST_HOME/.ssh/config"
  # Create a clean tracked file
  echo "# just a comment" > "$TEST_DOTFILES/clean_file.sh"
  git -C "$TEST_DOTFILES" add clean_file.sh
  git -C "$TEST_DOTFILES" commit -q -m "add clean file" --no-gpg-sign
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  # Should pass the secrets check
  [ "$pass_count" -ge 1 ]
}

@test "security: detects secrets in tracked files" {
  chmod 700 "$TEST_HOME/.ssh"
  echo "Host *" > "$TEST_HOME/.ssh/config"
  chmod 600 "$TEST_HOME/.ssh/config"
  # Create a file with a secret pattern
  echo 'API_KEY="sk_live_abcdefghijklmnop1234"' > "$TEST_DOTFILES/leaky.sh" # dotfiles-secret-allowlist: writes a fixture that the scanner must catch
  git -C "$TEST_DOTFILES" add leaky.sh
  git -C "$TEST_DOTFILES" commit -q -m "add leaky file" --no-gpg-sign
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "security: detects secrets even when the line mentions TODO or example" {
  chmod 700 "$TEST_HOME/.ssh"
  echo "Host *" > "$TEST_HOME/.ssh/config"
  chmod 600 "$TEST_HOME/.ssh/config"
  echo 'API_KEY="sk_live_abcdefghijklmnop1234" # TODO rotate this example' > "$TEST_DOTFILES/leaky_example.sh" # dotfiles-secret-allowlist: writes a fixture that the scanner must catch
  git -C "$TEST_DOTFILES" add leaky_example.sh
  git -C "$TEST_DOTFILES" commit -q -m "add leaky example file" --no-gpg-sign
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "security: allows structured secret scan comments" {
  chmod 700 "$TEST_HOME/.ssh"
  echo "Host *" > "$TEST_HOME/.ssh/config"
  chmod 600 "$TEST_HOME/.ssh/config"
  echo 'API_KEY="sk_live_intentionalfixture" # dotfiles-secret-allowlist: fake credential for scanner coverage' > "$TEST_DOTFILES/allowlisted.sh"
  git -C "$TEST_DOTFILES" add allowlisted.sh
  git -C "$TEST_DOTFILES" commit -q -m "add allowlisted fixture" --no-gpg-sign
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  ! secret_scan_failures
}

@test "security: ignores intentional test secret fixtures" {
  chmod 700 "$TEST_HOME/.ssh"
  echo "Host *" > "$TEST_HOME/.ssh/config"
  chmod 600 "$TEST_HOME/.ssh/config"
  mkdir -p "$TEST_DOTFILES/tests"
  echo 'API_KEY="sk_live_intentionaltestfixture"' > "$TEST_DOTFILES/tests/audit_fixture.bats" # dotfiles-secret-allowlist: writes an explicit fixture-path secret
  git -C "$TEST_DOTFILES" add tests/audit_fixture.bats
  git -C "$TEST_DOTFILES" commit -q -m "add test fixture" --no-gpg-sign
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  ! secret_scan_failures
  [ "$pass_count" -ge 1 ]
}

@test "security: no .env files tracked passes" {
  chmod 700 "$TEST_HOME/.ssh"
  echo "Host *" > "$TEST_HOME/.ssh/config"
  chmod 600 "$TEST_HOME/.ssh/config"
  echo "# readme" > "$TEST_DOTFILES/README.md"
  git -C "$TEST_DOTFILES" add README.md
  git -C "$TEST_DOTFILES" commit -q -m "add readme" --no-gpg-sign
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  [ "$pass_count" -ge 1 ]
}

@test "security: sensitive file not world-readable passes" {
  chmod 700 "$TEST_HOME/.ssh"
  echo "Host *" > "$TEST_HOME/.ssh/config"
  chmod 600 "$TEST_HOME/.ssh/config"
  # Create a sensitive file with safe permissions
  echo "machine example.com" > "$TEST_HOME/.netrc"
  chmod 600 "$TEST_HOME/.netrc"
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  [ "$pass_count" -ge 1 ]
}

@test "security: sensitive file world-readable warns" {
  chmod 700 "$TEST_HOME/.ssh"
  echo "Host *" > "$TEST_HOME/.ssh/config"
  chmod 600 "$TEST_HOME/.ssh/config"
  # Create a world-readable sensitive file
  echo "machine example.com" > "$TEST_HOME/.netrc"
  chmod 644 "$TEST_HOME/.netrc"
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  [ "$warn_count" -ge 1 ]
  [[ "${warn_messages[*]}" == *"chmod 600 ~/.netrc"* ]]
}

@test "security: git credential store warns" {
  chmod 700 "$TEST_HOME/.ssh"
  echo "Host *" > "$TEST_HOME/.ssh/config"
  chmod 600 "$TEST_HOME/.ssh/config"
  git config --global credential.helper store
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  [ "$warn_count" -ge 1 ]
  [[ "${warn_messages[*]}" == *"git config --global --unset credential.helper"* ]]
}

@test "security: unsigned commits warning explains git config path" {
  chmod 700 "$TEST_HOME/.ssh"
  echo "Host *" > "$TEST_HOME/.ssh/config"
  chmod 600 "$TEST_HOME/.ssh/config"

  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"

  [ "$warn_count" -ge 1 ]
  [[ "${warn_messages[*]}" == *"git config --global commit.gpgsign true"* ]]
  [[ "${warn_messages[*]}" == *"skip only if your team does not require signed commits"* ]]
}

@test "security: ssh agent forwarding global warns" {
  chmod 700 "$TEST_HOME/.ssh"
  cat > "$TEST_HOME/.ssh/config" <<'SSH'
Host *
  ForwardAgent yes
  ServerAliveInterval 60
SSH
  chmod 600 "$TEST_HOME/.ssh/config"
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  [ "$warn_count" -ge 1 ]
}

# ── pipx venv architecture drift (arm64 host, x86_64 venv) ─────────────────
# Regression net for the 2026-05-29 dotfiles-upgrade `pipx` failure: all four
# pipx venvs were x86_64 on this arm64 Mac, which broke `pipx upgrade-all`.

@test "security: pipx venv on x86_64 python (arm64 host) is flagged as arch drift" {
  [ "$(uname -m)" = "arm64" ] || skip "pipx arch-drift check only fires on arm64 hosts"
  mkdir -p "$TEST_HOME/.local/pipx/venvs/badpkg"
  cat > "$TEST_HOME/.local/pipx/venvs/badpkg/pyvenv.cfg" <<'CFG'
home = /Users/x/.local/share/uv/python/cpython-3.13.13-macos-x86_64-none/bin
include-system-site-packages = false
version = 3.13.13
executable = /Users/x/.local/share/uv/python/cpython-3.13.13-macos-x86_64-none/bin/python3.13
CFG
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  printf '%s\n' "${failed_ids[@]:-}" | /usr/bin/grep -qx "security.pipx_venv_native_arch.badpkg"
}

@test "security: pipx venv on native arm64 python is NOT flagged" {
  [ "$(uname -m)" = "arm64" ] || skip "pipx arch-drift check only fires on arm64 hosts"
  mkdir -p "$TEST_HOME/.local/pipx/venvs/goodpkg"
  cat > "$TEST_HOME/.local/pipx/venvs/goodpkg/pyvenv.cfg" <<'CFG'
home = /Users/x/.local/share/uv/python/cpython-3.13.13-macos-aarch64-none/bin
include-system-site-packages = false
version = 3.13.13
executable = /Users/x/.local/share/uv/python/cpython-3.13.13-macos-aarch64-none/bin/python3.13
CFG
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  ! printf '%s\n' "${failed_ids[@]:-}" | /usr/bin/grep -qx "security.pipx_venv_native_arch.goodpkg"
}

@test "security: env shebang in bin/ is flagged" {
  mkdir -p "$TEST_DOTFILES/bin"
  cat > "$TEST_DOTFILES/bin/bad-script" <<'EOF'
#!/usr/bin/env bash
echo bad
EOF
  chmod +x "$TEST_DOTFILES/bin/bad-script"
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  printf '%s\n' "${failed_ids[@]:-}" | /usr/bin/grep -qx "security.no_env_shebang.bin_bad-script"
}

@test "security: clean bin/ passes no_env_shebangs check" {
  mkdir -p "$TEST_DOTFILES/bin"
  cat > "$TEST_DOTFILES/bin/good-script" <<'EOF'
#!/bin/bash
echo ok
EOF
  chmod +x "$TEST_DOTFILES/bin/good-script"
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  ! printf '%s\n' "${failed_ids[@]:-}" | /usr/bin/grep -q '^security\.no_env_shebang'
}

@test "security: env shebang in git-hooks/ is flagged" {
  mkdir -p "$TEST_DOTFILES/git-hooks"
  cat > "$TEST_DOTFILES/git-hooks/pre-commit" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$TEST_DOTFILES/git-hooks/pre-commit"
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  printf '%s\n' "${failed_ids[@]:-}" | /usr/bin/grep -qx "security.no_env_shebang.git-hooks_pre-commit"
}

@test "security: LaunchAgent plist with /usr/bin/env is flagged" {
  mkdir -p "$TEST_DOTFILES/launchagents"
  cat > "$TEST_DOTFILES/launchagents/com.dotfiles.bad.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/env</string>
    <string>bash</string>
    <string>/tmp/run.sh</string>
  </array>
</dict></plist>
EOF
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  printf '%s\n' "${failed_ids[@]:-}" | /usr/bin/grep -qx "security.launchagent_no_env.launchagents_com.dotfiles.bad.plist"
}

@test "security: unsigned endpoint shim is flagged" {
  _find_target="$(readlink "$TEST_DOTFILES/bin/find" 2>/dev/null || true)"
  if [ -n "$_find_target" ] && [ "${_find_target#/}" = "$_find_target" ]; then
    _find_target="$TEST_DOTFILES/bin/$_find_target"
  else
    _find_target="$TEST_DOTFILES/bin/find"
  fi
  codesign --remove-signature "$_find_target" >/dev/null 2>&1 || true
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  printf '%s\n' "${failed_ids[@]:-}" | /usr/bin/grep -qx "security.endpoint_shims_adhoc_signed"
}

@test "security: curl shim exists as symlink" {
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  ! failed_ids_contains "security.curl_shim"
  ! failed_ids_contains "security.curl_shim_not_script"
  ! failed_ids_contains "security.curl_not_system"
  ! failed_ids_contains "security.curl_not_bare_homebrew"
  ! failed_ids_contains "security.curl_launchagent_path"
  ! failed_ids_contains "security.curl_launchagent_not_system"
  ! failed_ids_contains "security.brew_curl_adhoc_signed"
}

@test "security: jq shim exists as symlink" {
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  ! failed_ids_contains "security.jq_shim"
  ! failed_ids_contains "security.jq_shim_not_script"
  ! failed_ids_contains "security.jq_not_system"
  ! failed_ids_contains "security.jq_not_bare_homebrew"
  ! failed_ids_contains "security.jq_launchagent_path"
  ! failed_ids_contains "security.deployed_la_jq"
}

@test "security: jq bash script shim is auto-fixed by doctor" {
  rm -f "$TEST_DOTFILES/bin/jq"
  cat >"$TEST_DOTFILES/bin/jq" <<'EOF'
#!/bin/bash
exec /opt/homebrew/bin/jq "$@"
EOF
  chmod +x "$TEST_DOTFILES/bin/jq"
  [ ! -L "$TEST_DOTFILES/bin/jq" ]
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  failed_ids_contains "security.jq_shim_not_script"
  DOTFILES_BREW_PREFIX="$TEST_DOTFILES/stubs/opt/homebrew" "$TEST_DOTFILES/bin/dotfiles-link-jq-shim"
  [ -L "$TEST_DOTFILES/bin/jq" ]
}

@test "security: unsigned uv python is flagged" {
  mkdir -p "$TEST_HOME/.local/share/uv/python/cpython-3.13.13-macos-aarch64-none/bin"
  cp /bin/echo "$TEST_HOME/.local/share/uv/python/cpython-3.13.13-macos-aarch64-none/bin/python3.13"
  codesign --remove-signature "$TEST_HOME/.local/share/uv/python/cpython-3.13.13-macos-aarch64-none/bin/python3.13" 2>/dev/null || true
  chmod +x "$TEST_HOME/.local/share/uv/python/cpython-3.13.13-macos-aarch64-none/bin/python3.13"
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  failed_ids_contains "security.uv_python_adhoc_signed"
}

@test "security: python3 shims exist" {
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  ! failed_ids_contains "security.python3_shim"
  ! failed_ids_contains "security.python3_13_shim"
  ! failed_ids_contains "security.python3_shim_not_script"
  ! failed_ids_contains "security.python3_13_shim_not_script"
}

@test "security: grep and ggrep shims exist as symlinks" {
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  ! failed_ids_contains "security.grep_shim"
  ! failed_ids_contains "security.ggrep_shim"
  ! failed_ids_contains "security.grep_shim_not_script"
  ! failed_ids_contains "security.ggrep_shim_not_script"
  ! failed_ids_contains "security.ggrep_launchagent_path"
  ! failed_ids_contains "security.grep_launchagent_path"
}

@test "security: homebrew-only sandbox PATH flags bare ggrep when unsigned" {
  codesign --remove-signature "$TEST_DOTFILES/stubs/opt/homebrew/bin/ggrep" 2>/dev/null || true
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  failed_ids_contains "security.sandbox_ggrep_signed"
  codesign --sign - --force "$TEST_DOTFILES/stubs/opt/homebrew/bin/ggrep" >/dev/null 2>&1 || true
}

@test "security: homebrew-only sandbox PATH flags bare perl when unsigned" {
  codesign --remove-signature "$TEST_DOTFILES/stubs/opt/homebrew/bin/perl" 2>/dev/null || true
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  failed_ids_contains "security.sandbox_perl_signed"
  codesign --sign - --force "$TEST_DOTFILES/stubs/opt/homebrew/bin/perl" >/dev/null 2>&1 || true
}

@test "security: homebrew-only sandbox PATH flags bare jq when unsigned" {
  codesign --remove-signature "$TEST_DOTFILES/stubs/opt/homebrew/bin/jq" 2>/dev/null || true
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  failed_ids_contains "security.sandbox_jq_signed"
  codesign --sign - --force "$TEST_DOTFILES/stubs/opt/homebrew/bin/jq" >/dev/null 2>&1 || true
}

@test "security: keg curl PATH without dotfiles/bin flags bare curl when unsigned" {
  codesign --remove-signature "$TEST_DOTFILES/stubs/opt/homebrew/opt/curl/bin/curl" 2>/dev/null || true
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  failed_ids_contains "security.sandbox_curl_signed"
  codesign --sign - --force "$TEST_DOTFILES/stubs/opt/homebrew/opt/curl/bin/curl" >/dev/null 2>&1 || true
}

@test "security: grep bash script shim is auto-fixed by doctor" {
  rm -f "$TEST_DOTFILES/bin/grep" "$TEST_DOTFILES/bin/ggrep"
  cat >"$TEST_DOTFILES/bin/grep" <<'EOF'
#!/bin/bash
exec /opt/homebrew/bin/ggrep "$@"
EOF
  chmod +x "$TEST_DOTFILES/bin/grep"
  [ ! -L "$TEST_DOTFILES/bin/grep" ]
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  failed_ids_contains "security.grep_shim_not_script"
  DOTFILES_BREW_PREFIX="$TEST_DOTFILES/stubs/opt/homebrew" "$TEST_DOTFILES/bin/dotfiles-link-grep-shim"
  [ -L "$TEST_DOTFILES/bin/grep" ]
  [ -L "$TEST_DOTFILES/bin/ggrep" ]
}

@test "security: deployed agentbrew LaunchAgent without dotfiles/bin fails ggrep PATH check" {
  chmod 700 "$TEST_HOME/.ssh"
  mkdir -p "$TEST_HOME/Library/LaunchAgents"
  cat > "$TEST_HOME/Library/LaunchAgents/com.agentbrew.competitor-watch.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.agentbrew.competitor-watch</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>$TEST_DOTFILES/stubs/opt/homebrew/bin:/usr/bin:/bin</string>
  </dict>
</dict>
</plist>
EOF
  cp "$BATS_TEST_DIRNAME/../lib/launchctl-timeout.sh" "$TEST_DOTFILES/lib/launchctl-timeout.sh"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-fix-launchagent-endpoint-path" \
    "$TEST_DOTFILES/bin/dotfiles-fix-launchagent-endpoint-path"
  chmod +x "$TEST_DOTFILES/bin/dotfiles-fix-launchagent-endpoint-path"
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  failed_ids_contains "security.deployed_la_ggrep.com.agentbrew.competitor-watch"
  failed_ids_contains "security.deployed_la_curl.com.agentbrew.competitor-watch"
  failed_ids_contains "security.deployed_la_perl.com.agentbrew.competitor-watch"
}

@test "security: deployed minsky tick-loop without dotfiles/bin fails jq PATH check" {
  chmod 700 "$TEST_HOME/.ssh"
  mkdir -p "$TEST_HOME/Library/LaunchAgents"
  cat > "$TEST_HOME/Library/LaunchAgents/com.minsky.tick-loop.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.minsky.tick-loop</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>$TEST_DOTFILES/stubs/opt/homebrew/bin:/usr/bin:/bin</string>
  </dict>
</dict>
</plist>
EOF
  cp "$BATS_TEST_DIRNAME/../lib/launchctl-timeout.sh" "$TEST_DOTFILES/lib/launchctl-timeout.sh"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-fix-launchagent-endpoint-path" \
    "$TEST_DOTFILES/bin/dotfiles-fix-launchagent-endpoint-path"
  chmod +x "$TEST_DOTFILES/bin/dotfiles-fix-launchagent-endpoint-path"
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  failed_ids_contains "security.deployed_la_jq.com.minsky.tick-loop"
}

@test "security: deployed watchman LaunchAgent with stale dotfiles path fails jq PATH check" {
  chmod 700 "$TEST_HOME/.ssh"
  mkdir -p "$TEST_HOME/Library/LaunchAgents"
  cat > "$TEST_HOME/Library/LaunchAgents/com.github.facebook.watchman.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.github.facebook.watchman</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>$TEST_HOME/apps/dotfiles/bin:/usr/local/bin:/usr/bin:/bin</string>
  </dict>
</dict>
</plist>
EOF
  cp "$BATS_TEST_DIRNAME/../lib/launchctl-timeout.sh" "$TEST_DOTFILES/lib/launchctl-timeout.sh"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-fix-launchagent-endpoint-path" \
    "$TEST_DOTFILES/bin/dotfiles-fix-launchagent-endpoint-path"
  chmod +x "$TEST_DOTFILES/bin/dotfiles-fix-launchagent-endpoint-path"
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  failed_ids_contains "security.deployed_la_jq.com.github.facebook.watchman"
  failed_ids_contains "security.deployed_la_stale_dotfiles_path.com.github.facebook.watchman"
}

@test "security: dotfiles-fix-launchagent-endpoint-path repairs watchman stale PATH" {
  mkdir -p "$TEST_HOME/Library/LaunchAgents"
  cat > "$TEST_HOME/Library/LaunchAgents/com.github.facebook.watchman.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.github.facebook.watchman</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>$TEST_HOME/apps/dotfiles/bin:/usr/bin:/bin</string>
  </dict>
</dict>
</plist>
EOF
  cp "$BATS_TEST_DIRNAME/../lib/launchctl-timeout.sh" "$TEST_DOTFILES/lib/launchctl-timeout.sh"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-fix-launchagent-endpoint-path" \
    "$TEST_DOTFILES/bin/dotfiles-fix-launchagent-endpoint-path"
  chmod +x "$TEST_DOTFILES/bin/dotfiles-fix-launchagent-endpoint-path"
  HOME="$TEST_HOME" DOTFILES_DIR="$TEST_DOTFILES" "$TEST_DOTFILES/bin/dotfiles-fix-launchagent-endpoint-path"
  path="$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:PATH' \
    "$TEST_HOME/Library/LaunchAgents/com.github.facebook.watchman.plist")"
  canon_bin="$(cd "$TEST_DOTFILES/bin" && pwd -P)"
  [[ "$path" == "${canon_bin}:"* ]] \
    || { echo "expected PATH to begin with $canon_bin, got $path"; false; }
  ! [[ "$path" == *"apps/dotfiles/bin"* ]]
}

@test "security: dotfiles-fix-launchagent-endpoint-path drops a dev checkout bin ahead of DOTFILES_DIR" {
  mkdir -p "$TEST_HOME/Library/LaunchAgents" "$TEST_DIR/stub-bin"
  canon_bin="$(cd "$TEST_DOTFILES/bin" && pwd -P)"
  printf '#!/bin/bash\necho "$*" >> "%s/launchctl.log"\n' "$TEST_DIR" > "$TEST_DIR/stub-bin/launchctl"
  chmod +x "$TEST_DIR/stub-bin/launchctl"
  cat > "$TEST_HOME/Library/LaunchAgents/com.example.dev-bin-test.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.example.dev-bin-test</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>$TEST_HOME/apps/tooling/dotfiles/bin:$canon_bin:/usr/bin:/bin</string>
  </dict>
</dict>
</plist>
EOF
  cp "$BATS_TEST_DIRNAME/../lib/launchctl-timeout.sh" "$TEST_DOTFILES/lib/launchctl-timeout.sh"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-fix-launchagent-endpoint-path" \
    "$TEST_DOTFILES/bin/dotfiles-fix-launchagent-endpoint-path"
  chmod +x "$TEST_DOTFILES/bin/dotfiles-fix-launchagent-endpoint-path"
  PATH="$TEST_DIR/stub-bin:$PATH" HOME="$TEST_HOME" DOTFILES_DIR="$TEST_DOTFILES" \
    "$TEST_DOTFILES/bin/dotfiles-fix-launchagent-endpoint-path"
  path="$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:PATH' \
    "$TEST_HOME/Library/LaunchAgents/com.example.dev-bin-test.plist")"
  [ "$path" = "${canon_bin}:/usr/bin:/bin" ] \
    || { echo "expected $canon_bin:/usr/bin:/bin, got $path"; false; }
}

@test "security: LaunchAgent PATH repair does not reload an unloaded job" {
  write_path_repair_plist "com.example.unloaded"
  install_launchagent_path_repair
  write_launchctl_reload_stub
  run_path_repair_with_launchctl_stub 0
  [ "$status" -eq 0 ]
  [[ "$output" == *"job was not reloaded"* ]]
  /usr/bin/grep -q '^print gui/' "$TEST_DIR/launchctl.log"
  ! /usr/bin/grep -qE '^(bootout|unload|bootstrap|load)' "$TEST_DIR/launchctl.log"
}

@test "security: LaunchAgent PATH repair reloads only a job loaded before repair" {
  write_path_repair_plist "com.example.loaded"
  install_launchagent_path_repair
  write_launchctl_reload_stub
  run_path_repair_with_launchctl_stub 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"Fixed and reloaded PATH"* ]]
  /usr/bin/grep -q '^print gui/' "$TEST_DIR/launchctl.log"
  /usr/bin/grep -q '^bootout gui/' "$TEST_DIR/launchctl.log"
  /usr/bin/grep -q '^bootstrap gui/' "$TEST_DIR/launchctl.log"
}

@test "security: LaunchAgent PATH repair never loads Minsky without its autostart marker" {
  write_path_repair_plist "com.minsky.tick-loop"
  install_launchagent_path_repair
  write_launchctl_reload_stub
  run_path_repair_with_launchctl_stub 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"reload skipped by current safety policy"* ]]
  /usr/bin/grep -q '^print gui/' "$TEST_DIR/launchctl.log"
  ! /usr/bin/grep -qE '^(bootout|unload|bootstrap|load)' "$TEST_DIR/launchctl.log"
}

@test "security: LaunchAgent PATH repair reloads a loaded Minsky job only with its autostart marker" {
  write_path_repair_plist "com.minsky.tick-loop"
  install_launchagent_path_repair
  write_launchctl_reload_stub
  mkdir -p "$TEST_HOME/.minsky"
  : > "$TEST_HOME/.minsky/autostart-enabled"
  run_path_repair_with_launchctl_stub 1
  [ "$status" -eq 0 ]
  /usr/bin/grep -q '^bootout gui/' "$TEST_DIR/launchctl.log"
  /usr/bin/grep -q '^bootstrap gui/' "$TEST_DIR/launchctl.log"
}

@test "security: LaunchAgent PATH repair never loads blocked Node jobs" {
  write_path_repair_plist "com.agentbrew.competitor-watch"
  install_launchagent_path_repair
  write_launchctl_reload_stub
  mkdir -p "$TEST_HOME/.local/state/dotfiles"
  : > "$TEST_HOME/.local/state/dotfiles/endpoint-node-publisher-blocked"
  run_path_repair_with_launchctl_stub 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"reload skipped by current safety policy"* ]]
  /usr/bin/grep -q '^print gui/' "$TEST_DIR/launchctl.log"
  ! /usr/bin/grep -qE '^(bootout|unload|bootstrap|load)' "$TEST_DIR/launchctl.log"
}

@test "security: LaunchAgent PATH repair rechecks safe mode before reloading a Node job" {
  write_path_repair_plist "com.agentbrew.competitor-watch"
  install_launchagent_path_repair
  write_launchctl_reload_stub
  run_path_repair_with_late_node_block
  [ "$status" -eq 0 ]
  [[ "$output" == *"reload skipped by current safety policy"* ]]
  /usr/bin/grep -q '^print gui/' "$TEST_DIR/launchctl.log"
  ! /usr/bin/grep -qE '^(bootout|unload|bootstrap|load)' "$TEST_DIR/launchctl.log"
}

@test "security: LaunchAgent PATH repair from a dev checkout is report-only" {
  setup_distinct_dotfiles_checkouts "$TEST_DOTFILES" "$TEST_DIR/applied"
  mkdir -p "$TEST_HOME/Library/LaunchAgents" "$TEST_DIR/stub-bin" "$TEST_APPLIED_DOTFILES/bin"
  applied_bin="$(cd "$TEST_APPLIED_DOTFILES" && pwd)/bin"
  dev_bin="$(cd "$TEST_DOTFILES/bin" && pwd -P)"
  printf '#!/bin/bash\necho "$*" >> "%s/launchctl.log"\n' "$TEST_DIR" > "$TEST_DIR/stub-bin/launchctl"
  cat > "$TEST_DIR/stub-bin/chezmoi" <<FAKE
#!/bin/bash
[ "\$1" = "source-path" ] && printf '%s\n' "$TEST_DIR/applied"
FAKE
  chmod +x "$TEST_DIR/stub-bin/launchctl" "$TEST_DIR/stub-bin/chezmoi"
  cat > "$TEST_HOME/Library/LaunchAgents/com.example.applied-bin-test.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.example.applied-bin-test</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>$dev_bin:$applied_bin:/usr/bin:/bin</string>
  </dict>
</dict>
</plist>
EOF
  cp "$BATS_TEST_DIRNAME/../lib/launchctl-timeout.sh" "$TEST_DOTFILES/lib/launchctl-timeout.sh"
  cp "$BATS_TEST_DIRNAME/../lib/dotfiles-source-dir.sh" "$TEST_DOTFILES/lib/dotfiles-source-dir.sh"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-fix-launchagent-endpoint-path" \
    "$TEST_DOTFILES/bin/dotfiles-fix-launchagent-endpoint-path"
  chmod +x "$TEST_DOTFILES/bin/dotfiles-fix-launchagent-endpoint-path"
  run env PATH="$TEST_DIR/stub-bin:$PATH" HOME="$TEST_HOME" DOTFILES_DIR="$TEST_DOTFILES" \
    "$TEST_DOTFILES/bin/dotfiles-fix-launchagent-endpoint-path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"report-only outside the applied checkout"* ]]
  plist="$TEST_HOME/Library/LaunchAgents/com.example.applied-bin-test.plist"
  path="$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:PATH' "$plist")"
  [ "$path" = "${dev_bin}:${applied_bin}:/usr/bin:/bin" ]
  [ ! -s "$TEST_DIR/launchctl.log" ]
}

@test "security: deployed LaunchAgent PATH is checked against DOTFILES_LINK_DIR bin" {
  chmod 700 "$TEST_HOME/.ssh"
  mkdir -p "$TEST_HOME/Library/LaunchAgents" "$TEST_DIR/applied/bin"
  printf '#!/bin/bash\n' > "$TEST_DIR/applied/bin/jq"
  chmod +x "$TEST_DIR/applied/bin/jq"
  cat > "$TEST_HOME/Library/LaunchAgents/com.example.link-dir-test.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.example.link-dir-test</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>$TEST_DIR/applied/bin:/usr/bin:/bin</string>
  </dict>
</dict>
</plist>
EOF
  DOTFILES_LINK_DIR="$TEST_DIR/applied"
  use_real_jq_lookup
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  [ "$DOTFILES_DIR" = "$TEST_DOTFILES" ]
  ! failed_ids_contains "security.deployed_la_jq.com.example.link-dir-test"
}

@test "security: memory daemon keeps its isolated uvx PATH" {
  chmod 700 "$TEST_HOME/.ssh"
  mkdir -p "$TEST_HOME/Library/LaunchAgents"
  cat > "$TEST_HOME/Library/LaunchAgents/com.agentbrew.mcp-memory.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.agentbrew.mcp-memory</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/usr/bin:/bin</string>
  </dict>
</dict>
</plist>
EOF
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  ! failed_ids_contains "security.deployed_la_jq.com.agentbrew.mcp-memory"
  ! failed_ids_contains "security.deployed_la_ggrep.com.agentbrew.mcp-memory"
  ! failed_ids_contains "security.deployed_la_curl.com.agentbrew.mcp-memory"
  ! failed_ids_contains "security.deployed_la_perl.com.agentbrew.mcp-memory"
}

@test "security: deployed LaunchAgent PATH with a dev checkout bin ahead of DOTFILES_LINK_DIR fails" {
  chmod 700 "$TEST_HOME/.ssh"
  mkdir -p "$TEST_HOME/Library/LaunchAgents" "$TEST_DIR/applied/bin" "$TEST_DIR/dev/bin"
  printf '#!/bin/bash\n' > "$TEST_DIR/applied/bin/jq"
  printf '#!/bin/bash\n' > "$TEST_DIR/dev/bin/jq"
  chmod +x "$TEST_DIR/applied/bin/jq" "$TEST_DIR/dev/bin/jq"
  cat > "$TEST_HOME/Library/LaunchAgents/com.example.dev-link-test.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.example.dev-link-test</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>$TEST_DIR/dev/bin:$TEST_DIR/applied/bin:/usr/bin:/bin</string>
  </dict>
</dict>
</plist>
EOF
  DOTFILES_LINK_DIR="$TEST_DIR/applied"
  use_real_jq_lookup
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  failed_ids_contains "security.deployed_la_jq.com.example.dev-link-test"
}

@test "security: launchctl PATH with the DOTFILES_LINK_DIR bin first passes" {
  mkdir -p "$TEST_DIR/applied/bin"
  launchctl() {
    [ "${1:-}" = getenv ] && [ "${2:-}" = PATH ] \
      && printf '%s\n' "$TEST_DIR/applied/bin:/usr/bin:/bin"
    return 0
  }
  DOTFILES_LINK_DIR="$TEST_DIR/applied"
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  ! failed_ids_contains "security.launchctl_path_dotfiles_first"
}

@test "security: launchctl PATH without any dotfiles bin still fails" {
  mkdir -p "$TEST_DIR/applied/bin"
  launchctl() {
    [ "${1:-}" = getenv ] && [ "${2:-}" = PATH ] \
      && printf '%s\n' "/usr/bin:/bin:$TEST_DIR/applied/bin"
    return 0
  }
  DOTFILES_LINK_DIR="$TEST_DIR/applied"
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  failed_ids_contains "security.launchctl_path_dotfiles_first"
}

@test "security: fix-launchagent unloads a loaded watchman job when its Program binary is missing" {
  mkdir -p "$TEST_HOME/Library/LaunchAgents" "$TEST_HOME/bin"
  cat > "$TEST_HOME/Library/LaunchAgents/com.github.facebook.watchman.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.github.facebook.watchman</string>
  <key>ProgramArguments</key>
  <array>
    <string>$TEST_HOME/missing-watchman</string>
    <string>--foreground</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>$TEST_HOME/apps/dotfiles/bin:/usr/bin:/bin</string>
  </dict>
</dict>
</plist>
EOF
  install_launchagent_path_repair
  write_launchctl_reload_stub
  run_path_repair_with_launchctl_stub 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"unloading orphan LaunchAgent"* ]]
  [[ "$output" != *"Kickstarted com.github.facebook.watchman"* ]]
  /usr/bin/grep -q '^bootout gui/' "$TEST_DIR/launchctl.log"
}

@test "security: fix-launchagent does not start an unloaded watchman job" {
  mkdir -p "$TEST_HOME/Library/LaunchAgents" "$TEST_HOME/bin"
  cat > "$TEST_HOME/Library/LaunchAgents/com.github.facebook.watchman.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.github.facebook.watchman</string>
  <key>ProgramArguments</key>
  <array><string>/bin/echo</string><string>watchman</string></array>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>$TEST_HOME/apps/dotfiles/bin:/usr/bin:/bin</string></dict>
</dict>
</plist>
EOF
  install_launchagent_path_repair
  write_launchctl_reload_stub
  run_path_repair_with_launchctl_stub 0
  [ "$status" -eq 0 ]
  [[ "$output" == *"job was not reloaded"* ]]
  /usr/bin/grep -q '^print gui/' "$TEST_DIR/launchctl.log"
  ! /usr/bin/grep -qE '^(bootout|unload|bootstrap|load|kickstart)' "$TEST_DIR/launchctl.log"
}

@test "security: perl shim exists as symlink" {
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  ! failed_ids_contains "security.perl_shim"
  ! failed_ids_contains "security.perl_shim_not_script"
  ! failed_ids_contains "security.perl_not_system"
  ! failed_ids_contains "security.perl_not_bare_homebrew"
  ! failed_ids_contains "security.perl_launchagent_path"
  ! failed_ids_contains "security.brew_perl_adhoc_signed"
}

@test "security: python3 under LaunchAgent PATH is not system python" {
  mkdir -p "$TEST_HOME/.local/bin"
  ln -sf "$TEST_HOME/.local/share/uv/python/cpython-3.13.13-macos-aarch64-none/bin/python3.13" \
    "$TEST_HOME/.local/bin/python3.13" 2>/dev/null || true
  source "$BATS_TEST_DIRNAME/../modules/security/doctor.sh"
  ! failed_ids_contains "security.python3_launchagent_path"
}
