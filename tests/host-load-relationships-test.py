#!/usr/bin/env python3
"""Mutation controls for the pinned host-load source receipt."""
import importlib.util
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "docs/plans"))
spec = importlib.util.spec_from_file_location("host_load", ROOT / "docs/plans/host-load-relationships.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class HostLoadRelationships(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.identity, cls.sources = module.snapshot()

    def test_original(self):
        self.assertEqual(len(module.validate(self.identity, self.sources)["direct_sources"]), 2)

    def test_changed_identity_and_anchors_are_rejected(self):
        with self.assertRaises(ValueError):
            module.validate(("100755", self.identity[1]), self.sources)
        for path, anchors in module.ANCHORS.items():
            with self.subTest(path=path):
                sources = dict(self.sources)
                lines = sources[path].splitlines()
                lines[next(iter(anchors)) - 1] += " changed"
                sources[path] = "\n".join(lines)
                with self.assertRaises(ValueError):
                    module.validate(self.identity, sources)


if __name__ == "__main__":
    unittest.main()
