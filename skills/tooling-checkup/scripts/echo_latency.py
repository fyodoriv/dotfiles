"""Measure how fast a terminal program echoes typed keys.

It starts COMMAND in a pseudo-terminal, waits for it to settle, then types one
character at a time and times how long each one takes to appear in the output.
Use it to compare Claude Code with a plain shell before and after a change.

Usage:
  python3 echo_latency.py [--chars N] [--interval S] [--settle S] [--cwd DIR] -- COMMAND [ARGS...]

Example (run both, compare the two lines):
  python3 echo_latency.py --settle 1 -- zsh -f
  python3 echo_latency.py --settle 10 -- claude

Output: one line, for example
  echo-latency command="zsh -f" n=40 median_ms=6.1 p95_ms=21.4 max_ms=30.2 timeouts=0
Starting `claude` this way opens a new short-lived session. Run it from a
trusted project directory, or the folder-trust prompt takes the keys.
"""

import argparse
import fcntl
import os
import pty
import select
import shlex
import signal
import statistics
import struct
import sys
import termios
import time

# Rare letters: unlikely to appear in a redraw by chance.
KEYS = b"zqxjkvwy"


def drain(fd: int, seconds: float) -> None:
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        ready, _, _ = select.select([fd], [], [], 0.05)
        if ready:
            try:
                if not os.read(fd, 65536):
                    return
            except OSError:
                return


def percentile(values, fraction):
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, round(fraction * (len(ordered) - 1))))
    return ordered[index]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--chars", type=int, default=40)
    parser.add_argument("--interval", type=float, default=0.15, help="seconds between keys")
    parser.add_argument("--settle", type=float, default=8.0, help="seconds to wait after start")
    parser.add_argument("--timeout", type=float, default=3.0, help="seconds before a key counts as lost")
    parser.add_argument("--cwd", default=None)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("give a command after --")

    pid, fd = pty.fork()
    if pid == 0:
        if args.cwd:
            os.chdir(args.cwd)
        try:
            os.execvp(command[0], command)
        except OSError as error:
            print(f"echo_latency: cannot run {command[0]}: {error}", file=sys.stderr)
            os._exit(127)

    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
    drain(fd, args.settle)

    samples = []
    timeouts = 0
    for index in range(args.chars):
        key = KEYS[index % len(KEYS):][:1]
        os.write(fd, key)
        sent = time.monotonic()
        seen = False
        while time.monotonic() - sent < args.timeout:
            ready, _, _ = select.select([fd], [], [], 0.01)
            if not ready:
                continue
            try:
                data = os.read(fd, 65536)
            except OSError:
                data = b""
            if not data:
                break
            if key in data:
                samples.append((time.monotonic() - sent) * 1000)
                seen = True
                break
        if not seen:
            timeouts += 1
        drain(fd, args.interval)

    # Clear the typed text, then stop the program.
    try:
        os.write(fd, b"\x15")
        os.kill(pid, signal.SIGTERM)
        drain(fd, 0.3)
        if os.waitpid(pid, os.WNOHANG)[0] == 0:
            os.kill(pid, signal.SIGKILL)
            os.waitpid(pid, 0)
    except (OSError, ChildProcessError):
        pass

    label = shlex.join(command)
    if not samples:
        print(f'echo-latency command="{label}" n=0 timeouts={timeouts} error="no key echoed"')
        return 1
    print(
        f'echo-latency command="{label}" n={len(samples)}'
        f" median_ms={statistics.median(samples):.1f}"
        f" p95_ms={percentile(samples, 0.95):.1f}"
        f" max_ms={max(samples):.1f}"
        f" timeouts={timeouts}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
