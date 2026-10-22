#!/usr/bin/env bats
# Hard-to-undo dotfiles commands ask first (lib/confirm.sh): a y/N prompt at
# a terminal, or --yes. Without a terminal and without --yes they refuse and
# change nothing, so an agent has to ask the user first. --dry-run and --help
# need no yes. Covers `dotfiles contribute` (a public PR) and `dotfiles init`
# here, the prompt itself (on /dev/tty, through a pty), and
# tests/bin-dotfiles-update.bats, tests/dotfiles-upgrade.bats, and
# tests/plugin-v2.bats cover the gates inside those scripts.

load test_helper

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
  TEST_DIR="$(mktemp -d)"
  LOG="$TEST_DIR/calls.log"
  export LOG
  # A copy without .git, so bin/dotfiles skips its update check (no git fetch).
  mkdir -p "$TEST_DIR/repo/bin" "$TEST_DIR/repo/lib" "$TEST_DIR/stubs"
  cp "$REPO_ROOT/bin/dotfiles" "$REPO_ROOT/bin/dotfiles-contribute" "$TEST_DIR/repo/bin/"
  cp "$REPO_ROOT/lib/colors.sh" "$TEST_DIR/repo/lib/"
  [ ! -f "$REPO_ROOT/lib/confirm.sh" ] || cp "$REPO_ROOT/lib/confirm.sh" "$TEST_DIR/repo/lib/"
  for tool in chezmoi agentbrew; do
    printf '#!/bin/bash\necho "%s $*" >> "$LOG"\n' "$tool" > "$TEST_DIR/stubs/$tool"
    chmod +x "$TEST_DIR/stubs/$tool"
  done
  printf '#!/bin/bash\necho "dotfiles-update $*" >> "$LOG"\n' > "$TEST_DIR/repo/bin/dotfiles-update"
  export PATH="$TEST_DIR/stubs:$PATH" DOTFILES_AGENTBREW_BIN="$TEST_DIR/stubs/agentbrew"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "contribute without a terminal and without --yes refuses and opens no PR" {
  run bash "$TEST_DIR/repo/bin/dotfiles" contribute --draft < /dev/null
  [ "$status" -eq 2 ]
  [[ "$output" == *"public pull request"*"--yes"* ]] || { echo "$output"; return 1; }
  [ ! -e "$LOG" ] || { cat "$LOG"; return 1; }
}

@test "contribute --yes opens the PR and passes the other flags through, without --yes" {
  run bash "$TEST_DIR/repo/bin/dotfiles" contribute --yes --draft < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(cat "$LOG")" = "agentbrew contribute --draft" ]
}

@test "contribute --dry-run and --help need no yes" {
  run bash "$TEST_DIR/repo/bin/dotfiles" contribute --dry-run < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(cat "$LOG")" = "agentbrew contribute --dry-run" ]
  run bash "$TEST_DIR/repo/bin/dotfiles-contribute" --help < /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"--yes"* ]]
}

@test "init without a terminal and without --yes refuses and runs no chezmoi" {
  run bash "$TEST_DIR/repo/bin/dotfiles" init < /dev/null
  [ "$status" -eq 2 ]
  [[ "$output" == *"--yes"* ]] || { echo "$output"; return 1; }
  [ ! -e "$LOG" ] || { cat "$LOG"; return 1; }
}

@test "init --yes runs chezmoi init --apply without --yes" {
  run bash "$TEST_DIR/repo/bin/dotfiles" init --yes < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(cat "$LOG")" = "chezmoi init --source $TEST_DIR/repo --apply" ]
}

# on_tty <answer> <cmd>...: run cmd with a pty as its terminal; answer the
# first "[y/N]" the pty shows. Exit 99 when no prompt reached the terminal.
on_tty() {
  ANSWER="$1" python3 - "${@:2}" <<'PY'
import os, pty, select, signal, sys, time
pid, fd = pty.fork()
if pid == 0:
    os.execvp(sys.argv[1], sys.argv[1:])
buf, sent, end = b"", False, time.time() + 15
while time.time() < end:
    if select.select([fd], [], [], 0.2)[0]:
        try:
            data = os.read(fd, 1024)
        except OSError:
            break
        if not data:
            break
        buf += data
        if not sent and b"[y/N]" in buf:
            os.write(fd, os.environ["ANSWER"].encode() + b"\n")
            sent = True
    elif os.waitpid(pid, os.WNOHANG)[0]:
        break
else:
    os.kill(pid, signal.SIGKILL)
_, status = os.waitpid(pid, 0)
sys.stdout.write(buf.decode(errors="replace"))
sys.exit(os.waitstatus_to_exitcode(status) if sent else 99)
PY
}

@test "at a terminal with its output sent to a file, the prompt shows on the terminal and y goes through" {
  run on_tty y bash -c 'exec >"$1" 2>&1; source "$2"; confirm_yes 0 "changes a test thing"; echo AGREED' _ "$TEST_DIR/out" "$REPO_ROOT/lib/confirm.sh"
  [ "$status" -eq 0 ] || { echo "status $status: $output"; cat "$TEST_DIR/out"; return 1; }
  [[ "$output" == *"changes a test thing"*"[y/N]"* ]]
  grep -qx AGREED "$TEST_DIR/out"
}

@test "at a terminal, n stops the command and nothing after the gate runs" {
  run on_tty n bash -c 'exec >"$1" 2>&1; source "$2"; confirm_yes 0 "changes a test thing"; echo AGREED' _ "$TEST_DIR/out" "$REPO_ROOT/lib/confirm.sh"
  [ "$status" -eq 1 ] || { echo "status $status: $output"; cat "$TEST_DIR/out"; return 1; }
  ! grep -q AGREED "$TEST_DIR/out"
}
