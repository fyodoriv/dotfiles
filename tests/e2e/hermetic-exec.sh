#!/bin/bash
# Run one command inside a scratch HOME that hermetic-install.sh already
# installed, with the same PATH shims and sandbox-exec profile. Story e2e
# tests use it to drive real dotfiles commands after a real install.
#
# Usage: tests/e2e/hermetic-exec.sh <scratch-dir> <command> [args...]
# The command runs from the dotfiles clone in the scratch HOME; its output goes to
# stdout and stderr, and its exit status is this script's exit status.
set -uo pipefail

SCRATCH="$(cd "$1" && pwd -P)" || exit 2
shift
[ -f "$SCRATCH/profile.sb" ] && [ -d "$SCRATCH/home/apps/dotfiles" ] || {
  echo "hermetic-exec: run hermetic-install.sh $SCRATCH first" >&2
  exit 2
}

cd "$SCRATCH/home/apps/dotfiles" || exit 2
exec env -i HOME="$SCRATCH/home" USER="${USER:-e2e}" LOGNAME="${USER:-e2e}" SHELL=/bin/zsh TERM=dumb \
  TMPDIR="$SCRATCH/tmp" LANG=en_US.UTF-8 \
  PATH="$SCRATCH/home/apps/dotfiles/bin:$SCRATCH/shims:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  GIT_CONFIG_NOSYSTEM=1 \
  sandbox-exec -f "$SCRATCH/profile.sb" "$@"
