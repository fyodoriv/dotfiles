import os
from pathlib import Path
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).parent / "helpers"))
import hook_run_locality as locality


class LocalityControls(unittest.TestCase):
    def test_local_nonlocal_unknown_and_bad_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            info = root.stat()
            identity = (info.st_dev, info.st_ino)
            called = []
            def inspect(fd):
                called.append(os.fstat(fd).st_ino)
                return True
            self.assertTrue(locality.check(root, identity, inspect))
            self.assertEqual(called, [identity[1]])
            self.assertFalse(locality.check(root, identity, lambda fd: False))
            self.assertFalse(locality.check(root, identity, lambda fd: None))
            self.assertFalse(locality.check(root, identity, lambda fd: 1))
            self.assertFalse(locality.check(root, identity, None))
            self.assertFalse(locality.check(root, (True, 1.0), inspect))
            self.assertFalse(locality.check(root, (1, 1), inspect))

    def test_directory_change_or_inspector_failure_rejected(self):
        for mutation in ("chmod", "replace", "error", "unexpected"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                outer = Path(directory)
                root = outer / "run"
                root.mkdir(mode=0o700)
                info = root.stat()
                def inspect(fd):
                    if mutation == "chmod": root.chmod(0o755)
                    elif mutation == "replace":
                        root.rename(outer / "displaced")
                        root.mkdir(mode=0o700)
                    elif mutation == "error": raise OSError("injected")
                    else: raise RuntimeError("injected")
                    return True
                self.assertFalse(locality.check(root, (info.st_dev, info.st_ino), inspect))

if __name__ == "__main__":
    unittest.main()
