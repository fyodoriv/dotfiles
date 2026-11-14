import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).parent / "helpers"))
import hook_source_snapshot as snapshots


class SnapshotControls(unittest.TestCase):
    def fixture(self, root):
        root.chmod(0o700)
        rows = []
        for index, (side, path, mode) in enumerate(snapshots.EXPECTED):
            data = ("hook-" + side if path == snapshots.HOOK else "shared-" + path).encode()
            name = f"{index:03}.src"
            file = root / name
            file.write_bytes(data)
            file.chmod(0o600)
            oid = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data, usedforsecurity=False).hexdigest()
            rows.append({"side": side, "path": path, "mode": mode, "file": name,
                         "blob": oid, "sha256": hashlib.sha256(data).hexdigest()})
        manifest = {"format": 1, "run_id": "a" * 32, "old_revision": "b" * 40,
                    "candidate_revision": "c" * 40, "files": rows}
        raw = json.dumps(manifest, sort_keys=True).encode()
        (root / "manifest.json").write_bytes(raw)
        (root / "manifest.json").chmod(0o600)
        return raw

    def test_checked_snapshot_reopens_with_expected_binding(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            raw = self.fixture(root)
            result = snapshots.read_snapshot(root, raw, "a" * 32, "b" * 40, "c" * 40)
            self.assertIsNotNone(result)
            self.assertEqual(len(result), 9)
            self.assertIsNone(snapshots.read_snapshot(root, raw, "f" * 32, "b" * 40, "c" * 40))
            self.assertIsNone(snapshots.read_snapshot(root, raw, "a" * 32, "b" * 40, "f" * 40))
            self.assertIsNone(snapshots.read_snapshot(root, raw + b" ", "a" * 32, "b" * 40, "c" * 40))

    def test_changed_missing_extra_linked_or_nonprivate_source_fails(self):
        for mutation in ("changed", "missing", "extra", "symlink", "hardlink", "mode", "manifest"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                raw = self.fixture(root)
                target = root / "000.src"
                if mutation == "changed": target.write_bytes(b"changed")
                elif mutation == "missing": target.unlink()
                elif mutation == "extra": (root / "extra").write_text("x")
                elif mutation == "symlink":
                    target.unlink()
                    target.symlink_to(root / "001.src")
                elif mutation == "hardlink":
                    target.unlink()
                    os.link(root / "001.src", target)
                elif mutation == "mode": target.chmod(0o644)
                else: (root / "manifest.json").write_bytes(raw + b" ")
                self.assertIsNone(snapshots.read_snapshot(root, raw, "a" * 32, "b" * 40, "c" * 40))

    def test_wrong_mapping_and_oversized_source_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            raw = self.fixture(root)
            manifest = json.loads(raw)
            manifest["files"][0]["path"] = "wrong"
            changed = json.dumps(manifest, sort_keys=True).encode()
            (root / "manifest.json").write_bytes(changed)
            self.assertIsNone(snapshots.read_snapshot(root, changed, "a" * 32, "b" * 40, "c" * 40))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            raw = self.fixture(root)
            (root / "000.src").write_bytes(b"x" * 2_000_001)
            self.assertIsNone(snapshots.read_snapshot(root, raw, "a" * 32, "b" * 40, "c" * 40))

    def test_forged_manifest_and_changed_shared_source_fail(self):
        for mutation in ("bool_format", "duplicate_key", "wrong_revision", "duplicate_row", "missing_row", "reordered", "mode", "blob", "sha256", "changed_shared"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                raw = self.fixture(root)
                manifest = json.loads(raw)
                if mutation == "bool_format": manifest["format"] = True
                elif mutation == "wrong_revision": manifest["old_revision"] = "f" * 40
                elif mutation == "duplicate_row": manifest["files"][1] = manifest["files"][0]
                elif mutation == "missing_row": manifest["files"].pop()
                elif mutation == "reordered": manifest["files"][0], manifest["files"][1] = manifest["files"][1], manifest["files"][0]
                elif mutation == "mode": manifest["files"][0]["mode"] = "120000"
                elif mutation == "blob": manifest["files"][0]["blob"] = "f" * 40
                elif mutation == "sha256": manifest["files"][0]["sha256"] = "f" * 64
                elif mutation == "changed_shared":
                    data = b"different shared source"
                    row = manifest["files"][5]
                    (root / row["file"]).write_bytes(data)
                    row["blob"] = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data, usedforsecurity=False).hexdigest()
                    row["sha256"] = hashlib.sha256(data).hexdigest()
                changed = json.dumps(manifest, sort_keys=True).encode()
                if mutation == "duplicate_key": changed = b'{"format":1,' + changed[1:]
                (root / "manifest.json").write_bytes(changed)
                self.assertIsNone(snapshots.read_snapshot(root, changed, "a" * 32, "b" * 40, "c" * 40))

    def test_exact_size_limit_is_accepted(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = json.loads(self.fixture(root))
            data = b"x" * 2_000_000
            row = manifest["files"][0]
            (root / row["file"]).write_bytes(data)
            row["blob"] = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data, usedforsecurity=False).hexdigest()
            row["sha256"] = hashlib.sha256(data).hexdigest()
            raw = json.dumps(manifest, sort_keys=True).encode()
            (root / "manifest.json").write_bytes(raw)
            self.assertIsNotNone(snapshots.read_snapshot(root, raw, "a" * 32, "b" * 40, "c" * 40))

    def test_manifest_and_root_must_be_private_regular_inputs(self):
        for mutation in ("root_mode", "manifest_mode", "manifest_symlink", "manifest_hardlink"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                raw = self.fixture(root)
                manifest = root / "manifest.json"
                if mutation == "root_mode": root.chmod(0o755)
                elif mutation == "manifest_mode": manifest.chmod(0o644)
                elif mutation == "manifest_symlink":
                    manifest.unlink()
                    manifest.symlink_to(root / "000.src")
                else:
                    manifest.unlink()
                    os.link(root / "000.src", manifest)
                self.assertIsNone(snapshots.read_snapshot(root, raw, "a" * 32, "b" * 40, "c" * 40))


if __name__ == "__main__":
    unittest.main()
