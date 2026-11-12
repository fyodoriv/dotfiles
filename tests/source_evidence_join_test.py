import importlib.util
from pathlib import Path
import sys
import unittest

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("join", Path(__file__).parents[1] / "docs/plans/source-evidence-join.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class EvidenceJoin(unittest.TestCase):
    def test_overlaps_and_stale_modes_are_preserved(self):
        candidates = [{"path": "a", "mode": "100755", "blob": "x", "reasons": ["executable-mode"]},
                      {"path": "b", "mode": "100644", "blob": "x", "reasons": ["source-suffix"]}]
        evidence = [{"receipt": "one", "revision": "r", "path": "a", "mode": "100755", "blob": "x"},
                    {"receipt": "two", "revision": "s", "path": "a", "mode": "100644", "blob": "x"},
                    {"receipt": "three", "revision": "t", "path": "other", "mode": "100644", "blob": "x"}]
        rows = module.join(candidates, evidence)
        self.assertEqual(rows[0]["status"], "exact")
        self.assertEqual([item["status"] for item in rows[0]["evidence"]], ["exact", "stale"])
        self.assertTrue(rows[0]["evidence"][1]["blob_match"])
        self.assertFalse(rows[0]["evidence"][1]["mode_match"])
        self.assertEqual(rows[1]["status"], "absent")
        self.assertEqual(rows[1]["evidence"], [])

    def test_same_path_changed_blob_is_stale(self):
        rows = module.join([{"path": "a", "mode": "100755", "blob": "x", "reasons": []}],
                           [{"receipt": "one", "revision": "r", "path": "a", "mode": "100755", "blob": "y"}])
        self.assertEqual(rows[0]["status"], "stale")
        self.assertFalse(rows[0]["evidence"][0]["blob_match"])

    def test_duplicate_candidates_or_receipt_paths_are_rejected(self):
        candidate = {"path": "a", "mode": "100755", "blob": "x", "reasons": []}
        source = {"receipt": "one", "revision": "r", "path": "a", "mode": "100755", "blob": "x"}
        with self.assertRaises(ValueError):
            module.join([candidate, candidate], [])
        with self.assertRaises(ValueError):
            module.join([candidate], [source, source])

    def test_receipt_source_identities_and_schema_fail_closed(self):
        name = "docs/plans/ci-source-inventory.json"
        row = {"path": "a", "mode": "100755", "blob": "x", "first_line": "#!"}
        receipt = {"format": 1, "revision": "a" * 40, "files": [row], "references": []}
        source_tree = {"a": {"mode": "100755", "blob": "x"}}
        self.assertEqual(len(module.extract_records(name, receipt, source_tree)), 1)
        for changed in ({**receipt, "format": True}, {**receipt, "extra": 1},
                        {**receipt, "files": []}, {**receipt, "files": [row, row]},
                        {**receipt, "files": [{**row, "extra": 1}]},
                        {**receipt, "files": [{**row, "blob": "wrong"}]},
                        {**receipt, "files": [{**row, "mode": "100644"}]},
                        {**receipt, "files": [{**row, "path": "missing"}]}):
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                module.extract_records(name, changed, source_tree)

    def test_ledger_uses_source_tree_mode_and_rejects_duplicates(self):
        name = "docs/plans/rust-source-inventory-evidence.json"
        row = {"source_path": "a", "git_blob": "x"}
        receipt = {"format": "dotfiles-source-collection-v1", "revision": "a" * 40,
                   "files": {"one": row}, "generated_outputs": {},
                   "outside_scope_references": {}, "relationships": {}}
        source_tree = {"a": {"mode": "100755", "blob": "x"}}
        self.assertEqual(module.extract_records(name, receipt, source_tree)[0]["mode"], "100755")
        receipt["files"]["two"] = row
        with self.assertRaises(ValueError):
            module.extract_records(name, receipt, source_tree)

    def test_duplicate_json_fields_are_rejected(self):
        self.assertEqual(module.strict_json('{"a": 1}'), {"a": 1})
        with self.assertRaises(ValueError):
            module.strict_json('{"a": 1, "a": 2}')


if __name__ == "__main__":
    unittest.main()
