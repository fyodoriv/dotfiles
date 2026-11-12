import copy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path.cwd() / "docs/plans"))
spec = importlib.util.spec_from_file_location("test_cargo_targets", "docs/plans/test-cargo-targets.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class TargetControls(unittest.TestCase):
    def test_changed_fixture_evidence_is_rejected(self):
        expected = module.generate()
        changes = []
        for mutation in ("missing", "kind", "blob", "manifest", "anchor"):
            value = copy.deepcopy(expected)
            if mutation == "missing": value["records"].pop()
            elif mutation == "kind": value["records"][0]["kind"] = "test_module"
            elif mutation == "blob": value["records"][0]["blob"] = "0" * 40
            elif mutation == "manifest": value["manifests"][0]["blob"] = "0" * 40
            else: value["module_anchor"]["lines"] = [1, 2]
            changes.append(value)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "receipt.json"
            with patch.object(module, "OUTPUT", path), patch.object(sys, "argv", ["test-cargo-targets.py", "--check"]):
                path.write_text(json.dumps(expected))
                module.main()
                for value in changes:
                    path.write_text(json.dumps(value))
                    with self.assertRaises(SystemExit): module.main()

if __name__ == "__main__":
    unittest.main()
