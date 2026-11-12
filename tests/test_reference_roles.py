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
spec = importlib.util.spec_from_file_location("test_reference_roles", "docs/plans/test-reference-roles.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class RoleControls(unittest.TestCase):
    def test_changed_declaration_or_unresolved_status_is_rejected(self):
        expected = module.generate()
        declared = next(i for i, row in enumerate(expected["records"]) if row["anchor"])
        unresolved = next(i for i, row in enumerate(expected["records"]) if not row["anchor"])
        changes = []
        for mutation in ("missing", "role", "anchor", "unresolved", "count"):
            value = copy.deepcopy(expected)
            if mutation == "missing": value["records"].pop()
            elif mutation == "role": value["records"][declared]["role"] = "source"
            elif mutation == "anchor": value["records"][declared]["anchor"]["line"] += 1
            elif mutation == "unresolved": value["records"][unresolved]["role"] = "invocation"
            else: value["declared_count"] += 1
            changes.append(value)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "receipt.json"
            with patch.object(module, "OUTPUT", path), patch.object(sys, "argv", ["test-reference-roles.py", "--check"]):
                path.write_text(json.dumps(expected))
                module.main()
                for value in changes:
                    path.write_text(json.dumps(value))
                    with self.assertRaises(SystemExit): module.main()

if __name__ == "__main__":
    unittest.main()
