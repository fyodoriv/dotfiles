#!/usr/bin/env python3
"""Draft isolated interoperability controls. Root owns heavy-run execution."""
import argparse
import fcntl
import hashlib
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time
import unittest


def wait_for(predicate, seconds=8):
    until = time.monotonic() + seconds
    while time.monotonic() < until:
        if predicate():
            return
        time.sleep(0.04)
    raise AssertionError("isolated queue handshake timed out")


class Interoperability(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="heavy-project-a-")
        self.root = Path(self.scratch.name)
        self.state = self.root / "state"
        (self.state / "slots").mkdir(parents=True)
        (self.state / "queue").mkdir()
        (self.root / "home").mkdir()
        self.children = []
        self.starts = {}
        self.files = []
        self.holders = []
        self.number = 0
        self.env = dict(os.environ)
        for key in list(self.env):
            if key.startswith("HEAVY_RUN_"):
                del self.env[key]
        self.env.update(
            HOME=str(self.root / "home"),
            XDG_CONFIG_HOME=str(self.root / "home" / ".config"),
            HEAVY_RUN_DIR=str(self.state), HEAVY_RUN_SLOTS="3",
            HEAVY_RUN_PROJECT_SLOTS="1", HEAVY_RUN_RAMP="0",
            HEAVY_RUN_MAX_LOAD="0", HEAVY_RUN_PROBE="true",
            HEAVY_RUN_PAUSE_APPS="", HEAVY_RUN_MEMORY_GUARD="0",
            HEAVY_RUN_KEEP_ORPHAN="1",
        )

    def tearDown(self):
        for handle in self.holders:
            handle.close()
        for child in self.children:
            if child.poll() is None:
                for sig in (signal.SIGCONT, signal.SIGTERM):
                    try:
                        os.killpg(child.pid, sig)
                    except ProcessLookupError:
                        pass
        for child in self.children:
            try:
                child.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGKILL)
                child.wait(timeout=3)
        for handle in self.files:
            handle.close()
        self.scratch.cleanup()

    def launch(self, script, project):
        self.number += 1
        started = self.root / ("started-" + str(self.number))
        release = self.root / ("release-" + str(self.number))
        program = (
            "from pathlib import Path; import os,sys,time; "
            "Path(sys.argv[1]).write_text(str(os.getpid())); end=time.monotonic()+15\n"
            "while not Path(sys.argv[2]).exists() and time.monotonic()<end: time.sleep(.04)"
        )
        program = "exec(" + repr(program) + ")"
        assert "\n" not in program and "\r" not in program
        log = (self.root / ("child-" + str(self.number) + ".log")).open("wb")
        self.files.append(log)
        env = dict(self.env, HEAVY_RUN_PROJECT=project)
        child = subprocess.Popen(
            ["/bin/bash", str(script), sys.executable, "-c", program,
             str(started), str(release)], cwd=self.root, env=env,
            stdout=log, stderr=subprocess.STDOUT, start_new_session=True,
        )
        self.children.append(child)
        self.starts[child.pid] = started
        return child, started, release

    def live_tickets(self):
        return [p for p in (self.state / "queue").glob("*-*")
                if p.name != "0000000000-0" and p.name.replace("-", "").isdigit()]

    def queued(self, child):
        def ready():
            tickets = [p for p in self.live_tickets() if p.name.endswith("-" + str(child.pid))]
            if len(tickets) != 1:
                return False
            path = tickets[0]
            try:
                with path.open() as handle:
                    try:
                        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    except BlockingIOError:
                        pass
                    else:
                        return False
                    lines = handle.read().splitlines()
                why = Path(str(path) + ".why")
                reason = why.read_text().strip() if why.exists() else next((s[5:] for s in lines if s.startswith("wait=")), "")
                return bool(reason) and reason != "starting" and not Path(str(path) + ".grant").exists()
            except FileNotFoundError:
                return False
        wait_for(lambda: ready() or self.starts[child.pid].exists() or child.poll() is not None)
        self.assertIsNone(child.poll(), "waiter exited before queue observation")
        self.assertFalse(self.starts[child.pid].exists(), "wrong same-project admission before queue observation")
        self.assertTrue(ready(), "candidate has no held, nonstarting own-ticket handshake")

    def ready_owner(self, run):
        result = []
        def ready():
            if not run[1].exists():
                return False
            pid = run[1].read_text().strip()
            if not pid.isdigit():
                return False
            for owner in (self.state / "slots").glob("s*.owner"):
                lines = owner.read_text().splitlines()
                if len(lines) >= 3 and re.search(r"\bpid=" + pid + r"\b", lines[0]) and lines[1].startswith("project=") and re.fullmatch(r"start=\d+\.\d+", lines[2]):
                    result[:] = lines
                    return True
            return False
        wait_for(ready)
        return result

    def blocked(self, started, duration=1.2):
        until = time.monotonic() + duration
        while time.monotonic() < until:
            self.assertFalse(started.exists(), "wrong same-project admission")
            time.sleep(.04)

    def release(self, run):
        run[2].touch()
        self.assertEqual(run[0].wait(timeout=8), 0)

    def hold(self, relative, text, shared=False):
        path = self.state / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        handle = path.open("w+")
        fcntl.flock(handle, fcntl.LOCK_SH if shared else fcntl.LOCK_EX)
        handle.write(text)
        handle.flush()
        self.holders.append(handle)
        return handle

    def owner(self, project, typed=False, slot="s1"):
        self.hold("lock", "", shared=True)
        handle = self.hold("slots/" + slot, "")
        field = "project_id=sha256:" + hashlib.sha256(project.encode()).hexdigest() if typed else "project=" + project
        (self.state / ("slots/" + slot + ".owner")).write_text(
            "synthetic owner\n" + field + "\nstart=1.000\nreader=project-id-v1\n"
        )
        return handle

    def test_a_counts_429_owner_and_other_project_runs(self):
        self.owner("alpha", slot="1")
        a = self.launch(CANDIDATE, "alpha")
        self.queued(a[0])
        b = self.launch(CANDIDATE, "beta")
        wait_for(b[1].exists)
        self.blocked(a[1])
        self.release(b)

    def mixed_writer_reader(self, reader):
        a = self.launch(CANDIDATE, "alpha")
        self.ready_owner(a)
        old = self.launch(reader, "alpha")
        self.queued(old[0])
        self.blocked(old[1])
        self.release(a)
        wait_for(old[1].exists)
        self.release(old)

    def test_429_reader_counts_a_through_gate(self):
        self.mixed_writer_reader(LEGACY429)

    def test_430_reader_counts_a(self):
        self.mixed_writer_reader(LEGACY430)

    def test_a_owner_retains_raw_project_start_and_marker(self):
        a = self.launch(CANDIDATE, "alpha")
        lines = self.ready_owner(a)
        self.assertEqual(lines[1], "project=alpha")
        self.assertRegex(lines[2], r"^start=\d+\.\d+$")
        self.assertIn("reader=project-id-v1", lines)
        self.release(a)

    def test_a_ticket_retains_positional_raw_project_and_marker(self):
        self.owner("alpha")
        a = self.launch(CANDIDATE, "alpha")
        self.queued(a[0])
        ticket = self.live_tickets()[0]
        lines = ticket.read_text().splitlines()
        self.assertEqual(lines[2], "project=alpha")
        self.assertIn("kind=v2", lines)
        self.assertIn("reader=project-id-v1", lines)
        self.blocked(a[1])

    def test_a_counts_typed_future_owner(self):
        self.owner("alpha", typed=True)
        a = self.launch(CANDIDATE, "alpha")
        self.queued(a[0])
        b = self.launch(CANDIDATE, "beta")
        wait_for(b[1].exists)
        self.blocked(a[1])
        self.release(b)

    def test_a_skips_capped_typed_ticket(self):
        self.owner("alpha")
        digest = hashlib.sha256(b"alpha").hexdigest()
        self.hold("queue/0000000001-999999", "synthetic ticket\nwait=\nproject_id=sha256:" + digest + "\nkind=v2\nexclusive=0\nreader=project-id-v1\n")
        b = self.launch(CANDIDATE, "beta")
        wait_for(b[1].exists)
        self.assertFalse((self.state / "queue/0000000001-999999.grant").exists(), "capped synthetic ticket received grant")
        self.release(b)

    def test_a_counts_typed_pending_grant(self):
        digest = hashlib.sha256(b"alpha").hexdigest()
        self.hold("queue/0000000001-999999", "synthetic ticket\nwait=\nproject_id=sha256:" + digest + "\nkind=v2\nexclusive=0\nreader=project-id-v1\n")
        (self.state / "queue/0000000001-999999.grant").write_text("s1\n")
        a = self.launch(CANDIDATE, "alpha")
        self.queued(a[0])
        b = self.launch(CANDIDATE, "beta")
        wait_for(b[1].exists)
        self.blocked(a[1])
        self.release(b)

    def test_raw_digest_looking_project_is_still_raw(self):
        project = "sha256:" + "a" * 64
        self.owner(project)
        a = self.launch(CANDIDATE, project)
        self.queued(a[0])
        self.blocked(a[1])

    def test_invalid_typed_owner_never_grants(self):
        self.owner("alpha", typed=True)
        owner = self.state / "slots/s1.owner"
        owner.write_text("synthetic owner\nproject_id=sha256:invalid\nstart=1.000\nreader=project-id-v1\n")
        a = self.launch(CANDIDATE, "alpha")
        self.queued(a[0])
        self.blocked(a[1])


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--legacy-429", type=Path, required=True)
    parser.add_argument("--legacy-430", type=Path, required=True)
    args, remaining = parser.parse_known_args()
    CANDIDATE, LEGACY429, LEGACY430 = (p.resolve(strict=True) for p in (args.candidate, args.legacy_429, args.legacy_430))
    unittest.main(argv=[sys.argv[0], *remaining])
