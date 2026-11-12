import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path.cwd() / "docs/plans"))
spec = importlib.util.spec_from_file_location("hook_source_edge", "docs/plans/hook-source-edge.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class HookSourceEdgeControls(unittest.TestCase):
    def test_each_source_anchor_is_required(self):
        receipt = module.generate()
        lines = subprocess.check_output(["git", "show", f"{receipt['candidate_revision']}:{module.LAUNCHER}"]).decode().splitlines()
        self.assertTrue(module.anchors_match(lines))
        for line in module.ANCHORS:
            changed = list(lines)
            changed[line - 1] = "planted"
            self.assertFalse(module.anchors_match(changed))
        self.assertFalse(module.anchors_match([]))

    def test_changed_identity_or_relationship_is_rejected(self):
        expected = module.generate()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "receipt.json"
            with patch.object(module, "OUTPUT", path), patch.object(sys, "argv", ["hook-source-edge.py", "--check"]):
                path.write_text(json.dumps(expected))
                module.main()
                for field in ("caller", "target", "anchors", "relationship"):
                    value = copy.deepcopy(expected)
                    value[field] = "planted"
                    path.write_text(json.dumps(value))
                    with self.assertRaises(SystemExit): module.main()

if __name__ == "__main__":
    unittest.main()
