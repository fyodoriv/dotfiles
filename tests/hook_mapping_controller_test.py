import json
from contextlib import nullcontext
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).parent / "helpers"))
import hook_mapping_controller as controller
import hook_mapping_intent as intent
import hook_remote_mapping_test as mapping_tests


class ControllerControls(unittest.TestCase):
    def test_fetch_only_after_valid_intent_and_recheck(self):
        for mutation in ("none", "missing", "wrong_digest", "changed_during_fetch", "extra", "failed_fetch", "chmod", "extra_during", "replace", "write_failure", "archive_tamper"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                outer = Path(directory)
                root = outer / "run"
                root.mkdir(mode=0o700)
                info = root.stat()
                identity = (info.st_dev, info.st_ino)
                old, new, commits, trees = mapping_tests.MappingControls().fixture()
                run = "9" * 32
                digest = intent.reserve(root, identity, run, old, new)
                records = {(kind, key): json.dumps(value).encode() for kind, group in
                           (("commits", commits), ("trees", trees)) for key, value in group.items()}
                calls = []
                def fetch(kind, oid):
                    calls.append((kind, oid))
                    if len(calls) == 1:
                        if mutation == "changed_during_fetch": (root / "request.json").write_text("{}")
                        elif mutation == "chmod": root.chmod(0o755)
                        elif mutation == "extra_during": (root / "extra").write_text("x")
                        elif mutation == "replace":
                            root.rename(outer / "displaced")
                            root.mkdir(mode=0o700)
                    return None if mutation == "failed_fetch" else records.get((kind, oid))
                if mutation == "missing": (root / "request.json").unlink()
                elif mutation == "wrong_digest": digest = "0" * 64
                elif mutation == "extra": (root / "extra").write_text("x")
                real_store = controller.remote.store_archive
                def store(*args):
                    if mutation == "write_failure": return None
                    result = real_store(*args)
                    (root / "mapping.json").write_text("{}")
                    return result
                context = patch.object(controller.remote, "store_archive", side_effect=store) if mutation in ("write_failure", "archive_tamper") else nullcontext()
                with context:
                    result = controller.collect_private(root, identity, run, old, new, digest, fetch)
                if mutation == "none":
                    self.assertIsNotNone(result)
                    self.assertEqual(len(calls), 8)
                    self.assertTrue((root / "mapping.json").is_file())
                else:
                    self.assertIsNone(result)
                    if mutation != "archive_tamper": self.assertFalse((root / "mapping.json").exists())
                    if mutation in ("missing", "wrong_digest", "extra"): self.assertEqual(calls, [])

if __name__ == "__main__":
    unittest.main()
