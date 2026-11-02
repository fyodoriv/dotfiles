# Each Bats test owns its probe, receipts, controllers and release files.
rt_probe_setup() {
  case "${BASH_ENV:-}" in
    */lib/coverage-trap.sh) unset ENV ;;
    *) unset BASH_ENV ENV ;;
  esac
  export BATS_RT_PROBE_ROOT="$BATS_TEST_TMPDIR/realtime-probe"
  mkdir -p "$BATS_RT_PROBE_ROOT/bin" "$BATS_RT_PROBE_ROOT/seen"
  cat > "$BATS_RT_PROBE_ROOT/bin/pgrep" <<'PROBE'
#!/bin/sh
[ "$1" = -x ] && [ "$2" = queue-probe-fixture ] || exit 2
mode=$(cat "$BATS_RT_PROBE_ROOT/mode")
: > "$BATS_RT_PROBE_ROOT/seen/$mode"
case "$mode" in
  clear) exit 1 ;;
  present) printf '42\n'; exit 0 ;;
  error2) exit 2 ;;
  error3) exit 3 ;;
  missing) exit 127 ;;
  empty) exit 0 ;;
  malformed) printf 'not-a-pid\n'; exit 0 ;;
  contradictory) printf '42\n'; exit 1 ;;
  blank_no_match) printf '\n'; exit 1 ;;
  extra_line) printf '42\n\n'; exit 0 ;;
  *) exit 3 ;;
esac
PROBE
  chmod 700 "$BATS_RT_PROBE_ROOT/bin/pgrep"
  export PATH="$BATS_RT_PROBE_ROOT/bin:$PATH"
  export HEAVY_RUN_PAUSE_APPS=queue-probe-fixture HEAVY_RUN_SLOTS=2 HEAVY_RUN_PROJECT_SLOTS=2
  BATS_RT_PROBE_CHILDREN=""
  rt_probe_mode clear
}

rt_probe_mode() {
  printf '%s\n' "$1" > "$BATS_RT_PROBE_ROOT/mode.next"
  mv "$BATS_RT_PROBE_ROOT/mode.next" "$BATS_RT_PROBE_ROOT/mode"
}

rt_probe_wait_path() {
  local i
  for i in $(seq 100); do
    [ -e "$1" ] && return 0
    sleep 0.1
  done
  return 1
}

rt_probe_prepare() {
  local context="$1" mode="$2"
  if [ "$context" = additional ]; then
    start_fifo_holder
    BATS_RT_PROBE_CHILDREN="$BATS_RT_PROBE_CHILDREN $!"
    wait_held
    rt_probe_mode "$mode"
    rt_probe_wait_path "$BATS_RT_PROBE_ROOT/seen/$mode"
  else
    rt_probe_mode "$mode"
  fi
}

rt_probe_spawn() {
  local context="$1"
  if [ "$context" = exclusive ]; then
    "$SCRIPT" --exclusive touch "$BATS_RT_PROBE_ROOT/admitted" > "$BATS_RT_PROBE_ROOT/controller.log" 2>&1 &
  else
    "$SCRIPT" touch "$BATS_RT_PROBE_ROOT/admitted" > "$BATS_RT_PROBE_ROOT/controller.log" 2>&1 &
  fi
  BATS_RT_PROBE_PID=$!
  BATS_RT_PROBE_CHILDREN="$BATS_RT_PROBE_CHILDREN $BATS_RT_PROBE_PID"
}

# A workload marker or this controller's held ticket is a real decision.
rt_probe_observe() {
  local i ticket reason
  BATS_RT_PROBE_REASON=""
  BATS_RT_PROBE_TICKET=""
  for i in $(seq 100); do
    [ -e "$BATS_RT_PROBE_ROOT/admitted" ] && return 0
    for ticket in "$HEAVY_RUN_DIR"/queue/*-"$BATS_RT_PROBE_PID"; do
      [ -f "$ticket" ] && [ -f "$ticket.why" ] || continue
      if perl -MFcntl=:flock -e 'open(my $f,"<",$ARGV[0]) or exit 2; exit(flock($f,LOCK_EX|LOCK_NB) ? 1 : 0)' "$ticket"; then
        reason=$(cat "$ticket.why")
        case "$reason" in '' | starting) continue ;; esac
        [ ! -e "$ticket.grant" ] || continue
        BATS_RT_PROBE_REASON="$reason"
        BATS_RT_PROBE_TICKET="$ticket"
        return 0
      fi
    done
    sleep 0.1
  done
  return 1
}

rt_probe_unknown() {
  local context="$1" mode="$2"
  rt_probe_setup
  rt_probe_prepare "$context" "$mode"
  rt_probe_spawn "$context"
  rt_probe_wait_path "$BATS_RT_PROBE_ROOT/seen/$mode"
  rt_probe_observe
  [ ! -e "$BATS_RT_PROBE_ROOT/admitted" ]
  [ "$BATS_RT_PROBE_REASON" = 'real-time app probe unavailable' ]
  [ -n "$BATS_RT_PROBE_TICKET" ] && [ ! -e "$BATS_RT_PROBE_TICKET.grant" ]
  rt_probe_mode clear
  rt_probe_wait_path "$BATS_RT_PROBE_ROOT/admitted"
  wait "$BATS_RT_PROBE_PID"
}

rt_probe_clear() {
  local context="$1"
  rt_probe_setup
  rt_probe_prepare "$context" clear
  rt_probe_spawn "$context"
  rt_probe_wait_path "$BATS_RT_PROBE_ROOT/seen/clear"
  rt_probe_wait_path "$BATS_RT_PROBE_ROOT/admitted"
  wait "$BATS_RT_PROBE_PID"
}

rt_probe_present() {
  local context="$1"
  rt_probe_setup
  rt_probe_prepare "$context" present
  rt_probe_spawn "$context"
  rt_probe_wait_path "$BATS_RT_PROBE_ROOT/seen/present"
  rt_probe_observe
  [ ! -e "$BATS_RT_PROBE_ROOT/admitted" ]
  [ "$BATS_RT_PROBE_REASON" = 'queue-probe-fixture is running (a real-time app)' ]
  [ -n "$BATS_RT_PROBE_TICKET" ] && [ ! -e "$BATS_RT_PROBE_TICKET.grant" ]
  rt_probe_mode clear
  rt_probe_wait_path "$BATS_RT_PROBE_ROOT/admitted"
  wait "$BATS_RT_PROBE_PID"
}

rt_probe_cleanup() {
  [ -n "${BATS_RT_PROBE_ROOT:-}" ] || return 0
  rt_probe_mode clear
  : > "$BATS_RT_PROBE_ROOT/release-workload"
  [ -z "${FIFO_RELEASE:-}" ] || release_fifo_holder
  local child live i
  for i in $(seq 100); do
    local found=false
    for child in ${BATS_RT_PROBE_CHILDREN:-}; do
      for live in $(jobs -pr) $(jobs -ps); do
        [ "$live" != "$child" ] || found=true
      done
    done
    $found || break
    sleep 0.1
  done
  for child in ${BATS_RT_PROBE_CHILDREN:-}; do
    for live in $(jobs -pr) $(jobs -ps); do
      if [ "$live" = "$child" ]; then
        kill -CONT "$child" 2>/dev/null || true
        kill -TERM "$child" 2>/dev/null || true
      fi
    done
    wait "$child" 2>/dev/null || true
  done
}
