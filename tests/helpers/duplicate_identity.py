#!/usr/bin/env python3
"""Isolated duplicate identity controls; never addresses the live queue."""
import argparse
import hashlib
import importlib.util
from pathlib import Path
import sys
import unittest

spec = importlib.util.spec_from_file_location("registered_interop", Path(__file__).with_name("heavy-run-project-interop.py"))
registered = importlib.util.module_from_spec(spec)
spec.loader.exec_module(registered)

class DuplicateIdentity(registered.Interoperability):
    def duplicate_owner(self, typed):
        self.owner("alpha", typed=typed)
        field = "project_id=sha256:" + hashlib.sha256(b"beta").hexdigest() if typed else "project=beta"
        with (self.state / "slots/s1.owner").open("a") as out:
            out.write(field + "\n")
        run = self.launch(registered.CANDIDATE, "alpha")
        self.queued(run[0])
        self.blocked(run[1])

    def duplicate_ticket(self, typed):
        self.owner("alpha")
        def field(project):
            return "project_id=sha256:" + hashlib.sha256(project.encode()).hexdigest() if typed else "project=" + project
        self.hold("queue/0000000001-999999", "synthetic ticket\nwait=\n" + field("alpha") + "\nkind=v2\nexclusive=0\nreader=project-id-v1\n" + field("beta") + "\n")
        run = self.launch(registered.CANDIDATE, "gamma")
        self.queued(run[0])
        self.assertFalse((self.state / "queue/0000000001-999999.grant").exists(), "ambiguous identity ticket received a grant")
        self.blocked(run[1])

    def test_duplicate_raw_owner(self): self.duplicate_owner(False)
    def test_duplicate_typed_owner(self): self.duplicate_owner(True)
    def test_duplicate_raw_ticket(self): self.duplicate_ticket(False)
    def test_duplicate_typed_ticket(self): self.duplicate_ticket(True)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--legacy-429", type=Path, required=True)
    parser.add_argument("--legacy-430", type=Path, required=True)
    args = parser.parse_args()
    registered.CANDIDATE, registered.LEGACY429, registered.LEGACY430 = (p.resolve(strict=True) for p in (args.candidate, args.legacy_429, args.legacy_430))
    names = ["test_duplicate_raw_owner", "test_duplicate_typed_owner", "test_duplicate_raw_ticket", "test_duplicate_typed_ticket"]
    result = unittest.TextTestRunner(verbosity=2).run(unittest.TestSuite(DuplicateIdentity(name) for name in names))
    raise SystemExit(0 if result.wasSuccessful() else 1)
