import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).parent / "helpers"))
import hook_effective_helper as effective


class HelperControls(unittest.TestCase):
    def fixture(self, root):
        (root / "bin").mkdir()
        (root / "lib").mkdir()
        path = root / "lib/dotfiles-endpoint-paths.sh"
        path.write_bytes(b"reviewed helper")
        path.chmod(0o644)
        info = root.stat()
        return (info.st_dev, info.st_ino)

    def test_exact_root_and_helper_are_bound(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            identity = self.fixture(root)
            snapshot = effective.snapshot(root, identity, {"DOTFILES_DIR": str(root)}, b"reviewed helper")
            self.assertIsNotNone(snapshot)
            self.assertEqual(snapshot, effective.snapshot(root, identity, {"DOTFILES_DIR": str(root)}, b"reviewed helper"))
            self.assertIsNone(effective.snapshot(root, identity, {"DOTFILES_DIR": "/other"}, b"reviewed helper"))
            self.assertIsNone(effective.snapshot(root, identity, {}, b"reviewed helper"))
            self.assertIsNone(effective.snapshot(root, (True, 1.0), {"DOTFILES_DIR": str(root)}, b"reviewed helper"))

    def test_missing_changed_or_redirected_inputs_are_rejected(self):
        for mutation in ("missing_bin", "bin_link", "bin_mode", "helper_missing", "helper_link", "helper_hardlink", "helper_changed", "helper_mode"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                identity = self.fixture(root)
                binary = root / "bin"
                helper = root / "lib/dotfiles-endpoint-paths.sh"
                if mutation == "missing_bin": binary.rmdir()
                elif mutation == "bin_link": binary.rmdir(); binary.symlink_to(root / "lib")
                elif mutation == "bin_mode": binary.chmod(0o777)
                elif mutation == "helper_missing": helper.unlink()
                elif mutation == "helper_link": helper.unlink(); helper.symlink_to(root / "lib")
                elif mutation == "helper_hardlink": os.link(helper, root / "lib/second")
                elif mutation == "helper_changed": helper.write_bytes(b"changed")
                else: helper.chmod(0o666)
                self.assertIsNone(effective.snapshot(root, identity, {"DOTFILES_DIR": str(root)}, b"reviewed helper"))

    def test_changes_during_inspection_are_rejected(self):
        for mutation in ("helper", "bin", "root"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                outer = Path(directory)
                root = outer / "root"
                root.mkdir()
                identity = self.fixture(root)
                original = effective.read_source
                calls = []
                def changed(fd, path, mode):
                    result = original(fd, path, mode)
                    if not calls:
                        calls.append(True)
                        if mutation == "helper": (root / path).write_bytes(b"changed")
                        elif mutation == "bin":
                            (root / "bin").rename(root / "displaced-bin")
                            (root / "bin").mkdir()
                        else:
                            root.rename(outer / "displaced-root")
                            root.mkdir()
                    return result
                with patch.object(effective, "read_source", side_effect=changed):
                    self.assertIsNone(effective.snapshot(root, identity, {"DOTFILES_DIR": str(root)}, b"reviewed helper"))

if __name__ == "__main__":
    unittest.main()
