import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).parent / "helpers"))
import hook_pair_receipts as receipts
import hook_status_pairs as pairs


class ReceiptControls(unittest.TestCase):
    def test_complete_attempts_are_reread_and_bound(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            root.chmod(0o700)
            sink = receipts.AttemptSink(root, "a" * 32)
            result = pairs.capture(lambda _case, _side: (100, 0, b"", b""),
                                   lambda: True, lambda: True, sink.record)
            self.assertTrue(result["valid"])
            self.assertTrue(sink.verify(result["attempts"]))
            self.assertEqual(receipts.read_attempts(root, "a" * 32), result["attempts"])
            self.assertIsNone(receipts.read_attempts(root, "b" * 32))
            self.assertFalse(sink.verify(result["attempts"][:-1]))

    def test_missing_truncated_extra_and_wrong_identity_are_rejected(self):
        for mutation in ("missing", "truncated", "extra", "wrong_id", "wrong_order", "duplicate_key", "bool_ordinal", "symlink", "hardlink", "file_mode", "dir_mode"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                root.chmod(0o700)
                sink = receipts.AttemptSink(root, "a" * 32)
                result = pairs.capture(lambda _case, _side: (100, 0, b"", b""),
                                       lambda: True, lambda: True, sink.record)
                target = root / "attempts" / "000.json"
                if mutation == "missing":
                    target.unlink()
                elif mutation == "truncated":
                    target.write_text("{")
                elif mutation == "extra":
                    (root / "attempts" / "extra.json").write_text("{}")
                elif mutation == "symlink":
                    target.unlink()
                    target.symlink_to(root / "attempts" / "001.json")
                elif mutation == "hardlink":
                    target.unlink()
                    os.link(root / "attempts" / "001.json", target)
                elif mutation == "file_mode":
                    target.chmod(0o644)
                elif mutation == "dir_mode":
                    (root / "attempts").chmod(0o755)
                elif mutation == "duplicate_key":
                    target.write_text('{"format":1,' + target.read_text()[1:])
                else:
                    record = json.loads(target.read_text())
                    if mutation == "wrong_id":
                        record["run_id"] = "b" * 32
                    elif mutation == "wrong_order":
                        record["attempt"]["side"] = "new"
                    else:
                        record["ordinal"] = False
                    target.write_text(json.dumps(record))
                self.assertFalse(sink.verify(result["attempts"]))
                self.assertIsNone(receipts.read_attempts(root, "a" * 32))

    def test_unfinished_or_interrupted_capture_cannot_verify(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            root.chmod(0o700)
            sink = receipts.AttemptSink(root, "a" * 32)
            def interrupted(_case, _side):
                raise KeyboardInterrupt()
            with self.assertRaises(KeyboardInterrupt):
                pairs.capture(interrupted, lambda: True, lambda: True, sink.record)
            self.assertFalse(sink.verify([]))

    def test_partial_write_never_qualifies(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            root.chmod(0o700)
            sink = receipts.AttemptSink(root, "a" * 32)
            def fail_write(path, _value):
                path.write_text("{")
                raise OSError("private fixture")
            with patch.object(receipts, "write_private_json", side_effect=fail_write):
                result = pairs.capture(lambda _case, _side: (100, 0, b"", b""),
                                       lambda: True, lambda: True, sink.record)
            self.assertFalse(result["valid"])
            self.assertIsNone(receipts.read_attempts(root, "a" * 32))
            self.assertNotIn("private fixture", json.dumps(result))


if __name__ == "__main__":
    unittest.main()
