import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).parent / "helpers"))
import hook_mapping_intent as intent


class IntentControls(unittest.TestCase):
    def test_private_request_is_exclusive_and_bound(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            info = root.stat()
            identity = (info.st_dev, info.st_ino)
            run, old, new = "a" * 32, "b" * 40, "c" * 40
            digest = intent.reserve(root, identity, run, old, new)
            self.assertIsNotNone(digest)
            self.assertTrue(intent.verify(root, identity, run, old, new, digest))
            self.assertIsNone(intent.reserve(root, identity, run, old, new))
            self.assertFalse(intent.verify(root, identity, run, old, new, "0" * 64))
            self.assertFalse(intent.verify(root, identity, run, old, "d" * 40, digest))
            self.assertFalse(intent.verify(root, (1, 1), run, old, new, digest))
            request = root / "request.json"
            request.chmod(0o644)
            self.assertFalse(intent.verify(root, identity, run, old, new, digest))

    def test_unsafe_files_and_failed_writes_are_rejected(self):
        run, old, new = "a" * 32, "b" * 40, "c" * 40
        for mutation in ("zero", "error", "chmod", "replace", "symlink", "hardlink"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                outer = Path(directory)
                root = outer / "run"
                root.mkdir(mode=0o700)
                info = root.stat()
                identity = (info.st_dev, info.st_ino)
                if mutation in ("symlink", "hardlink"):
                    digest = intent.reserve(root, identity, run, old, new)
                    request = root / "request.json"
                    target = outer / "target"
                    request.rename(target)
                    if mutation == "symlink": request.symlink_to(target)
                    else: os.link(target, request)
                    self.assertFalse(intent.verify(root, identity, run, old, new, digest))
                    continue
                real_write = intent.os.write
                def inject(fd, data):
                    if mutation == "zero": return 0
                    if mutation == "error": raise OSError("injected")
                    if mutation == "chmod": root.chmod(0o755)
                    else:
                        root.rename(outer / "displaced")
                        root.mkdir(mode=0o700)
                    return real_write(fd, data)
                with patch.object(intent.os, "write", side_effect=inject):
                    self.assertIsNone(intent.reserve(root, identity, run, old, new))
                if mutation == "replace": self.assertEqual(list(root.iterdir()), [])
                else: self.assertTrue((root / "request.json").exists())
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.assertIsNone(intent.reserve(root, (True, 1.0), run, old, new))
            self.assertEqual(list(root.iterdir()), [])

    def test_changed_or_forged_requests_are_rejected(self):
        for mutation in ("origin", "limits", "extra", "bool_format", "duplicate", "noncanonical"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                info = root.stat()
                identity = (info.st_dev, info.st_ino)
                run, old, new = "a" * 32, "b" * 40, "c" * 40
                self.assertIsNotNone(intent.reserve(root, identity, run, old, new))
                path = root / "request.json"
                value = json.loads(path.read_bytes())
                if mutation == "origin": value["origin"] = "https://example.com"
                elif mutation == "limits": value["max_calls"] += 1
                elif mutation == "extra": value["extra"] = True
                elif mutation == "bool_format": value["format"] = True
                raw = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
                if mutation == "duplicate": raw = b'{"format":1,' + raw[1:]
                elif mutation == "noncanonical": raw += b" "
                path.write_bytes(raw)
                self.assertFalse(intent.verify(root, identity, run, old, new, hashlib.sha256(raw).hexdigest()))

if __name__ == "__main__":
    unittest.main()
