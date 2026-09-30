#!/bin/bash
# lib/coverage-trap.sh — bash trace helper sourced via BASH_ENV during
# `make coverage` runs. Records every executed line of every bash subprocess
# to a per-PID trace file so the post-processor can compute line coverage
# for shell scripts under bin/, lib/, and modules/.
#
# Why this exists: kcov 43 on macOS Tahoe (26.4.x) cannot follow `bash CMD`
# subprocesses spawned by bats because DYLD_INSERT_LIBRARIES is blocked by
# SIP, and bash's BASH_ENV helper unsets BASH_ENV before tests run, so
# subshells lose instrumentation. Bats tests use `run bash "$CMD"` which
# always spawns a child bash — meaning kcov on macOS reports 0% covered
# regardless of which tests ran. See `docs/ci-setup.md` for the full
# rationale and the fix.
#
# This file is exported as BASH_ENV by `bin/dotfiles-coverage`. Every bash
# subprocess with BASH_XTRACEFD support sources it on startup, opens an
# append-only fd to a per-PID trace file, sets BASH_XTRACEFD + PS4 so
# `set -x` lines record `COV@<source>@<lineno>@` markers, then enables
# tracing. Because the script does NOT unset BASH_ENV, every nested bash
# subshell inherits the same instrumentation — which is what kcov fails to do
# on macOS.

# Bash 3.2 (macOS /bin/bash) has no BASH_XTRACEFD; `set -x` would leak trace
# lines to stderr and corrupt output-sensitive tests. Leave those shells
# uninstrumented instead of trading coverage for broken command behavior.
_DOTFILES_COVERAGE_SUPPORTS_XTRACEFD=0
if [ "${BASH_VERSINFO[0]:-0}" -gt 4 ] ||
  { [ "${BASH_VERSINFO[0]:-0}" -eq 4 ] && [ "${BASH_VERSINFO[1]:-0}" -ge 1 ]; }; then
  _DOTFILES_COVERAGE_SUPPORTS_XTRACEFD=1
fi

# Guard: only install once per process. The variable is intentionally NOT
# exported so each new bash subprocess re-runs the install with its own PID
# and its own xtrace fd. Re-sourcing within the same process (e.g., a script
# that explicitly resources BASH_ENV) is a no-op.
#
# We compare against $$ instead of using a plain set/unset flag because
# subshells (parentheses, command substitution) inherit the parent shell's
# variables — and we want them to inherit the trap, not reinstall it.
if [ -n "${COVERAGE_TRACE_DIR:-}" ] &&
  [ "${_DOTFILES_COVERAGE_INSTALLED_PID:-}" != "$$" ] &&
  [ "$_DOTFILES_COVERAGE_SUPPORTS_XTRACEFD" = "1" ]; then
  _DOTFILES_COVERAGE_INSTALLED_PID=$$

  # Create the trace dir lazily — it's harmless to do it from every subshell
  # because mkdir -p is idempotent, and a missing parent would silently drop
  # all coverage data otherwise.
  mkdir -p "$COVERAGE_TRACE_DIR" 2>/dev/null || true

  # One trace file per PID keeps writes lock-free under bats's parallel jobs.
  # Post-processing concatenates them all in `bin/dotfiles-coverage report`.
  _DOTFILES_COVERAGE_FILE="${COVERAGE_TRACE_DIR}/trace.$$.log"

  # Open the trace file on a high-numbered fd so it doesn't collide with
  # tests that manipulate fds 3-9. We use a fixed fd 99 deliberately:
  # `exec {var}>>file` would allocate a fresh fd cleanly, but `exec`'s
  # redirections are PERMANENT for the shell — and any `2>/dev/null` to
  # silence "bash 4.0 doesn't support the syntax" errors would also redirect
  # the script's own stderr to /dev/null, swallowing every `echo … >&2`
  # message and silently breaking output-comparison tests.
  exec 99>>"$_DOTFILES_COVERAGE_FILE"
  _DOTFILES_COVERAGE_FD=99
  BASH_XTRACEFD=$_DOTFILES_COVERAGE_FD

  # PS4 prefix — `bin/dotfiles-coverage report` greps for `^COV@`.
  # ${BASH_SOURCE[0]} is the file currently executing; LINENO is the line.
  # The trailing `@` separates the marker from the traced command text.
  PS4='COV@${BASH_SOURCE[0]}@${LINENO}@'

  set -x
fi
