#!/usr/bin/env bats

setup() {
  unset BASH_ENV ENV
  repo="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  scratch="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$scratch"
  cat > "$scratch/opencode" <<'SH'
#!/bin/bash
if [ "${1:-}" = '--version' ]; then
  printf '%s\n' "$FAKE_OPENCODE_VERSION"
  exit 0
fi
if [ -n "${FAKE_OPENCODE_TRACE:-}" ]; then printf '%s\n' "$*" >> "$FAKE_OPENCODE_TRACE"; fi
if [ "${1:-}" = service ] && [ "${2:-}" = status ]; then
  if [ "${FAKE_SERVICE_STOPPED:-0}" = 1 ] || [ "${FAKE_API_FAIL:-0}" = 1 ]; then printf 'stopped\n'; else printf 'http://127.0.0.1:49374\n'; fi
  exit 0
fi
if [ "${1:-}" = api ] && [ "${FAKE_API_FAIL:-0}" = 1 ]; then exit 1; fi
if [ "${FAKE_REPORT_PWD:-0}" = 1 ]; then printf 'cwd=<%s> env=<%s>\n' "$(pwd -P)" "$PWD"; fi
if [ "$#" -eq 0 ]; then printf '<no-args>\n'; exit 0; fi
printf '<%s>\n' "$@"
SH
  chmod +x "$scratch/opencode"
  mkdir -p "$BATS_TEST_TMPDIR/home/.opencode/bin"
  cp "$scratch/opencode" "$BATS_TEST_TMPDIR/home/.opencode/bin/opencode"
  export HOME="$BATS_TEST_TMPDIR/home"
  export PATH="$scratch:/usr/bin:/bin"
}

@test "OpenCode 2 oc uses the upstream managed service" {
  export FAKE_OPENCODE_VERSION='opencode v2.2.6'
  run /bin/bash "$repo/bin/dotfiles-opencode" -c
  [ "$status" -eq 0 ]
  [ "$output" = '<-c>' ]
}

@test "OpenCode 2 oc works with no arguments under macOS Bash" {
  export FAKE_OPENCODE_VERSION='opencode v2.2.6'
  run /bin/bash "$repo/bin/dotfiles-opencode"
  [ "$status" -eq 0 ]
  [ "$output" = '<no-args>' ]
}

@test "OpenCode 2 oc preserves the old directory option" {
  export FAKE_OPENCODE_VERSION='opencode v2.2.6'
  run /bin/bash "$repo/bin/dotfiles-opencode" --dir '/tmp/synthetic project' -c
  [ "$status" -eq 0 ]
  [ "$output" = $'<-c>\n</tmp/synthetic project>' ]
}

@test "OpenCode 2 oc accepts the directory option after other flags" {
  export FAKE_OPENCODE_VERSION='opencode v2.2.6'
  run /bin/bash "$repo/bin/dotfiles-opencode" -c --dir '/tmp/synthetic project'
  [ "$status" -eq 0 ]
  [ "$output" = $'<-c>\n</tmp/synthetic project>' ]
}

@test "OpenCode 2 run selects the requested directory without changing the prompt" {
  export FAKE_OPENCODE_VERSION='opencode v2.2.6' FAKE_REPORT_PWD=1
  local target="$BATS_TEST_TMPDIR/synthetic project"
  mkdir -p "$target"
  target="$(cd "$target" && pwd -P)"
  run /bin/bash "$repo/bin/dotfiles-opencode" run --dir "$target" 'hello'
  [ "$status" -eq 0 ]
  expected="$(printf 'cwd=<%s> env=<%s>\n<run>\n<hello>' "$target" "$target")"
  if [ "$output" != "$expected" ]; then printf 'got: %s\nexpected: %s\n' "$output" "$expected" >&3; return 1; fi
}

