import copy
from pathlib import Path
import sys
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).parent / "helpers"))
import hook_remote_mapping as mapping


class MappingControls(unittest.TestCase):
    def fixture(self):
        old, new = "a" * 40, "b" * 40
        roots = {old: "c" * 40, new: "d" * 40}
        trees = {}
        commits = {rev: {"sha": rev, "tree": {"sha": tree}} for rev, tree in roots.items()}
        for index, (rev, root) in enumerate(roots.items()):
            hook_tree, lib_tree = ("e" if index == 0 else "f") * 40, ("1" if index == 0 else "2") * 40
            trees[root] = {"sha": root, "truncated": False, "tree": [
                {"path": "agent-hooks", "mode": "040000", "type": "tree", "sha": hook_tree},
                {"path": "lib", "mode": "040000", "type": "tree", "sha": lib_tree}]}
            entries = [
                {"path": "block-dangerous-git.sh", "mode": "100755", "type": "blob", "sha": "3" * 40},
                {"path": "bootstrap-endpoint-path.sh", "mode": "100755", "type": "blob", "sha": "4" * 40},
                {"path": "plain-document-write.jq", "mode": "100644", "type": "blob", "sha": "5" * 40}]
            if rev == new:
                entries.append({"path": "literal-status-only.sh", "mode": "100755", "type": "blob", "sha": "6" * 40})
            trees[hook_tree] = {"sha": hook_tree, "truncated": False, "tree": entries}
            trees[lib_tree] = {"sha": lib_tree, "truncated": False, "tree": [
                {"path": "dotfiles-endpoint-paths.sh", "mode": "100644", "type": "blob", "sha": "7" * 40}]}
        return old, new, commits, trees

    def test_exact_mapping(self):
        old, new, commits, trees = self.fixture()
        result = mapping.resolve(old, new, commits, trees)
        expected = {}
        for side in ("old", "new"):
            for name, mode, blob in (("block-dangerous-git.sh", "100755", "3"),
                                     ("bootstrap-endpoint-path.sh", "100755", "4"),
                                     ("plain-document-write.jq", "100644", "5")):
                expected[(side, "agent-hooks/" + name)] = (mode, blob * 40)
            expected[(side, "lib/dotfiles-endpoint-paths.sh")] = ("100644", "7" * 40)
        expected[("new", "agent-hooks/literal-status-only.sh")] = ("100755", "6" * 40)
        self.assertEqual(result, expected)

    def test_rejects_unverified_commit_and_tree_responses(self):
        for mutation in ("commit_sha", "root", "tree_sha", "truncated", "missing_tree", "duplicate", "missing_path", "mode", "type", "blob", "bad_path", "bool_truncated", "branch_type", "branch_mode", "bad_revision", "missing_commit", "branch_sha", "row_type", "null_root"):
            with self.subTest(mutation=mutation):
                old, new, commits, trees = self.fixture()
                if mutation == "branch_sha": trees["c" * 40]["tree"][0]["sha"] = "bad"
                elif mutation == "row_type": trees["c" * 40]["tree"].append(None)
                elif mutation == "null_root": commits[old]["tree"] = None
                elif mutation == "branch_type": trees["c" * 40]["tree"][0]["type"] = "blob"
                elif mutation == "branch_mode": trees["c" * 40]["tree"][0]["mode"] = "120000"
                elif mutation == "bad_revision": old = "a" * 39
                elif mutation == "missing_commit": del commits[old]
                elif mutation == "commit_sha": commits[old]["sha"] = "9" * 40
                elif mutation == "root": commits[old]["tree"]["sha"] = "9" * 40
                elif mutation == "tree_sha": trees["c" * 40]["sha"] = "9" * 40
                elif mutation == "truncated": trees["c" * 40]["truncated"] = True
                elif mutation == "bool_truncated": trees["c" * 40]["truncated"] = 0
                elif mutation == "missing_tree": del trees["e" * 40]
                elif mutation == "duplicate": trees["e" * 40]["tree"].append(copy.deepcopy(trees["e" * 40]["tree"][0]))
                elif mutation == "missing_path": trees["e" * 40]["tree"].pop(0)
                elif mutation == "mode": trees["e" * 40]["tree"][0]["mode"] = "120000"
                elif mutation == "type": trees["e" * 40]["tree"][0]["type"] = "commit"
                elif mutation == "blob": trees["e" * 40]["tree"][0]["sha"] = "bad"
                else: trees["e" * 40]["tree"][0]["path"] = "../block-dangerous-git.sh"
                self.assertIsNone(mapping.resolve(old, new, commits, trees))

if __name__ == "__main__":
    unittest.main()
