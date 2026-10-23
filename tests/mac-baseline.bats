#!/usr/bin/env bats
# baseline_zsh_ms (lib/mac-baseline.sh): the zsh start time in the install
# receipt and `dotfiles metrics --gains`. A finished run took more than 0 ms,
# so a fast Mac must never record 0 (the US01 e2e flake, task
# e2e-zsh-ms-zero-flake); a shell that fails must record nothing, so the
# e2e check `.before.zsh_ms > 0` still catches a missing or broken measure.

load test_helper

REPO_ROOT="$BATS_TEST_DIRNAME/.."

setup() {
  TEST_DIR="$(mktemp -d)"
  mkdir -p "$TEST_DIR/bin"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# measure <runs> [<PATH>]: baseline_zsh_ms under /bin/bash (3.2) with PATH.
measure() {
  PATH="${2:-$TEST_DIR/bin:/usr/bin:/bin}" /bin/bash -c 'source "$1/lib/mac-baseline.sh"; baseline_zsh_ms "$2"' _ "$REPO_ROOT" "$1"
}

# no_perl_tools: a PATH folder with the tools the fallback needs, no perl.
no_perl_tools() {
  mkdir -p "$TEST_DIR/noperl"
  for t in sort awk sh cat sleep; do ln -sf "$(command -v "$t")" "$TEST_DIR/noperl/$t"; done
}

@test "a shell that starts in under 10 ms never measures 0 ms" {
  ln -s /usr/bin/true "$TEST_DIR/bin/zsh"
  for _ in $(seq 20); do
    ms="$(measure 3)"
    [[ "$ms" =~ ^[0-9]+$ ]] || { echo "not a number: '$ms'"; return 1; }
    [ "$ms" -ge 1 ] || { echo "measured $ms ms"; return 1; }
  done
}

@test "a shell that cannot run gives no measure" {
  # A zsh that dies from a signal at once: it could not start.
  printf '#!/bin/sh\nkill -9 $$\n' > "$TEST_DIR/bin/zsh"
  chmod +x "$TEST_DIR/bin/zsh"
  run measure 3
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "a working zsh whose last startup line is false still gets a number" {
  # As on a fresh Mac outside Terminal.app (/etc/zshrc ends with a test that
  # is false), or after an install line that returns 1.
  command -v zsh >/dev/null 2>&1 || skip "no zsh"
  mkdir -p "$TEST_DIR/home"
  printf 'false\n' > "$TEST_DIR/home/.zshrc"
  zsh_dir="$(dirname "$(command -v zsh)")"
  ms="$(HOME="$TEST_DIR/home" ZDOTDIR="$TEST_DIR/home" measure 3 "$zsh_dir:/usr/bin:/bin")"
  echo "$ms"
  [[ "$ms" =~ ^[0-9]+$ ]] && [ "$ms" -ge 1 ]
}

@test "no zsh gives no measure" {
  # /bin/zsh exists on macOS; hide it with a PATH that has no zsh at all.
  mkdir -p "$TEST_DIR/tools"
  for t in sort awk perl sh cat; do ln -s "$(command -v "$t")" "$TEST_DIR/tools/$t"; done
  run measure 3 "$TEST_DIR/tools"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "a slower shell measures about its real time" {
  printf '#!/bin/sh\nsleep 0.2\n' > "$TEST_DIR/bin/zsh"
  chmod +x "$TEST_DIR/bin/zsh"
  ms="$(measure 1)"
  echo "$ms"
  [ "$ms" -ge 150 ] && [ "$ms" -lt 5000 ]
}

@test "without perl it still never measures 0 ms" {
  no_perl_tools
  ln -s /usr/bin/true "$TEST_DIR/noperl/zsh"
  export DOTFILES_BASELINE_PERL=
  for _ in $(seq 10); do
    ms="$(measure 3 "$TEST_DIR/noperl")"
    [[ "$ms" =~ ^[0-9]+$ ]] && [ "$ms" -ge 1 ] || { echo "measured '$ms'"; return 1; }
  done
  printf '#!/bin/sh\nkill -9 $$\n' > "$TEST_DIR/noperl/zsh.dead"
  chmod +x "$TEST_DIR/noperl/zsh.dead"
  ln -sf "$TEST_DIR/noperl/zsh.dead" "$TEST_DIR/noperl/zsh"
  run measure 3 "$TEST_DIR/noperl"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "the fallback reads a decimal comma from /usr/bin/time (0,52 is not 1 ms)" {
  no_perl_tools
  # sleep reads "0.5" by the locale, so it gets the C locale itself; the
  # timer around it still prints "0,5x" in de_DE.
  printf '#!/bin/sh\nLC_ALL=C exec sleep 0.5\n' > "$TEST_DIR/noperl/zsh"
  chmod +x "$TEST_DIR/noperl/zsh"
  ms="$(DOTFILES_BASELINE_PERL= LANG=de_DE.UTF-8 LC_ALL=de_DE.UTF-8 measure 1 "$TEST_DIR/noperl")"
  echo "$ms"
  [ "$ms" -ge 400 ]
}

@test "a perl that cannot load Time::HiRes falls back to /usr/bin/time" {
  printf '#!/bin/sh\necho "Can not locate Time/HiRes.pm" >&2\nexit 2\n' > "$TEST_DIR/badperl"
  chmod +x "$TEST_DIR/badperl"
  ln -s /usr/bin/true "$TEST_DIR/bin/zsh"
  ms="$(DOTFILES_BASELINE_PERL="$TEST_DIR/badperl" measure 3)"
  echo "$ms"
  [[ "$ms" =~ ^[0-9]+$ ]] && [ "$ms" -ge 1 ]
}

@test "the receipt timing never stops a set -e caller when a run fails" {
  printf '#!/bin/sh\nkill -9 $$\n' > "$TEST_DIR/bin/zsh"
  chmod +x "$TEST_DIR/bin/zsh"
  run env PATH="$TEST_DIR/bin:/usr/bin:/bin" /bin/bash -c 'set -euo pipefail; source "$1/lib/mac-baseline.sh"; _baseline_run_ms zsh -i -c "exit 0"; echo reached' _ "$REPO_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *reached* ]]
}

@test "a perl that fails with exit 1 (a module mismatch) still falls back to /usr/bin/time" {
  printf '#!/bin/sh\necho "HiRes.c: loadable library and perl binaries are mismatched" >&2\nexit 1\n' > "$TEST_DIR/badperl1"
  chmod +x "$TEST_DIR/badperl1"
  ln -s /usr/bin/true "$TEST_DIR/bin/zsh"
  ms="$(DOTFILES_BASELINE_PERL="$TEST_DIR/badperl1" measure 3)"
  echo "$ms"
  [[ "$ms" =~ ^[0-9]+$ ]] && [ "$ms" -ge 1 ]
}

@test "another perl's modules on PERL5LIB cannot break the measure" {
  mkdir -p "$TEST_DIR/lib5/Time"
  # Dies with errno 1, so perl exits 1, as a real module mismatch does.
  printf 'package Time::HiRes; $! = 1; die "loadable library and perl binaries are mismatched\\n";\n1;\n' > "$TEST_DIR/lib5/Time/HiRes.pm"
  ln -s /usr/bin/true "$TEST_DIR/bin/zsh"
  ms="$(PERL5LIB="$TEST_DIR/lib5" measure 3)"
  echo "$ms"
  [[ "$ms" =~ ^[0-9]+$ ]] && [ "$ms" -ge 1 ]
}
