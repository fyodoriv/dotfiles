#!/usr/bin/env bats

load test_helper

REPO="$BATS_TEST_DIRNAME/.."
SCRIPT="$REPO/bin/dotfiles-podman-idle-stop"

setup() {
  export PODMAN_FIXTURE="$(mktemp -d)"
  export XDG_STATE_HOME="$PODMAN_FIXTURE/state"
  export PODMAN_SCENARIO=idle
  mkdir -p "$PODMAN_FIXTURE/bin"
  cat > "$PODMAN_FIXTURE/bin/podman" <<'STUB'
#!/bin/bash
set -eu
calls="$PODMAN_FIXTURE/calls"
if [[ "${PODMAN_GUEST:-0}" == 1 ]]; then
  [[ "$1" == --remote=false ]] || exit 2
  shift
  store="${PODMAN_STORE:-managed}"
  printf '%s %s\n' "$store" "$1" >> "$calls"
  case "$1" in
    info)
      if [[ "$PODMAN_SCENARIO" == logger-off && "$store" == root ]]; then echo none; else echo journald; fi ;;
    ps)
      case "$PODMAN_SCENARIO:$store" in
        running:root) echo running ;;
        paused:managed) echo paused ;;
      esac ;;
    events)
      if [[ "$PODMAN_SCENARIO" == recent-event && "$store" == managed ]]; then echo start; fi ;;
    *) exit 2 ;;
  esac
  exit 0
fi

case "$1:$2" in
  machine:inspect)
    [[ "$3" == local-fixture ]] || exit 2
    printf 'inspect %s\n' "$3" >> "$calls"
    [[ "$PODMAN_SCENARIO" != down ]] || exit 1
    boot=2026-01-01T00:00:00Z
    if [[ "$PODMAN_SCENARIO" == reboot && "$(grep -c '^inspect ' "$calls")" -gt 1 ]]; then
      boot=2026-01-01T01:00:00Z
    fi
    printf 'local-fixture|running|2025-12-01T00:00:00Z|%s\n' "$boot"
    ;;
  machine:ssh)
    [[ "$3" == local-fixture && "$*" == "machine ssh local-fixture sh -s -- 30" ]] || exit 2
    printf 'ssh %s\n' "$3" >> "$calls"
    shift 3
    PODMAN_GUEST=1 "$@"
    ;;
  machine:stop)
    [[ "$3" == local-fixture ]] || exit 2
    printf 'stop %s\n' "$3" >> "$calls"
    [[ "$PODMAN_SCENARIO" != stop-fails ]]
    ;;
  *) exit 2 ;;
esac
STUB
  cat > "$PODMAN_FIXTURE/bin/sudo" <<'STUB'
#!/bin/bash
[[ "$1" == -n ]] || exit 2
shift
PODMAN_STORE=root exec "$@"
STUB
  cat > "$PODMAN_FIXTURE/bin/journalctl" <<'STUB'
#!/bin/bash
[[ "${PODMAN_STORE:-}" == root ]] || exit 2
[[ "$PODMAN_SCENARIO" == short-history ]] || echo '1767225600.000000 guest journal entry'
STUB
  chmod +x "$PODMAN_FIXTURE/bin/"*
  export PATH="$PODMAN_FIXTURE/bin:$PATH"
}

teardown() {
  rm -rf "$PODMAN_FIXTURE"
}

@test "Podman idle stop makes no calls without an opted-in machine" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "$PODMAN_FIXTURE/calls" ]
}

@test "Podman idle stop selects the same named VM and logs one successful stop" {
  run bash "$SCRIPT" local-fixture 30
  [ "$status" -eq 0 ]
  [ "$(grep -c '^stop ' "$PODMAN_FIXTURE/calls")" -eq 1 ]
  grep -Fxq 'stop local-fixture' "$PODMAN_FIXTURE/calls"
  grep -Fxq 'managed events' "$PODMAN_FIXTURE/calls"
  grep -Fxq 'root events' "$PODMAN_FIXTURE/calls"
  [[ "$output" == *"stopped local-fixture after 30 idle minutes"* ]]
}

@test "Podman idle stop leaves busy or unverified machines running" {
  for scenario in running paused recent-event down logger-off short-history reboot; do
    : > "$PODMAN_FIXTURE/calls"
    run env PODMAN_SCENARIO="$scenario" bash "$SCRIPT" local-fixture 30
    [ "$status" -eq 0 ]
    ! grep -q '^stop ' "$PODMAN_FIXTURE/calls"
  done
}

@test "Podman idle stop reports a failed stop without logging success" {
  run env PODMAN_SCENARIO=stop-fails bash "$SCRIPT" local-fixture 30
  [ "$status" -ne 0 ]
  grep -Fxq 'stop local-fixture' "$PODMAN_FIXTURE/calls"
  [[ "$output" != *"stopped local-fixture"* ]]
}

@test "Podman LaunchAgent uses the selected machine and polls every ten minutes" {
  local plist="$PODMAN_FIXTURE/job.plist"
  chezmoi execute-template --source "$REPO" \
    --override-data '{"dotfiles_dir":"apps/dotfiles","podman_idle_machine":"local-fixture","podman_idle_minutes":45}' \
    < "$REPO/launchagents/com.dotfiles.podman-idle-stop.plist.tmpl" > "$plist"
  plutil -lint "$plist"
  [ "$(plutil -extract ProgramArguments.2 raw -o - "$plist")" = local-fixture ]
  [ "$(plutil -extract ProgramArguments.3 raw -o - "$plist")" = 45 ]
  [ "$(plutil -extract StartInterval raw -o - "$plist")" = 600 ]
}

@test "Podman LaunchAgent is skipped until enabled" {
  local installer="$REPO/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
  eval "$(sed -n '/^should_skip_agent/,/^}/p' "$installer")"
  PODMAN_IDLE_ENABLED=false
  should_skip_agent podman-idle-stop
  PODMAN_IDLE_ENABLED=true
  ! should_skip_agent podman-idle-stop
}
