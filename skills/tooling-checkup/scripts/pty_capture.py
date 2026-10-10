"""Run a command inside a pseudo-terminal and print its plain-text output.

Some CLIs (for example `claude doctor`) print nothing when stdout is not a
terminal. This gives them a terminal, waits until the output goes quiet, and
prints the text without ANSI escape codes.

Usage: python3 pty_capture.py [--timeout SECONDS] [--quiet SECONDS] -- COMMAND [ARGS...]
Exit status: the command's exit status, or 124 when it hit the timeout.
"""

import argparse
import os
import pty
import re
import select
import signal
import sys
import time

ANSI = re.compile(
    r"\x1b\[[0-9;?<>=]*[ -/]*[@-~]"  # CSI
    r"|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)"  # OSC
    r"|\x1b[@-Z\\-_]"  # two-byte escapes
)


def strip_ansi(text: str) -> str:
    text = ANSI.sub("", text)
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    return "\n".join(line.rstrip() for line in text.split("\n"))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--timeout", type=float, default=60.0, help="hard limit in seconds")
    parser.add_argument("--quiet", type=float, default=5.0, help="stop after this many seconds without output")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("give a command after --")

    pid, fd = pty.fork()
    if pid == 0:
        try:
            os.execvp(command[0], command)
        except OSError as error:
            print(f"pty_capture: cannot run {command[0]}: {error}", file=sys.stderr)
            os._exit(127)

    chunks = []
    start = last = time.monotonic()
    timed_out = False
    while True:
        now = time.monotonic()
        if now - start > args.timeout:
            timed_out = True
            break
        if chunks and now - last > args.quiet:
            break
        ready, _, _ = select.select([fd], [], [], 0.25)
        if not ready:
            continue
        try:
            data = os.read(fd, 65536)
        except OSError:  # EIO: the child closed the terminal
            break
        if not data:
            break
        chunks.append(data)
        last = time.monotonic()

    status = 124 if timed_out else 0
    try:
        finished, raw = os.waitpid(pid, os.WNOHANG)
        if finished == 0:
            os.kill(pid, signal.SIGTERM)
            _, raw = os.waitpid(pid, 0)
        if not timed_out:
            status = os.waitstatus_to_exitcode(raw)
    except ChildProcessError:
        pass
    os.close(fd)

    print(strip_ansi(b"".join(chunks).decode("utf-8", "replace")).strip())
    return status if status >= 0 else 128 - status


if __name__ == "__main__":
    sys.exit(main())
