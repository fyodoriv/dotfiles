#!/usr/bin/env bats
# GNU parallel (bats --jobs) starts each job with SIGALRM ignored. An ignored
# signal stays ignored across exec, so `perl -e 'alarm N; exec @ARGV'` never
# times out unless it resets the handler first. See issue #370.

# Run a command with SIGALRM ignored, like a bats --jobs worker.
_with_alarm_ignored() {
  perl -e '$SIG{ALRM} = "IGNORE"; exec @ARGV' "$@"
}

@test "every one-line perl alarm wrapper resets SIGALRM first" {
  run bash -c "grep -rnE 'perl .*alarm' bin lib tests --exclude=perl-alarm.bats \
    | grep -v 'SIG{ALRM}' | grep -v '^tests/morning.bats'"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}

@test "bin/morning _timeout still times out when SIGALRM is ignored" {
  # Source only the _timeout helper; hide gtimeout/timeout so the perl path runs.
  local fn
  fn="$(sed -n '/^_timeout()/,/^}/p' bin/morning)"
  [ -n "$fn" ]
  local nopath="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$nopath"
  ln -s "$(command -v perl)" "$nopath/perl"
  ln -s "$(command -v sleep)" "$nopath/sleep"
  SECONDS=0
  run _with_alarm_ignored env PATH="$nopath" /bin/bash -c "$fn"$'\n'"_timeout 1 sleep 30"
  [ "$SECONDS" -lt 10 ]
  [ "$status" -ne 0 ]
}

@test "bin/dotfiles-doctor _timeout still times out when SIGALRM is ignored" {
  local fn
  fn="$(sed -n '/^_timeout()/,/^}/p' bin/dotfiles-doctor)"
  [ -n "$fn" ]
  local nopath="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$nopath"
  ln -s "$(command -v perl)" "$nopath/perl"
  ln -s "$(command -v sleep)" "$nopath/sleep"
  SECONDS=0
  run _with_alarm_ignored env PATH="$nopath" /bin/bash -c "$fn"$'\n'"_timeout 1 sleep 30"
  [ "$SECONDS" -lt 10 ]
  [ "$status" -ne 0 ]
}