@test "OpenCode 2 run after a global option uses the requested directory" {
  export FAKE_OPENCODE_VERSION='opencode v2.2.6' FAKE_REPORT_PWD=1
  local target="$BATS_TEST_TMPDIR/synthetic project"
  mkdir -p "$target"
  target="$(cd "$target" && pwd -P)"
  run /bin/bash "$repo/bin/dotfiles-opencode" --log-level warn run --dir "$target" 'hello'
  [ "$status" -eq 0 ]
  expected="$(printf 'cwd=<%s> env=<%s>\n<--log-level>\n<warn>\n<run>\n<hello>' "$target" "$target")"
  if [ "$output" != "$expected" ]; then printf 'got: %s\nexpected: %s\n' "$output" "$expected" >&3; return 1; fi
}

@test "OpenCode 2 does not mistake a global option value for run" {
  export FAKE_OPENCODE_VERSION='opencode v2.2.6'
  run /bin/bash "$repo/bin/dotfiles-opencode" --log-level run --dir '/tmp/synthetic project'
  [ "$status" -eq 0 ]
  [ "$output" = $'<--log-level>\n<run>\n</tmp/synthetic project>' ]
}

@test "OpenCode 1 oc keeps the existing attach interface" {
  export FAKE_OPENCODE_VERSION='1.14.2'
  run /bin/bash "$repo/bin/dotfiles-opencode" -c
  [ "$status" -eq 0 ]
  [ "$output" = $'<attach>\n<http://127.0.0.1:4096>\n<-c>' ]
}

@test "oc uses the same installed binary as the launch agent" {
  export FAKE_OPENCODE_VERSION='1.14.2'
  cat > "$HOME/.opencode/bin/opencode" <<'SH'
#!/bin/bash
if [ "${1:-}" = '--version' ]; then printf 'opencode v2.2.6\n'; else printf '<home:%s>\n' "$@"; fi
SH
  chmod +x "$HOME/.opencode/bin/opencode"
  run /bin/bash "$repo/bin/dotfiles-opencode" -c
  [ "$status" -eq 0 ]
  [ "$output" = '<home:-c>' ]
  run env DOTFILES_DIR="$repo" LIST_MODE=true /bin/bash -c '
    check() { :; }
    check_advisory() { :; }
    source "$DOTFILES_DIR/modules/local-ai/doctor.sh"
    _opencode_bin
  '
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.opencode/bin/opencode" ]
}

@test "oc falls back to the PATH binary when the managed install is absent" {
  rm -f "$HOME/.opencode/bin/opencode"
  export FAKE_OPENCODE_VERSION='opencode v2.2.6'
  run /bin/bash "$repo/bin/dotfiles-opencode" -c
  [ "$status" -eq 0 ]
  [ "$output" = '<-c>' ]
}

@test "an unrecognized OpenCode version fails without starting a client" {
  export FAKE_OPENCODE_VERSION='unknown'
  run /bin/bash "$repo/bin/dotfiles-opencode" -c
  [ "$status" -ne 0 ]
  [[ "$output" == *'Unsupported OpenCode version'* ]]
  [[ "$output" != *'<-c>'* ]]
}

@test "only OpenCode 1 requires the legacy launch agent" {
  export FAKE_OPENCODE_VERSION='1.14.2'
  run /bin/bash -c 'source "$1"; opencode_legacy_service_required "$2"' _ "$repo/lib/opencode-version.sh" "$scratch/opencode"
  [ "$status" -eq 0 ]
  export FAKE_OPENCODE_VERSION='opencode v2.2.6'
  run /bin/bash -c 'source "$1"; opencode_legacy_service_required "$2"' _ "$repo/lib/opencode-version.sh" "$scratch/opencode"
  [ "$status" -ne 0 ]
  export FAKE_OPENCODE_VERSION='unknown'
  run /bin/bash -c 'source "$1"; opencode_legacy_service_required "$2"' _ "$repo/lib/opencode-version.sh" "$scratch/opencode"
  [ "$status" -ne 0 ]
}

@test "oc points to the version-aware launcher" {
  run grep -F "alias oc='dotfiles-opencode'" "$repo/home/zshrc.ai-tools"
  [ "$status" -eq 0 ]
}

@test "oc also works in a noninteractive agent shell" {
  export FAKE_OPENCODE_VERSION='opencode v2.2.6'
  run env PATH="$repo/bin:$PATH" /bin/bash -c 'oc -c'
  [ "$status" -eq 0 ]
  [ "$output" = '<-c>' ]
}

