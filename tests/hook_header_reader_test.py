#!/usr/bin/env python3
"""Only private synthetic files are opened; no fixture is executed."""
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent / "helpers"))
import hook_header_reader as reader
from hook_snapshot_acquire import LIMIT


class HeaderReaderTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / "bin").mkdir(mode=0o700)
        self.file = self.root / "bin/tool"
        self.file.write_bytes(b"#!/bin/bash\nexit 0\n")
        self.file.chmod(0o700)
        self.fd = os.open(self.root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        info = os.fstat(self.fd)
        self.identity = (info.st_dev, info.st_ino)

    def tearDown(self):
        os.close(self.fd)
        self.temp.cleanup()

    def check(self, path="bin/tool", identity=None):
        return reader.read_header(self.fd, self.identity if identity is None else identity, path)

    def test_regular_file_and_empty_not_trusted(self):
        self.assertEqual(self.check()["header"], ("script", "/bin/bash", None))
        self.file.write_bytes(b"")
        self.assertEqual(self.check()["header"], ("not_script", None, None))

    def test_paths_and_identity_rejected(self):
        for path in ("../tool", "bin/../tool", "/bin/tool", "bin/./tool", "bin/missing"):
            with self.subTest(path=path):
                self.assertIsNone(self.check(path))
        self.assertIsNone(self.check(identity=(0, 0)))
        self.root.chmod(0o755)
        self.assertIsNone(self.check())
        self.root.chmod(0o700)
        (self.root / "alias").symlink_to("bin", target_is_directory=True)
        self.assertIsNone(self.check("alias/tool"))

    def test_links_types_mode_and_size_rejected(self):
        self.file.unlink()
        self.file.symlink_to("missing")
        self.assertIsNone(self.check())
        self.file.unlink()
        os.mkfifo(self.file, 0o700)
        self.assertIsNone(self.check())
        self.file.unlink()
        self.file.write_bytes(b"#!/bin/bash\n")
        self.file.chmod(0o722)
        self.assertIsNone(self.check())
        self.file.chmod(0o700)
        os.link(self.file, self.root / "bin/second")
        self.assertIsNone(self.check())
        (self.root / "bin/second").unlink()
        with self.file.open("wb") as file:
            file.truncate(LIMIT + 1)
        self.assertIsNone(self.check())

    def test_changed_or_short_reads_fail(self):
        original_read = os.read
        mutated = False

        def change_during_read(fd, count):
            nonlocal mutated
            if not mutated:
                mutated = True
                with self.file.open("ab") as file:
                    file.write(b"changed")
            return original_read(fd, count)

        with patch("hook_snapshot_acquire.os.read", side_effect=change_during_read):
            self.assertIsNone(self.check())
        self.file.write_bytes(b"#!/bin/bash\n")
        original_source = reader.read_source

        def change_root(*args):
            result = original_source(*args)
            self.root.chmod(0o755)
            return result

        with patch.object(reader, "read_source", side_effect=change_root):
            self.assertIsNone(self.check())
        self.root.chmod(0o700)
        with patch("hook_snapshot_acquire.os.read", return_value=b""):
            self.assertIsNone(self.check())
        self.file.write_bytes(b"#!/bin/bash")
        self.assertIsNone(self.check())


if __name__ == "__main__":
    unittest.main()
