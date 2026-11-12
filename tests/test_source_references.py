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
spec = importlib.util.spec_from_file_location("test_source_references", "docs/plans/test-source-references.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ReferenceControls(unittest.TestCase):
    def test_pinned_reference_changes_are_rejected(self):
        expected = module.generate()
        referenced = next(i for i, row in enumerate(expected["records"]) if row["references"])
        changes = []
        for mutation in ("missing", "blob", "line", "extra"):
            value = copy.deepcopy(expected)
            if mutation == "missing": value["records"].pop()
            elif mutation == "blob": value["records"][0]["blob"] = "0" * 40
            elif mutation == "line": value["records"][referenced]["references"][0]["line"] += 1
            else: value["records"].append(copy.deepcopy(value["records"][0]))
            changes.append(value)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "receipt.json"
            with patch.object(module, "OUTPUT", path), patch.object(sys, "argv", ["test-source-references.py", "--check"]):
                path.write_text(json.dumps(expected))
                module.main()
                for value in changes:
                    path.write_text(json.dumps(value))
                    with self.assertRaises(SystemExit): module.main()

if __name__ == "__main__":
    unittest.main()
