"""Scratch-only control. Every worker also has its own short self-stop."""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time


def signal_disposition(resistant):
    signal.signal(signal.SIGTERM, signal.SIG_IGN if resistant else signal.SIG_DFL)


def publish(path):
    path.write_text(json.dumps({"pid": os.getpid(), "group": os.getpgrp()}))


def worker(mode, folder):
    if mode == "normal":
        return 7
    if mode in ("default", "child-resistant"):
        child_mode = "leaf-resistant" if mode == "child-resistant" else "leaf"
        subprocess.Popen(
            [sys.executable, __file__, child_mode, str(folder)],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
    signal_disposition(mode in ("resistant", "leaf-resistant"))
    publish(folder / ("child" if mode.startswith("leaf") else "parent"))
    time.sleep(10)
    return 0


def member_active(identity):
    try:
        if os.getpgid(identity["pid"]) != identity["group"]:
            return False
    except ProcessLookupError:
        return False
    probe = subprocess.run(
        ["ps", "-o", "stat=", "-p", str(identity["pid"])],
        capture_output=True, text=True, check=False, timeout=1,
    )
    status = probe.stdout.strip()
    return probe.returncode == 0 and bool(status) and not status.startswith("Z")


def run_controls():
    limit = shutil.which("gtimeout") or shutil.which("timeout")
    if not limit:
        raise SystemExit("GNU timeout is unavailable")
    version = subprocess.check_output([limit, "--version"], text=True, timeout=2).splitlines()[0]
    if "GNU coreutils" not in version:
        raise SystemExit("GNU timeout is unavailable")
    print(version, flush=True)
    with tempfile.TemporaryDirectory(prefix="deadline-control-") as owned:
        root = Path(owned)
        separate_group = subprocess.Popen(
            [sys.executable, "-c", "import time; time.sleep(15)"],
            start_new_session=True,
        )
        surviving = []
        outcomes = []
        try:
            for name, expected_status, paths in (
                ("normal", 7, ()),
                ("default", 124, ("parent", "child")),
                ("resistant", 137, ("parent",)),
                ("child-resistant", 124, ("parent", "child")),
            ):
                folder = root / name
                folder.mkdir()
                command = subprocess.Popen(
                    [limit, "--kill-after=1s", "1.5s", sys.executable, __file__, name, str(folder)],
                    stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                )
                status = command.wait(timeout=7)
                identities = [json.loads((folder / label).read_text()) for label in paths]
                if any(row["group"] != command.pid for row in identities):
                    raise RuntimeError("worker did not join the timeout's owned group")
                active = [row for row in identities if member_active(row)]
                surviving.extend(active)
                outcomes.append({
                    "case": name, "status": status, "expected": expected_status,
                    "group_members_seen": len(identities), "active_after_exit": len(active),
                })
            separate_alive = separate_group.poll() is None
            print(json.dumps({"cases": outcomes, "separate_group_alive": separate_alive}), flush=True)
            # The workers have a second self-deadline. Let them exit without signaling a reused pid.
            until = time.monotonic() + 11
            while any(member_active(identity) for identity in surviving) and time.monotonic() < until:
                time.sleep(0.1)
            if any(member_active(identity) for identity in surviving):
                raise RuntimeError("fixture worker did not self-stop")
        finally:
            if separate_group.poll() is None:
                separate_group.terminate()
            separate_group.wait(timeout=3)
    return int(not separate_alive or any(
        row["status"] != row["expected"] or row["active_after_exit"] for row in outcomes
    ))


if __name__ == "__main__":
    if len(sys.argv) == 3:
        sys.exit(worker(sys.argv[1], Path(sys.argv[2])))
    sys.exit(run_controls())