@test "installer retires the old server only for supported newer versions" {
  local selector='source "$1"; eval "$(awk '\''/^should_skip_agent\(\) \{/{p=1} p{print} p && /^\}/{exit}'\'' "$2")"; LOCAL_AI_AGENTS=true; should_skip_agent opencode-serve'
  export FAKE_OPENCODE_VERSION='1.14.2'
  run env HOME="$BATS_TEST_TMPDIR/home" /bin/bash -c "$selector" _ "$repo/lib/opencode-version.sh" "$repo/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
  [ "$status" -ne 0 ]
  export FAKE_OPENCODE_VERSION='opencode v2.2.6'
  run env HOME="$BATS_TEST_TMPDIR/home" /bin/bash -c "$selector" _ "$repo/lib/opencode-version.sh" "$repo/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
  [ "$status" -eq 0 ]
  export FAKE_OPENCODE_VERSION='unknown'
  run env HOME="$BATS_TEST_TMPDIR/home" /bin/bash -c "$selector" _ "$repo/lib/opencode-version.sh" "$repo/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
  [ "$status" -eq 0 ]
}

@test "OpenCode 2 unloads an installed legacy launch agent" {
  export FAKE_OPENCODE_VERSION='opencode v2.2.6'
  export FAKE_LAUNCHCTL_TRACE="$BATS_TEST_TMPDIR/launchctl-trace"
  cat > "$scratch/launchctl" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$FAKE_LAUNCHCTL_TRACE"
[ "$1" = print ] && exit 1
exit 0
SH
  chmod +x "$scratch/launchctl"
  mkdir -p "$BATS_TEST_TMPDIR/home/Library/LaunchAgents"
  touch "$BATS_TEST_TMPDIR/home/Library/LaunchAgents/com.dotfiles.opencode-serve.plist"
  run env HOME="$BATS_TEST_TMPDIR/home" /bin/bash -c '
    source "$1"
    eval "$(awk '\''/^should_skip_agent\(\) \{/{p=1} p{print} p && /^\}/{exit}'\'' "$2")"
    eval "$(awk '\''/^remove_skipped_agent\(\) \{/{p=1} p{print} p && /^\}/{exit}'\'' "$2")"
    self_reload_should_defer() { return 1; }
    LOCAL_AI_AGENTS=true
    should_skip_agent opencode-serve && remove_skipped_agent opencode-serve com.dotfiles.opencode-serve.plist
  ' _ "$repo/lib/opencode-version.sh" "$repo/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/home/Library/LaunchAgents/com.dotfiles.opencode-serve.plist" ]
  [[ "$(cat "$FAKE_LAUNCHCTL_TRACE")" == unload*com.dotfiles.opencode-serve.plist* ]]
}

