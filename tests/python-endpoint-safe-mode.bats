#!/usr/bin/env bats

@test "doctor gates Python-dependent modules behind explicit exception opt-in" {
  grep -q 'DOTFILES_ALLOW_PUBLISHER_NA_PYTHON' bin/dotfiles-doctor
  grep -q 'claude-\*|local-ai|local-llm|mcp-orchestrator|vscode' bin/dotfiles-doctor
  grep -q 'python3 has no publisher authority' bin/dotfiles-doctor
}

@test "doctor does not execute Python from organization overlay modules" {
  fake_bin="$BATS_TEST_TMPDIR/bin"
  overlay_modules="$BATS_TEST_TMPDIR/overlay/modules"
  marker="$BATS_TEST_TMPDIR/python-executed"
  mkdir -p "$fake_bin" "$overlay_modules/mcp-orchestrator"
  cat >"$fake_bin/python3" <<EOF
#!/bin/bash
touch "$marker"
exit 99
EOF
  cat >"$fake_bin/codesign" <<'EOF'
#!/bin/bash
printf '%s\n' 'Signature=adhoc' 'TeamIdentifier=not set' >&2
EOF
  cat >"$fake_bin/chezmoi" <<'EOF'
#!/bin/bash
case "$1 $2" in
  *is_enterprise*) echo true ;;
  *profile*) echo full ;;
  "doctor "*) exit 0 ;;
esac
EOF
  cat >"$overlay_modules/mcp-orchestrator/doctor.sh" <<'EOF'
python3 -c 'raise SystemExit(99)'
EOF
  chmod +x "$fake_bin/python3" "$fake_bin/codesign" "$fake_bin/chezmoi"

  run env HOME="$BATS_TEST_TMPDIR/home" PATH="$fake_bin:/usr/bin:/bin" \
    DOTFILES_DOCTOR_FIXTURE_DIR="$overlay_modules" \
    bin/dotfiles-doctor --module mcp-orchestrator

  [ "$status" -eq 0 ]
  [[ "$output" == *"mcp-orchestrator skipped: python3 has no publisher authority"* ]]
  [ ! -e "$marker" ]
}

@test "apply-time Python tool installers honor endpoint safe mode" {
  grep -q 'AGENTBREW_MCPM_BIN=/nonexistent/' .chezmoiscripts/run_after_agentbrew-sync.sh
  grep -q 'endpoint-policy safe mode' .chezmoiscripts/run_after_install_local_llm.sh.tmpl
  grep -q 'DOTFILES_ALLOW_PUBLISHER_NA_PYTHON' .chezmoiscripts/run_after_uv-tools.sh
}

@test "security doctor no longer claims ad-hoc Python is publisher-safe" {
  grep -q 'security.python3_publisher_authority' modules/security/doctor.sh
  grep -q 'security.recurring_automation_no_publisher_na_python' modules/security/doctor.sh
  ! grep -q 'uv python3.*endpoint-safe' modules/security/doctor.sh
}

_resolve_fixture_python() {
  local hardening="$1" exception="$2" apple_python="$3" purpose="${4-hook}"
  local fixture="$BATS_TEST_TMPDIR/dotfiles"
  mkdir -p "$fixture/bin"
  ln -sf /bin/bash "$fixture/bin/python3"
  run env -u BASH_ENV -u ENV HOME="$BATS_TEST_TMPDIR/home" \
    DOTFILES_ENDPOINT_HARDENING="$hardening" DOTFILES_MANAGED_ENDPOINT=0 \
    DOTFILES_ENDPOINT_AGENT_APPS= DOTFILES_ALLOW_PUBLISHER_NA_PYTHON="$exception" \
    /bin/bash -c '
      source lib/dotfiles-endpoint-paths.sh
      apple_python="$2"
      dotfiles_apple_python() {
        [ "$1" = python3 ] && [ -n "$apple_python" ] || return 1
        printf "%s\n" "$apple_python"
      }
      dotfiles_resolve_python "$1" "$HOME" python3 "$3"
    ' bash "$fixture" "$apple_python" "$purpose"
}

