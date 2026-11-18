"""Scratch-only control. Every worker also has its own short self-stop."""
import json
import os
from pathlib import Path
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


def active_group_workers(group):
    snapshot = subprocess.check_output(["ps", "-eo", "pid=,pgid=,stat="], text=True, timeout=2)
    workers = []
    for line in snapshot.splitlines():
        columns = line.split()
        if len(columns) < 3:
            continue
        pid, owner, status = columns[:3]
        if owner == str(group) and pid != str(group) and not status.startswith("Z"):
            workers.append(pid)
    return workers


def supervise(mode, folder):
    signal_disposition(True)
    with subprocess.Popen([sys.executable, __file__, mode, str(folder)]) as child:
        status = child.wait(timeout=11)
        pending = folder / "exit-pending"
        pending.write_text(str(status))
        pending.replace(folder / "primary-exit")

    # The process group stays owned until the detecting parent releases it.
    until = time.monotonic() + 13
    while not (folder / "release").exists() and time.monotonic() < until:
        time.sleep(0.05)
    return 0


def stop_owned_group(process, how):
    # Poll reaps a dead sentinel. No other code reaps this child before we
    # signal, so its PID cannot be reused between a live poll and killpg.
    if process.poll() is not None or os.getpgid(process.pid) != process.pid:
        raise RuntimeError("could not verify the fixture group")
    os.killpg(process.pid, how)


def wait_for(test, seconds):
    until = time.monotonic() + seconds
    while time.monotonic() < until:
        if test():
            return True
        time.sleep(0.05)
    return test()


def run_case(name, folder):
    with subprocess.Popen(
        [sys.executable, __file__, "supervise", name, str(folder)],
        start_new_session=True,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ) as process:
        try:
            if name == "normal":
                if not wait_for((folder / "primary-exit").exists, 3):
                    raise RuntimeError("short command produced no exit")
                status = int((folder / "primary-exit").read_text())
                (folder / "release").touch()
            else:
                leaves = ["parent", "child"] if name in ("default", "child-resistant") else ["parent"]
                published = lambda: all((folder / leaf).exists() for leaf in leaves)
                if not wait_for(published, 3):
                    raise RuntimeError("fixture workers did not publish")
                recorded = [json.loads((folder / leaf).read_text()) for leaf in leaves]
                if any(leaf["group"] != process.pid for leaf in recorded):
                    raise RuntimeError("fixture worker used a different group")
                if len(active_group_workers(process.pid)) != len(leaves):
                    raise RuntimeError("fixture worker inventory was incomplete")
                stop_owned_group(process, signal.SIGTERM)
                drained = wait_for(lambda: not active_group_workers(process.pid), 1)
                status = 124 if drained else 137
                if drained:
                    (folder / "release").touch()
                else:
                    stop_owned_group(process, signal.SIGKILL)
                    if not wait_for(lambda: not active_group_workers(process.pid), 2):
                        raise RuntimeError("owned workers did not drain after escalation")
            result = process.wait(timeout=3)
            if result != (-9 if status == 137 else 0):
                raise RuntimeError("unexpected supervisor exit")
            return {"case": name, "status": status, "active_after_exit": len(active_group_workers(process.pid))}
        finally:
            if process.poll() is None:
                stop_owned_group(process, signal.SIGKILL)
                process.wait(timeout=3)


def run_controls():
    with tempfile.TemporaryDirectory(prefix="owned-deadline-control-") as run:
        root = Path(run)
        with subprocess.Popen(
            [sys.executable, "-c", "import time; time.sleep(15)"],
            start_new_session=True,
        ) as bystander:
            try:
                results = []
                for name in ["normal", "default", "resistant", "child-resistant"]:
                    folder = root / name
                    folder.mkdir()
                    results.append(run_case(name, folder))
                untouched = bystander.poll() is None
                print(json.dumps({"cases": results, "separate_group_alive": untouched}), flush=True)
            finally:
                if bystander.poll() is None:
                    bystander.terminate()
                bystander.wait(timeout=3)
    return int(not untouched or any(
        row["status"] != expected or row["active_after_exit"]
        for row, expected in zip(results, (7, 124, 137, 137))
    ))


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "supervise":
        sys.exit(supervise(sys.argv[2], Path(sys.argv[3])))
    if len(sys.argv) == 3:
        sys.exit(worker(sys.argv[1], Path(sys.argv[2])))
    sys.exit(run_controls())
