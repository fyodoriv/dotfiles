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

@test "needs-e2e triggers on a lib that the e2e commands load" {
  run bash -c "printf 'lib/output.sh\n' | '$REPO_ROOT/tests/e2e/needs-e2e.sh' --stdin"
  [ "$status" -eq 0 ]
  [ "$output" = "lib/output.sh" ]
  # Libs that a doctor module or a lifecycle script loads count too.
  # So do the repo files a lifecycle script runs (macos.sh) and their libs
  # and data (lib/apply-defaults.sh, data/macos-defaults.json).
  for lib in lib/gitconfig-user-migrate.sh lib/launchagent-duplicates.sh lib/self-reload.sh lib/agentbrew-locate.sh \
      macos.sh lib/apply-defaults.sh data/macos-defaults.json bin/jetbrains-install-plugins; do
    run bash -c "printf '%s\n' '$lib' | '$REPO_ROOT/tests/e2e/needs-e2e.sh' --stdin"
    [ "$status" -eq 0 ] || { echo "no e2e for $lib"; return 1; }
  done
  run bash -c "printf 'lib/errors-log.sh\nREADME.md\n' | '$REPO_ROOT/tests/e2e/needs-e2e.sh' --stdin"
  [ "$status" -eq 0 ]
  [ "$output" = "lib/errors-log.sh" ]
}

@test "make check runs the install e2e only when needed" {
  grep -qE '^check:' "$REPO_ROOT/Makefile"
  grep -qE 'gate-timed.sh e2e .*e2e-if-needed' "$REPO_ROOT/Makefile"
  grep -q 'needs-e2e.sh' "$REPO_ROOT/Makefile"
}

@test "an Agentfile-only change skips the install e2e, because the e2e never runs agentbrew" {
  run bash -c "printf 'Agentfile.yaml\n' | '$REPO_ROOT/tests/e2e/needs-e2e.sh' --stdin"
  [ "$status" -eq 1 ]
  # The reason it is safe: the install e2e passes --no-agentbrew, and
  # run_after_agentbrew-sync.sh reads the Agentfile only after it finds
  # agentbrew (tests/chezmoiscripts.bats: "skips when no CLI is available").
  grep -q -- '--no-agentbrew' "$REPO_ROOT/tests/e2e/dotfiles-install-e2e.bats"
  run awk '/AGENTFILE=/ { a = NR } /agentbrew not available/ { n = NR } /_sync_from_agentfile "\$AGENTFILE"/ { s = NR } END { exit !(a && n && s && n < s) }' \
    "$REPO_ROOT/.chezmoiscripts/run_after_agentbrew-sync.sh"
  [ "$status" -eq 0 ]
}