@test "an unknown version preserves the existing launch agent and reports failure" {
  export FAKE_OPENCODE_VERSION='unknown'
  export FAKE_LAUNCHCTL_TRACE="$BATS_TEST_TMPDIR/launchctl-trace"
  cat > "$scratch/launchctl" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$FAKE_LAUNCHCTL_TRACE"
SH
  chmod +x "$scratch/launchctl"
  mkdir -p "$HOME/Library/LaunchAgents"
  touch "$HOME/Library/LaunchAgents/com.dotfiles.opencode-serve.plist"
  run env HOME="$HOME" /bin/bash -c '
    source "$1"
    for name in should_skip_agent remove_skipped_agent install_plist; do
      eval "$(awk -v name="$name" '\''$0 ~ "^" name "\\(\\) \\{" {p=1} p{print} p && /^\}/{exit}'\'' "$2")"
    done
    self_reload_should_defer() { return 1; }
    LOCAL_AI_AGENTS=true
    failed=0
    install_plist unused com.dotfiles.opencode-serve.plist com.dotfiles.opencode-serve opencode-serve
    printf "failed=%s\n" "$failed"
  ' _ "$repo/lib/opencode-version.sh" "$repo/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
  [ "$status" -eq 0 ]
  [[ "$output" == *'failed=1'* ]]
  [ -e "$HOME/Library/LaunchAgents/com.dotfiles.opencode-serve.plist" ]
  [ ! -e "$FAKE_LAUNCHCTL_TRACE" ]
}

@test "a failed unload preserves the active legacy job and reports failure" {
  export FAKE_OPENCODE_VERSION='opencode v2.2.6'
  cat > "$scratch/launchctl" <<'SH'
#!/bin/bash
case "$1" in unload) exit 1 ;; print) exit 0 ;; esac
SH
  chmod +x "$scratch/launchctl"
  mkdir -p "$HOME/Library/LaunchAgents"
  touch "$HOME/Library/LaunchAgents/com.dotfiles.opencode-serve.plist"
  run env HOME="$HOME" /bin/bash -c '
    source "$1"
    for name in should_skip_agent remove_skipped_agent install_plist; do
      eval "$(awk -v name="$name" '\''$0 ~ "^" name "\\(\\) \\{" {p=1} p{print} p && /^\}/{exit}'\'' "$2")"
    done
    self_reload_should_defer() { return 1; }
    LOCAL_AI_AGENTS=true
    failed=0
    install_plist unused com.dotfiles.opencode-serve.plist com.dotfiles.opencode-serve opencode-serve
    printf "failed=%s\n" "$failed"
  ' _ "$repo/lib/opencode-version.sh" "$repo/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
  [ "$status" -eq 0 ]
  [[ "$output" == *'failed=1'* ]]
  [ -e "$HOME/Library/LaunchAgents/com.dotfiles.opencode-serve.plist" ]
}

@test "managed service health uses upstream status without starting a client" {
  export FAKE_OPENCODE_TRACE="$BATS_TEST_TMPDIR/trace"
  run /bin/bash -c 'source "$1"; opencode_managed_service_healthy "$2"' _ "$repo/lib/opencode-version.sh" "$scratch/opencode"
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_OPENCODE_TRACE")" = 'service status' ]
  export FAKE_API_FAIL=1
  run /bin/bash -c 'source "$1"; opencode_managed_service_healthy "$2"' _ "$repo/lib/opencode-version.sh" "$scratch/opencode"
  [ "$status" -ne 0 ]
}

@test "a stopped managed service is unhealthy and does not start through the API check" {
  export FAKE_SERVICE_STOPPED=1
  export FAKE_OPENCODE_TRACE="$BATS_TEST_TMPDIR/trace"
  run /bin/bash -c 'source "$1"; opencode_managed_service_healthy "$2"' _ "$repo/lib/opencode-version.sh" "$scratch/opencode"
  [ "$status" -ne 0 ]
  [ "$(cat "$FAKE_OPENCODE_TRACE")" = 'service status' ]
}

@test "doctor accepts the managed oc executable without an alias" {
  export FAKE_OPENCODE_VERSION='opencode v2.2.6'
  run env HOME="$HOME" DOTFILES_DIR="$repo" LIST_MODE=true PATH="$repo/bin:$PATH" /bin/bash -c '
    check() { if [ "$1" = local-ai.oc_alias ]; then if eval "$3"; then echo PASS; else echo FAIL; fi; fi; return 0; }
    check_advisory() { :; }
    source "$DOTFILES_DIR/modules/local-ai/doctor.sh"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *PASS* ]]
}

@test "doctor rejects a stale alias and unrelated oc executable" {
  export FAKE_OPENCODE_VERSION='opencode v2.2.6'
  printf "alias oc='opencode attach http://127.0.0.1:4096'\n" > "$HOME/.zshrc.local"
  cp "$scratch/opencode" "$scratch/oc"
  run env HOME="$HOME" DOTFILES_DIR="$repo" LIST_MODE=true PATH="$scratch:/usr/bin:/bin" /bin/bash -c '
    check() { if [ "$1" = local-ai.oc_alias ]; then if eval "$3"; then echo PASS; else echo FAIL; fi; fi; return 0; }
    check_advisory() { :; }
    source "$DOTFILES_DIR/modules/local-ai/doctor.sh"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *FAIL* ]]
}

