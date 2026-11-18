"""Scratch-only control. Every worker also has its own short self-stop."""
import json
import os
import re
import shutil
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


def run_case(name, folder, run_limit=None):
    start = time.monotonic()
    deadline = None
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
                if run_limit is not None:
                    time.sleep(max(0, start + run_limit - time.monotonic()))
                    deadline = time.monotonic()
                    publish_record(folder / "first-signal", {"time": deadline})
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
            result = {"case": name, "status": status, "active_after_exit": len(active_group_workers(process.pid))}
            if run_limit is not None:
                result.update(start=start, deadline=deadline, drained=time.monotonic(),
                              slot=os.environ.get("HEAVY_RUN_SLOT"))
            return result
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


def publish_record(path, record):
    temp = path.with_suffix(".new")
    temp.write_text(json.dumps(record))
    temp.replace(path)


def queue_worker(mode, root):
    if mode == "held":
        publish_record(root / "holder", {"start": time.monotonic(), "slot": os.environ["HEAVY_RUN_SLOT"]})
        return 0 if wait_for((root / "release-first").exists, 8) else 1
    if mode == "timed":
        folder = root / "group"
        folder.mkdir()
        publish_record(root / "started", {"start": time.monotonic(), "pid": os.getpid()})
        limit = float(os.environ.get("FIXTURE_DEADLINE_SECONDS", "1"))
        outcome = run_case("child-resistant", folder, run_limit=limit)
        publish_record(root / "timer", outcome)
        return outcome["status"]
    publish_record(root / "successor", {"start": time.monotonic(), "slot": os.environ["HEAVY_RUN_SLOT"]})
    return 0


def run_queue_control():
    with tempfile.TemporaryDirectory(prefix="deadline-slot-fixture-") as scratch:
        root = Path(scratch)
        runtime = root / "queue-state"
        environment = dict(os.environ, HEAVY_RUN_DIR=str(runtime), HEAVY_RUN_SLOTS="1",
                           HEAVY_RUN_PROJECT_SLOTS="1", HEAVY_RUN_RAMP="0", HEAVY_RUN_PAUSE_APPS="")
        started = []
        def enqueue(mode):
            process = subprocess.Popen(
                ["./bin/heavy-run", sys.executable, __file__, "queue-worker", mode, str(root)],
                env=environment, stdin=subprocess.DEVNULL,
            )
            started.append(process)
            return process

        def ticket_count():
            tickets = runtime / "queue"
            if not tickets.exists():
                return 0
            return sum(bool(re.fullmatch(r"\d+-[1-9]\d*", name.name)) and
                       not name.name.startswith("0000000000-") for name in tickets.iterdir())

        try:
            first = enqueue("held")
            if not wait_for((root / "holder").exists, 4):
                raise RuntimeError("first slot was not observed")
            offered = time.monotonic()
            timer = enqueue("timed")
            if not wait_for(lambda: ticket_count() == 1, 4):
                raise RuntimeError("deadline ticket did not wait")
            successor = enqueue("successor")
            if not wait_for(lambda: ticket_count() == 2, 4):
                raise RuntimeError("successor ticket did not wait")
            time.sleep(max(0, offered + 1.4 - time.monotonic()))
            if (root / "timer").exists() or (root / "successor").exists():
                raise RuntimeError("registered waiter started before release")
            (root / "release-first").touch()
            statuses = [process.wait(timeout=12) for process in (first, timer, successor)]
            holder, deadline, next_job = (
                json.loads((root / name).read_text()) for name in ("holder", "timer", "successor")
            )
            result = {
                "queue_wait_seconds": round(deadline["start"] - offered, 3),
                "run_until_deadline_seconds": round(deadline["deadline"] - deadline["start"], 3),
                "successor_after_teardown": next_job["start"] >= deadline["drained"],
                "active_group_workers_after_exit": deadline["active_after_exit"],
                "same_slot": holder["slot"] == deadline["slot"] == next_job["slot"],
                "statuses": statuses,
            }
            print(json.dumps(result), flush=True)
        finally:
            (root / "release-first").touch()
            for process in started:
                process.wait(timeout=15)
    return int(not (statuses == [0, 137, 0] and result["queue_wait_seconds"] > 1
                   and result["run_until_deadline_seconds"] >= 0.99
                   and result["successor_after_teardown"] and result["same_slot"]
                   and result["active_group_workers_after_exit"] == 0))


def controller_stopped(pid):
    sample = subprocess.run(["ps", "-o", "stat=", "-p", str(pid)], capture_output=True,
                            text=True, timeout=2, check=False)
    return sample.returncode == 0 and sample.stdout.strip().startswith(("T", "t"))


def run_pause_control():
    with tempfile.TemporaryDirectory(prefix="deadline-pause-fixture-") as scratch:
        root = Path(scratch)
        state = root / "heavyrun"
        fixture_name = "dlpa" + str(os.getpid())
        fixture_binary = root / fixture_name
        shutil.copy2("/bin/sleep", fixture_binary)
        environment = dict(os.environ, HEAVY_RUN_DIR=str(state), HEAVY_RUN_SLOTS="1",
                           HEAVY_RUN_RAMP="0", HEAVY_RUN_PAUSE_APPS=fixture_name,
                           FIXTURE_DEADLINE_SECONDS="3")
        with subprocess.Popen(
            ["./bin/heavy-run", sys.executable, __file__, "queue-worker", "timed", str(root)],
            env=environment,
        ) as running:
            marker = root / "started"
            if not wait_for(marker.exists, 4):
                raise RuntimeError("controller did not begin")
            owned = json.loads(marker.read_text())
            with subprocess.Popen([fixture_binary, "12"], start_new_session=True) as pauser:
                try:
                    mark = state / "slots" / "s1.paused"
                    if not wait_for(lambda: mark.exists() and controller_stopped(owned["pid"]), 2.8):
                        raise RuntimeError("scheduler did not stop its controller")
                    stopped_at = time.monotonic() - owned["start"]
                    time.sleep(max(0, owned["start"] + 3.45 - time.monotonic()))
                    paused_at_limit = controller_stopped(owned["pid"]) and mark.exists()
                    signal_sent = (root / "group" / "first-signal").exists()
                finally:
                    if pauser.poll() is None:
                        pauser.terminate()
                    pauser.wait(timeout=3)
            status = running.wait(timeout=14)
            result = json.loads((root / "timer").read_text())
            report = {
                "paused_before_deadline_seconds": round(stopped_at, 3),
                "stopped_past_limit": paused_at_limit,
                "signal_sent_while_paused": signal_sent,
                "first_signal_after_run_seconds": round(result["deadline"] - result["start"], 3),
                "active_workers_after_resume": result["active_after_exit"],
                "status": status,
            }
            print(json.dumps(report), flush=True)
    return int(not (stopped_at < 3 and paused_at_limit and not signal_sent
                   and report["first_signal_after_run_seconds"] > 3.25
                   and report["active_workers_after_resume"] == 0 and status == 137))


if __name__ == "__main__":
    if len(sys.argv) == 4:
        if sys.argv[1] == "supervise":
            sys.exit(supervise(sys.argv[2], Path(sys.argv[3])))
        if sys.argv[1] == "queue-worker":
            sys.exit(queue_worker(sys.argv[2], Path(sys.argv[3])))
    if len(sys.argv) == 3:
        sys.exit(worker(sys.argv[1], Path(sys.argv[2])))
    sys.exit(run_pause_control())
