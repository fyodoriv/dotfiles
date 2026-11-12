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
spec = importlib.util.spec_from_file_location("unmatched_relationships", "docs/plans/test-unmatched-relationships.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class UnmatchedControls(unittest.TestCase):
    def test_each_source_anchor_and_candidate_identity_is_required(self):
        cache = {}
        original = module.git
        def cached(*args):
            if args not in cache:
                cache[args] = original(*args)
            return cache[args]
        with patch.object(module, "git", side_effect=cached):
            expected = module.generate()
            revision = expected["candidate_revision"]
            for _path, (_role, anchors) in module.CLAIMS.items():
                for file, number, _text in anchors:
                    args = ("show", f"{revision}:{file}")
                    original_bytes = cache[args]
                    lines = original_bytes.decode().splitlines(keepends=True)
                    lines[number - 1] = "planted\n"
                    cache[args] = "".join(lines).encode()
                    with self.assertRaises((ValueError, KeyError)): module.generate()
                    cache[args] = original_bytes
            args = ("show", f"{module.PIN}:docs/plans/test-source-references.json")
            original_bytes = cache[args]
            refs = json.loads(original_bytes)
            next(row for row in refs["records"] if row["path"] in module.CLAIMS)["blob"] = "0" * 40
            cache[args] = json.dumps(refs).encode()
            with self.assertRaises(ValueError): module.generate()

    def test_altered_relationships_and_identities_are_rejected(self):
        expected = module.generate()
        declared = next(i for i, row in enumerate(expected["records"]) if row["anchors"])
        unresolved = next(i for i, row in enumerate(expected["records"]) if row["role"] == "unresolved")
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "receipt.json"
            with patch.object(module, "OUTPUT", path), patch.object(sys, "argv", ["test-unmatched-relationships.py", "--check"]):
                path.write_text(json.dumps(expected))
                module.main()
                for mutation in ("missing", "blob", "mode", "anchor", "role", "unresolved"):
                    value = copy.deepcopy(expected)
                    if mutation == "missing": value["records"].pop()
                    elif mutation in ("blob", "mode"): value["records"][declared][mutation] = "planted"
                    elif mutation == "anchor": value["records"][declared]["anchors"][0]["line"] += 1
                    elif mutation == "role": value["records"][declared]["role"] = "unresolved"
                    else: value["records"][unresolved]["role"] = "invocation"
                    path.write_text(json.dumps(value))
                    with self.assertRaises(SystemExit): module.main()

if __name__ == "__main__":
    unittest.main()
