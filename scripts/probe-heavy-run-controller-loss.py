import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time


def wait_for(condition, seconds):
    limit = time.monotonic() + seconds
    while time.monotonic() < limit:
        if condition():
            return
        time.sleep(0.03)
    raise RuntimeError("timed out waiting for fixture state")


def publish(path, value):
    temporary = path.with_suffix(".new")
    temporary.write_text(json.dumps(value))
    temporary.replace(path)


def worker(folder):
    publish(folder / "ready", {
        "parent": os.getppid(),
        "slot": os.environ["HEAVY_RUN_SLOT"],
    })
    limit = time.monotonic() + 15
    while time.monotonic() < limit:
        if (folder / "release").exists():
            (folder / "done").touch()
            return
        if (folder / "successor").exists():
            (folder / "activity-after-successor").touch()
        time.sleep(0.03)
    (folder / "done").touch()
    raise RuntimeError("fixture worker did not receive a release")


def successor(folder):
    publish(folder / "successor", {
        "slot": os.environ["HEAVY_RUN_SLOT"],
        "worker_done": (folder / "done").exists(),
    })


def run_case(folder, controller_lost):
    queue = folder / "queue-state"
    environment = dict(os.environ, HEAVY_RUN_DIR=str(queue), HEAVY_RUN_SLOTS="1",
                       HEAVY_RUN_PROJECT_SLOTS="1", HEAVY_RUN_RAMP="0", HEAVY_RUN_PAUSE_APPS="")
    for name in ("HEAVY_RUN_HELD", "HEAVY_RUN_SLOT"):
        environment.pop(name, None)
    processes = []

    def start(mode):
        process = subprocess.Popen(
            ["./bin/heavy-run", sys.executable, __file__, mode, str(folder)],
            stdin=subprocess.DEVNULL, env=environment,
        )
        processes.append(process)
        return process

    def has_waiter():
        tickets = queue / "queue"
        return tickets.is_dir() and any(
            re.fullmatch(r"[0-9]+-[1-9][0-9]*", row.name)
            and not row.name.startswith("0000000000-") for row in tickets.iterdir()
        )

    try:
        controller = start("worker")
        wait_for((folder / "ready").exists, 4)
        ready = json.loads((folder / "ready").read_text())
        if ready["parent"] != controller.pid or controller.poll() is not None:
            raise RuntimeError("cannot verify the fixture worker's exact controller")
        next_run = start("successor")
        wait_for(has_waiter, 4)
        if (folder / "successor").exists():
            raise RuntimeError("successor started before controller action")

        if controller_lost:
            controller.kill()
            assert controller.wait(timeout=4) == -signal.SIGKILL
            wait_for((folder / "activity-after-successor").exists, 4)
            assert not (folder / "done").exists()
        else:
            time.sleep(0.6)
            assert not (folder / "successor").exists()

        (folder / "release").touch()
        wait_for((folder / "done").exists, 4)
        assert next_run.wait(timeout=4) == 0
        if not controller_lost:
            assert controller.wait(timeout=4) == 0
        record = json.loads((folder / "successor").read_text())
        assert record["slot"] == ready["slot"]
        assert record["worker_done"] is (not controller_lost)
        return {"controller_lost": controller_lost,
                "successor_saw_worker_done": record["worker_done"],
                "worker_active_after_successor": (folder / "activity-after-successor").exists(),
                "fixture_worker_finished": (folder / "done").exists(),
                "same_slot": record["slot"] == ready["slot"]}
    finally:
        (folder / "release").touch()
        for process in processes:
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=3)


if __name__ == "__main__":
    if len(sys.argv) == 3:
        action, directory = sys.argv[1:]
        {"worker": worker, "successor": successor}[action](Path(directory))
    else:
        with tempfile.TemporaryDirectory(prefix="heavy-run-controller-loss-") as scratch:
            root = Path(scratch)
            rows = []
            for label, controller_lost in (("ordinary", False), ("loss", True)):
                folder = root / label
                folder.mkdir()
                rows.append(run_case(folder, controller_lost))
            print(json.dumps(rows), flush=True)
