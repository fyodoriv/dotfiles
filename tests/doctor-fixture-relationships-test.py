#!/usr/bin/env python3
"""Mutation controls for the pinned fixture relationship check."""
import importlib.util
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "docs/plans"))
spec = importlib.util.spec_from_file_location("fixture_relationships", ROOT / "docs/plans/doctor-fixture-relationships.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class FixtureRelationships(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.identities, cls.sources = module.snapshot()

    def test_original(self):
        self.assertEqual(len(module.validate(self.identities, self.sources)["candidates"]), 2)

    def test_changed_identities_and_anchors_are_rejected(self):
        for path in module.CANDIDATES:
            with self.subTest(path=path):
                identities = dict(self.identities)
                identities[path] = ("100644", identities[path][1])
                with self.assertRaises(ValueError):
                    module.validate(identities, self.sources)
        for path, line in [("bin/dotfiles-doctor", 109), ("tests/doctor-json-status.bats", 50), ("bin/dotfiles-doctor", 267), ("bin/dotfiles-doctor", 797)]:
            with self.subTest(path=path):
                sources = dict(self.sources)
                lines = sources[path].splitlines()
                lines[line - 1] += " changed"
                sources[path] = "\n".join(lines)
                with self.assertRaises(ValueError):
                    module.validate(self.identities, sources)


if __name__ == "__main__":
    unittest.main()
