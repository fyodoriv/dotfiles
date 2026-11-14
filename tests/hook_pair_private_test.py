import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).parent / "helpers"))
import hook_pair_private as private


class PrivateReadControls(unittest.TestCase):
    def test_regular_private_file_and_exact_limit(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "record"
            path.write_bytes(b"abc")
            path.chmod(0o600)
            self.assertEqual(private.read_private(path, 3), b"abc")
            with self.assertRaises(ValueError): private.read_private(path, 2)

    def test_fifo_symlink_hardlink_and_permissions_are_refused(self):
        for mode in ("fifo", "symlink", "hardlink", "permissions"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                target, other = root / "record", root / "other"
                target.write_bytes(b"fixture")
                target.chmod(0o600)
                if mode == "fifo":
                    target.unlink()
                    os.mkfifo(target, 0o600)
                elif mode == "symlink":
                    target.rename(other)
                    target.symlink_to(other)
                elif mode == "hardlink": os.link(target, other)
                else: target.chmod(0o644)
                with self.assertRaises((ValueError, OSError)): private.read_private(target, 4096)

    def test_change_during_read_is_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "record"
            path.write_bytes(b"abc")
            path.chmod(0o600)
            real_read = os.read
            changed = []
            def mutate(fd, count):
                result = real_read(fd, count)
                if not changed:
                    path.write_bytes(b"xyz")
                    changed.append(True)
                return result
            with patch.object(private.os, "read", side_effect=mutate), self.assertRaises(ValueError):
                private.read_private(path, 4096)

    def test_parent_record_must_match(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "parent"
            path.write_text("123\n")
            path.chmod(0o600)
            self.assertTrue(private.expected_parent_valid(path, 123))
            self.assertFalse(private.expected_parent_valid(path, 124))


if __name__ == "__main__":
    unittest.main()