@test "doctor accepts the deployed managed alias" {
  export FAKE_OPENCODE_VERSION='opencode v2.2.6'
  printf "alias oc='dotfiles-opencode'\n" > "$HOME/.zshrc.ai-tools"
  run env HOME="$HOME" DOTFILES_DIR="$repo" LIST_MODE=true PATH="$repo/bin:$scratch:/usr/bin:/bin" /bin/bash -c '
    command() { if [ "$1" = -v ] && [ "${2:-}" = oc ]; then return 1; fi; builtin command "$@"; }
    check() { if [ "$1" = local-ai.oc_alias ]; then if eval "$3"; then echo PASS; else echo FAIL; fi; fi; return 0; }
    check_advisory() { :; }
    source "$DOTFILES_DIR/modules/local-ai/doctor.sh"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *PASS* ]]
}

@test "doctor rejects the managed alias when its launcher is unavailable" {
  export FAKE_OPENCODE_VERSION='opencode v2.2.6'
  printf "alias oc='dotfiles-opencode'\n" > "$HOME/.zshrc.ai-tools"
  run env HOME="$HOME" DOTFILES_DIR="$repo" LIST_MODE=true PATH="$scratch:/usr/bin:/bin" /bin/bash -c '
    check() { if [ "$1" = local-ai.oc_alias ]; then if eval "$3"; then echo PASS; else echo FAIL; fi; fi; return 0; }
    check_advisory() { :; }
    source "$DOTFILES_DIR/modules/local-ai/doctor.sh"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *FAIL* ]]
}

@test "doctor uses the managed service checks for OpenCode 2" {
  export FAKE_OPENCODE_VERSION='opencode v2.2.6'
  export FAKE_OPENCODE_TRACE="$BATS_TEST_TMPDIR/trace"
  run env HOME="$BATS_TEST_TMPDIR/home" DOTFILES_DIR="$repo" LIST_MODE=true /bin/bash -c '
    check() {
      case "$1" in
        local-ai.opencode_serve_agent_loaded|local-ai.opencode_serve_api)
          if eval "$3"; then printf "PASS:%s\n" "$1"; else printf "FAIL:%s\n" "$1"; fi ;;
      esac
    }
    check_advisory() { :; }
    source "$DOTFILES_DIR/modules/local-ai/doctor.sh"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *'PASS:local-ai.opencode_serve_agent_loaded'* ]]
  [[ "$output" == *'PASS:local-ai.opencode_serve_api'* ]]
  [[ "$(cat "$FAKE_OPENCODE_TRACE")" == *'service status'* ]]
  [[ "$(cat "$FAKE_OPENCODE_TRACE")" != *'api get'* ]]
}

@test "doctor keeps the legacy service checks for OpenCode 1" {
  export FAKE_OPENCODE_VERSION='1.14.2'
  export FAKE_LEGACY_TRACE="$BATS_TEST_TMPDIR/legacy-trace"
  for tool in launchctl curl; do
    cat > "$scratch/$tool" <<'SH'
#!/bin/bash
printf '%s\n' "${0##*/} $*" >> "$FAKE_LEGACY_TRACE"
SH
    chmod +x "$scratch/$tool"
  done
  run env HOME="$BATS_TEST_TMPDIR/home" DOTFILES_DIR="$repo" LIST_MODE=true /bin/bash -c '
    check() {
      case "$1" in
        local-ai.opencode_serve_agent_loaded|local-ai.opencode_serve_api)
          if eval "$3"; then printf "PASS:%s\n" "$1"; else printf "FAIL:%s\n" "$1"; fi ;;
      esac
    }
    check_advisory() { :; }
    source "$DOTFILES_DIR/modules/local-ai/doctor.sh"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *'PASS:local-ai.opencode_serve_agent_loaded'* ]]
  [[ "$output" == *'PASS:local-ai.opencode_serve_api'* ]]
  [[ "$(cat "$FAKE_LEGACY_TRACE")" == *'http://127.0.0.1:4096/'* ]]
}
