import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("git_blob_batch", Path(__file__).parents[1] / "docs/plans/git_blob_batch.py")
batch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(batch)


class BatchReads(unittest.TestCase):
    def test_one_process_preserves_order_and_bytes(self):
        one, two = "a" * 40, "b" * 40
        output = (one + " blob 4\n").encode() + b"a\nb\x00\n" + (two + " blob 0\n\n").encode()
        with patch.object(batch.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, output)) as run:
            self.assertEqual(batch.read_blobs([one, two]), [b"a\nb\x00", b""])
        self.assertEqual(run.call_count, 1)
        self.assertEqual(run.call_args.args[0], ["git", "cat-file", "--batch"])
        self.assertEqual(run.call_args.kwargs["input"], (one + "\n" + two + "\n").encode())
        self.assertTrue(run.call_args.kwargs["check"])

    def test_invalid_or_incomplete_responses_fail_closed(self):
        blob = "a" * 40
        responses = [b"", (blob + " missing\n").encode(), (blob + " tree 0\n\n").encode(),
                     (blob + " blob 2\nx\n").encode(), (blob + " blob 1\nx\nextra").encode(),
                     ("b" * 40 + " blob 0\n\n").encode()]
        for response in responses:
            with self.subTest(response=response), patch.object(batch.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, response)):
                with self.assertRaises(ValueError):
                    batch.read_blobs([blob])
        with patch.object(batch.subprocess, "run") as run:
            with self.assertRaises(ValueError):
                batch.read_blobs(["invalid\nrequest"])
            run.assert_not_called()
        with patch.object(batch.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "git")):
            with self.assertRaises(subprocess.CalledProcessError):
                batch.read_blobs([blob])


if __name__ == "__main__":
    unittest.main()
