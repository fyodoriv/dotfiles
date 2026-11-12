import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path.cwd() / "docs/plans"))
spec = importlib.util.spec_from_file_location("compiler_fixture_targets", "docs/plans/compiler-fixture-targets.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class CompilerFixtureControls(unittest.TestCase):
    def test_manifest_mutations_are_rejected(self):
        expected = module.generate()
        revision = expected["candidate_revision"]
        raw = subprocess.check_output(["git", "show", f"{revision}:{module.ROOT}/Cargo.toml"])
        manifest = tomllib.loads(raw.decode())
        self.assertTrue(module.declarations(manifest))
        for mutation in ("missing", "path", "name", "autotests", "duplicate", "kind"):
            value = copy.deepcopy(manifest)
            if mutation == "missing": value["test"].pop()
            elif mutation == "path": value["test"][0]["path"] = "other.rs"
            elif mutation == "name": value["test"][0]["name"] = "other"
            elif mutation == "autotests": value["package"]["autotests"] = True
            elif mutation == "duplicate": value["test"][1] = copy.deepcopy(value["test"][0])
            else: value["bench"] = value.pop("test")
            self.assertFalse(module.declarations(value))

    def test_receipt_mutations_are_rejected(self):
        expected = module.generate()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "receipt.json"
            with patch.object(module, "OUTPUT", path), patch.object(sys, "argv", ["compiler-fixture-targets.py", "--check"]):
                path.write_text(json.dumps(expected))
                module.main()
                for field in ("path", "mode", "blob", "target"):
                    value = copy.deepcopy(expected)
                    value["records"][0][field] = "planted"
                    path.write_text(json.dumps(value))
                    with self.assertRaises(SystemExit): module.main()

if __name__ == "__main__":
    unittest.main()
