#!/usr/bin/env bats

@test "Ollama LaunchAgent uses collision-safe wrapper" {
  grep -q 'bin/ollama-launchagent' launchagents/com.dotfiles.ollama.plist.tmpl
  ! grep -q '<string>serve</string>' launchagents/com.dotfiles.ollama.plist.tmpl
}

@test "Ollama LaunchAgent does not respawn after healthy-owner exit" {
  grep -A4 '<key>KeepAlive</key>' launchagents/com.dotfiles.ollama.plist.tmpl \
    | grep -q '<key>SuccessfulExit</key>'
  grep -A4 '<key>KeepAlive</key>' launchagents/com.dotfiles.ollama.plist.tmpl \
    | grep -q '<false/>'
}

@test "Ollama wrapper probes API before executing publisher binary" {
  probe_line="$(grep -n '/usr/bin/nc' bin/ollama-launchagent | cut -d: -f1)"
  exec_line="$(grep -n 'exec.*OLLAMA_BIN.*serve' bin/ollama-launchagent | cut -d: -f1)"
  [ -n "$probe_line" ]
  [ -n "$exec_line" ]
  [ "$probe_line" -lt "$exec_line" ]
}

@test "Ollama wrapper exits successfully when API owner is healthy" {
  grep -q 'API already healthy on :11434' bin/ollama-launchagent
  grep -A2 'API already healthy on :11434' bin/ollama-launchagent | grep -q 'exit 0'
}

@test "blocked Ollama publisher never executes when API is unavailable" {
  test_home="$BATS_TEST_TMPDIR/home"
  fake_bin="$BATS_TEST_TMPDIR/bin"
  marker="$BATS_TEST_TMPDIR/ollama-executed"
  mkdir -p "$test_home" "$fake_bin"
  cat >"$fake_bin/nc" <<'EOF'
#!/bin/bash
cat >/dev/null
exit 1
EOF
  cat >"$fake_bin/uname" <<'EOF'
#!/bin/bash
echo Darwin
EOF
  cat >"$fake_bin/codesign" <<'EOF'
#!/bin/bash
printf '%s\n' \
  'Authority=Developer ID Application: Infra Technologies, Inc (3MU9H2V9Y9)' \
  'TeamIdentifier=3MU9H2V9Y9' >&2
EOF
  cat >"$fake_bin/ollama" <<EOF
#!/bin/bash
touch "$marker"
exit 99
EOF
  chmod +x "$fake_bin/nc" "$fake_bin/uname" "$fake_bin/codesign" "$fake_bin/ollama"

  run env HOME="$test_home" PATH="$fake_bin:/usr/bin:/bin" \
    DOTFILES_MANAGED_ENDPOINT=1 \
    NC_BIN="$fake_bin/nc" OLLAMA_BIN="$fake_bin/ollama" \
    bin/ollama-launchagent

  [ "$status" -eq 0 ]
  [ ! -e "$marker" ]
  grep -qi 'publisher.*blocked' "$test_home/.local/share/dotfiles/logs/ollama-launchagent.log"
}
