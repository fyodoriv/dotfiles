#!/usr/bin/env bats

@test "apply-time hook wrapper uses Apple plutil, not Python" {
  script=".chezmoiscripts/run_after_cursor-hooks-endpoint-wrap.sh"
  grep -q '/usr/bin/plutil' "$script"
  ! grep -vE '^[[:space:]]*#' "$script" | grep -qE '(^|[[:space:]])python3([[:space:]]|$)'
}

@test "Cursor parity does not execute unsigned Python by default" {
  fake_bin="$BATS_TEST_TMPDIR/bin"
  marker="$BATS_TEST_TMPDIR/python-executed"
  mkdir -p "$fake_bin"
  cat >"$fake_bin/python3" <<EOF
#!/bin/bash
touch "$marker"
exit 99
EOF
  chmod +x "$fake_bin/python3"

  run env PATH="$fake_bin:/usr/bin:/bin" \
    bash .chezmoiscripts/run_after_cursor-agent-parity.sh --check

  [ "$status" -eq 0 ]
  [[ "$output" == *"endpoint-policy safe mode"* ]]
  [ ! -e "$marker" ]
}

@test "doctor gates Python-dependent modules behind explicit exception opt-in" {
  grep -q 'DOTFILES_ALLOW_PUBLISHER_NA_PYTHON' bin/dotfiles-doctor
  grep -q 'claude-\*|cursor|devin|local-ai|local-llm|mcp-orchestrator|vscode|windsurf' bin/dotfiles-doctor
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
    EXTRA_DOCTOR_DIR="$overlay_modules" \
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
