#!/usr/bin/env bats

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_DOTFILES="$TEST_DIR/dotfiles"
  STUB_DIR="$TEST_DIR/bin"
  mkdir -p "$TEST_DOTFILES/modules/memory" "$STUB_DIR"
  cp "$BATS_TEST_DIRNAME/../modules/memory/doctor.sh" "$TEST_DOTFILES/modules/memory/doctor.sh"
  export DOTFILES_DIR="$TEST_DOTFILES"
  export PATH="$STUB_DIR:/usr/bin:/bin"
  export CHECK_LOG="$TEST_DIR/checks.log"
  cat > "$STUB_DIR/jq" <<'STUB'
#!/bin/bash
if [ "${1:-}" = "-e" ] && [ "${2:-}" = ".enabled == true" ]; then
  /usr/bin/grep -Eq '"enabled"[[:space:]]*:[[:space:]]*true'
  exit $?
fi
exit 1
STUB
  chmod +x "$STUB_DIR/jq"
}

teardown() {
  rm -rf "$TEST_DIR"
}

run_memory_doctor() {
  check() {
    printf 'check\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$CHECK_LOG"
    eval "$3"
  }
  check_advisory() {
    printf 'advisory\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$CHECK_LOG"
    eval "$3"
  }
  # shellcheck disable=SC1091
  source "$DOTFILES_DIR/modules/memory/doctor.sh"
}

@test "memory doctor reports a missing agentbrew CLI with enable guidance" {
  run run_memory_doctor

  [ "$status" -eq 0 ]
  grep -q $'check\tmemory.agentbrew_available' "$CHECK_LOG"
  grep -q 'agentbrew memory enable' "$CHECK_LOG"
}

@test "memory doctor delegates runtime and bootstrap health to agentbrew" {
  cat > "$STUB_DIR/agentbrew" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${CHECK_LOG}.agentbrew"
case "$*" in
  "memory status --json")
    printf '%s\n' '{"enabled":true}'
    ;;
  "memory doctor"|"memory sync-projects --check"|"memory transport-report")
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
STUB
  chmod +x "$STUB_DIR/agentbrew"

  run run_memory_doctor

  [ "$status" -eq 0 ]
  grep -q $'advisory\tmemory.agentbrew_doctor' "$CHECK_LOG"
  grep -q 'behavioral bootstrap healthy' "$CHECK_LOG"
  grep -q $'\tagentbrew memory fix$' "$CHECK_LOG"
  grep -qx 'memory doctor' "${CHECK_LOG}.agentbrew"
  grep -q $'advisory\tmemory.project_sync_advisory' "$CHECK_LOG"
  grep -q $'advisory\tmemory.transport_compatibility' "$CHECK_LOG"
  grep -qx 'memory sync-projects --check' "${CHECK_LOG}.agentbrew"
  grep -qx 'memory transport-report' "${CHECK_LOG}.agentbrew"
}

@test "memory doctor skips project-sync and transport advisories when memory is disabled" {
  cat > "$STUB_DIR/agentbrew" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${CHECK_LOG}.agentbrew"
case "$*" in
  "memory status --json")
    printf '%s\n' '{"enabled":false}'
    ;;
  "memory doctor")
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
STUB
  chmod +x "$STUB_DIR/agentbrew"

  run run_memory_doctor

  [ "$status" -eq 0 ]
  grep -q $'advisory\tmemory.agentbrew_doctor' "$CHECK_LOG"
  ! grep -q 'memory.project_sync_advisory' "$CHECK_LOG"
  ! grep -q 'memory.transport_compatibility' "$CHECK_LOG"
}