@test "hardened Python resolution prefers Apple developer tools over the local shim" {
  _resolve_fixture_python 1 0 /usr/bin/python3
  [ "$status" -eq 0 ]
  [ "$output" = /usr/bin/python3 ]
}

@test "hardened Python resolution fails when no Apple interpreter is available" {
  _resolve_fixture_python 1 0 ""
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "the Python publisher exception keeps the configured local shim" {
  _resolve_fixture_python 1 1 /usr/bin/python3
  [ "$status" -eq 0 ]
  [ "$output" = "$BATS_TEST_TMPDIR/dotfiles/bin/python3" ]
}

@test "disabled endpoint hardening keeps the configured local shim" {
  _resolve_fixture_python 0 0 /usr/bin/python3
  [ "$status" -eq 0 ]
  [ "$output" = "$BATS_TEST_TMPDIR/dotfiles/bin/python3" ]
}

@test "Apple Python resolution verifies the selected developer-tools binary" {
  [ "$(uname -s)" = Darwin ] || skip "requires Apple developer tools"
  developer="$(/usr/bin/xcode-select -p)" || skip "no selected developer tools"
  [ -x "$developer/usr/bin/python3" ] || skip "no Apple developer-tools Python"

  run env -u BASH_ENV -u ENV /bin/bash -c '
    source lib/dotfiles-endpoint-paths.sh
    dotfiles_apple_python python3
  '

  [ "$status" -eq 0 ]
  [ "$output" = "$developer/usr/bin/python3" ]
  /usr/bin/codesign --verify '-R=anchor apple' "$output"
}

@test "ordinary Python consumers keep the configured interpreter under owner hardening" {
  _resolve_fixture_python 1 0 /usr/bin/python3 ""
  [ "$status" -eq 0 ]
  [ "$output" = "$BATS_TEST_TMPDIR/dotfiles/bin/python3" ]
}

_make_unsigned_hook_python_fixture() {
  local fixture="$BATS_TEST_TMPDIR/dotfiles"
  mkdir -p "$fixture/bin" "$fixture/lib"
  cp lib/dotfiles-endpoint-paths.sh "$fixture/lib/"
  printf '\ndotfiles_apple_python() { return 1; }\n' >>"$fixture/lib/dotfiles-endpoint-paths.sh"
  cat >"$fixture/bin/python3" <<'PYTHON'
#!/bin/bash
printf '%s\n' 'unsigned interpreter ran'
exit 99
PYTHON
  chmod +x "$fixture/bin/python3"
}

@test "session hook leaves the environment alone when signed Python is unavailable" {
  _make_unsigned_hook_python_fixture
  run env -u BASH_ENV -u ENV HOME="$BATS_TEST_TMPDIR/home" \
    DOTFILES_DIR="$BATS_TEST_TMPDIR/dotfiles" DOTFILES_ENDPOINT_HARDENING= \
    DOTFILES_AGENT_ENDPOINT_HARDENING=1 DOTFILES_ALLOW_PUBLISHER_NA_PYTHON=0 \
    /bin/bash -c 'printf "%s\n" "{}" | ./agent-hooks/session-endpoint-path.sh'
  [ "$status" -eq 0 ]
  [ "$output" = '{}' ]
}

@test "hook bootstrap clears inherited Python paths when signed Python is unavailable" {
  _make_unsigned_hook_python_fixture
  run env -u BASH_ENV -u ENV HOME="$BATS_TEST_TMPDIR/home" \
    DOTFILES_DIR="$BATS_TEST_TMPDIR/dotfiles" DOTFILES_ENDPOINT_HARDENING= \
    DOTFILES_AGENT_ENDPOINT_HARDENING=1 DOTFILES_ALLOW_PUBLISHER_NA_PYTHON=0 \
    DOTFILES_PYTHON3=/inherited/python3 DOTFILES_PYTHON3_13=/inherited/python3.13 \
    /bin/bash -c '
      source agent-hooks/bootstrap-endpoint-path.sh
      printf "%s|%s\n" "${DOTFILES_PYTHON3-unset}" "${DOTFILES_PYTHON3_13-unset}"
    '
  [ "$status" -eq 0 ]
  [ "$output" = 'unset|unset' ]
}
