#!/usr/bin/env bats
# Cheap guards for the hermetic install e2e (tests/e2e/). They run in the
# normal suite, so a change that would weaken the e2e fails fast.

load test_helper

REPO_ROOT="$BATS_TEST_DIRNAME/.."

@test "lifecycle scripts call OS-changing tools through PATH, so the e2e shims catch them" {
  # An absolute path (/usr/bin/defaults) would bypass the shims; the sandbox
  # would then fail the e2e. Only Homebrew's own `brew shellenv` bootstrap is allowed.
  run grep -nE '(/usr/bin|/bin|/usr/sbin|/sbin|/opt/homebrew/bin|/usr/local/bin)/(defaults|launchctl|killall|sudo|pmset|osascript|softwareupdate|mdutil|tccutil|mas|brew)\b' \
    "$REPO_ROOT"/.chezmoiscripts/* "$REPO_ROOT"/macos*.sh
  local bad
  bad="$(printf '%s\n' "$output" | grep -v 'brew shellenv' | grep -vE '\[ -[fxde] [^]]*\]' | grep -vE ':[0-9]+:\s*#' | grep -v '^$' || true)"
  [ -z "$bad" ] || { echo "$bad"; return 1; }
}

@test "needs-e2e triggers on installer paths and skips unrelated ones" {
  run bash -c "printf 'bin/dotfiles-install\n' | '$REPO_ROOT/tests/e2e/needs-e2e.sh' --stdin"
  [ "$status" -eq 0 ]
  run bash -c "printf '.chezmoiscripts/run_after_foo.sh\nREADME.md\n' | '$REPO_ROOT/tests/e2e/needs-e2e.sh' --stdin"
  [ "$status" -eq 0 ]
  [ "$output" = ".chezmoiscripts/run_after_foo.sh" ]
  # The story e2e drives morning, git-safe, and the git doctor module.
  run bash -c "printf 'bin/morning\nmodules/git/doctor.sh\n' | '$REPO_ROOT/tests/e2e/needs-e2e.sh' --stdin"
  [ "$status" -eq 0 ]
  run bash -c "printf 'README.md\ndocs/x.md\nmodules/ssh/doctor.sh\nbin/dotfiles-metrics\ntests/foo.bats\n' | '$REPO_ROOT/tests/e2e/needs-e2e.sh' --stdin"
  [ "$status" -eq 1 ]
}

@test "make check runs the install e2e only when needed" {
  grep -qE '^check:' "$REPO_ROOT/Makefile"
  grep -qE 'gate-timed.sh e2e .*e2e-if-needed' "$REPO_ROOT/Makefile"
  grep -q 'needs-e2e.sh' "$REPO_ROOT/Makefile"
}
