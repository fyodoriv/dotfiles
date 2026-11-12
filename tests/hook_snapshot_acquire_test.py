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
import hook_snapshot_acquire as acquisition
import hook_source_snapshot as snapshots


class AcquisitionControls(unittest.TestCase):
    def fixture(self, root):
        roots = {side: root / side for side in ("old", "new")}
        for path in roots.values(): path.mkdir()
        run = root / "run"
        run.mkdir(mode=0o700)
        rows = []
        for index, (side, path, mode) in enumerate(snapshots.EXPECTED):
            source = roots[side] / path
            source.parent.mkdir(parents=True, exist_ok=True)
            data = ("hook-" + side if path == snapshots.HOOK else "shared-" + path).encode()
            source.write_bytes(data)
            source.chmod(0o755 if mode == "100755" else 0o644)
            oid = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data, usedforsecurity=False).hexdigest()
            rows.append({"side": side, "path": path, "mode": mode, "file": f"{index:03}.src",
                         "blob": oid, "sha256": hashlib.sha256(data).hexdigest()})
        manifest = {"format": 1, "run_id": "a" * 32, "old_revision": "b" * 40,
                    "candidate_revision": "c" * 40, "files": rows}
        identities = {side: (path.stat().st_dev, path.stat().st_ino) for side, path in roots.items()}
        return run, roots, identities, json.dumps(manifest, sort_keys=True).encode()

    def acquire(self, run, roots, identities, raw):
        info = run.stat()
        return acquisition.acquire(run, raw, "a" * 32, "b" * 40, "c" * 40, roots, identities,
                                   (info.st_dev, info.st_ino))

    def test_acquisition_and_independent_readback(self):
        with tempfile.TemporaryDirectory() as directory:
            run, roots, identities, raw = self.fixture(Path(directory))
            self.assertTrue(self.acquire(run, roots, identities, raw))
            self.assertIsNotNone(snapshots.read_snapshot(run / "source", raw, "a" * 32, "b" * 40, "c" * 40))

    def test_wrong_root_link_or_source_never_creates_snapshot(self):
        for mutation in ("root_identity", "root_writable", "dir_writable", "file_writable", "intermediate_link", "final_link", "hardlink", "fifo", "mode", "changed", "oversized"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                run, roots, identities, raw = self.fixture(root)
                source = roots["old"] / snapshots.HOOK
                if mutation == "root_identity": identities["old"] = (0, 0)
                elif mutation == "root_writable": roots["old"].chmod(0o777)
                elif mutation == "dir_writable": source.parent.chmod(0o777)
                elif mutation == "file_writable": source.chmod(0o777)
                elif mutation == "intermediate_link":
                    parent = source.parent
                    target = roots["old"] / "original-hooks"
                    parent.rename(target)
                    parent.symlink_to(target)
                elif mutation == "final_link":
                    source.rename(source.with_name("original"))
                    source.symlink_to(source.with_name("original"))
                elif mutation == "hardlink": os.link(source, source.with_name("extra"))
                elif mutation == "fifo":
                    source.unlink()
                    os.mkfifo(source)
                elif mutation == "mode": source.chmod(0o644)
                elif mutation == "changed": source.write_bytes(b"changed")
                else: source.write_bytes(b"x" * 2_000_001)
                self.assertFalse(self.acquire(run, roots, identities, raw))
                self.assertFalse((run / "source").exists())

    def test_existing_destination_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            run, roots, identities, raw = self.fixture(Path(directory))
            dest = run / "source"
            dest.mkdir(mode=0o700)
            (dest / "sentinel").write_text("keep")
            self.assertFalse(self.acquire(run, roots, identities, raw))
            self.assertEqual((dest / "sentinel").read_text(), "keep")

    def test_wrong_run_identity_never_creates_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            run, roots, identities, raw = self.fixture(Path(directory))
            self.assertFalse(acquisition.acquire(run, raw, "a" * 32, "b" * 40, "c" * 40,
                                                 roots, identities, (0, 0)))
            self.assertFalse((run / "source").exists())

    def test_partial_write_is_incomplete_and_private(self):
        with tempfile.TemporaryDirectory() as directory:
            run, roots, identities, raw = self.fixture(Path(directory))
            with patch.object(acquisition.os, "write", side_effect=OSError("PRIVATE_CANARY")):
                self.assertFalse(self.acquire(run, roots, identities, raw))
            self.assertIsNone(snapshots.read_snapshot(run / "source", raw, "a" * 32, "b" * 40, "c" * 40))

    def test_source_change_during_copy_never_publishes_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            run, roots, identities, raw = self.fixture(Path(directory))
            original = acquisition.write_private
            def change_after_write(fd, name, data):
                original(fd, name, data)
                if name == "000.src":
                    (roots["old"] / snapshots.HOOK).write_bytes(b"changed")
            with patch.object(acquisition, "write_private", side_effect=change_after_write):
                self.assertFalse(self.acquire(run, roots, identities, raw))
            self.assertFalse((run / "source/manifest.json").exists())

    def test_replaced_root_or_same_content_inode_never_qualifies(self):
        for mutation in ("root", "file_inode"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                run, roots, identities, raw = self.fixture(root)
                original = acquisition.write_private
                def replace_after_write(fd, name, data):
                    original(fd, name, data)
                    if name != "000.src":
                        return
                    if mutation == "root":
                        roots["old"].rename(root / "old-moved")
                        roots["old"].mkdir()
                    else:
                        source = roots["old"] / snapshots.HOOK
                        content = source.read_bytes()
                        source.rename(source.with_name("original"))
                        source.write_bytes(content)
                        source.chmod(0o755)
                with patch.object(acquisition, "write_private", side_effect=replace_after_write):
                    self.assertFalse(self.acquire(run, roots, identities, raw))
                self.assertFalse((run / "source/manifest.json").exists())

    def test_replaced_run_directory_never_publishes_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            run, roots, identities, raw = self.fixture(root)
            info = run.stat()
            original = acquisition.write_private
            def replace_run(fd, name, data):
                original(fd, name, data)
                if name == "000.src":
                    run.rename(root / "old-run")
                    run.mkdir(mode=0o700)
            with patch.object(acquisition, "write_private", side_effect=replace_run):
                self.assertFalse(acquisition.acquire(run, raw, "a" * 32, "b" * 40, "c" * 40,
                                                     roots, identities, (info.st_dev, info.st_ino)))
            self.assertFalse((root / "old-run/source/manifest.json").exists())

    def test_permissions_changed_during_copy_never_publish_manifest(self):
        for target in ("root", "run"):
            with self.subTest(target=target), tempfile.TemporaryDirectory() as directory:
                run, roots, identities, raw = self.fixture(Path(directory))
                original = acquisition.write_private
                def change_mode(fd, name, data):
                    original(fd, name, data)
                    if name == "000.src":
                        (roots["old"] if target == "root" else run).chmod(0o777)
                with patch.object(acquisition, "write_private", side_effect=change_mode):
                    self.assertFalse(self.acquire(run, roots, identities, raw))
                self.assertFalse((run / "source/manifest.json").exists())

    def test_short_writes_are_retried_and_zero_writes_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            run, roots, identities, raw = self.fixture(Path(directory))
            real_write = acquisition.os.write
            with patch.object(acquisition.os, "write", side_effect=lambda fd, data: real_write(fd, data[:1])):
                self.assertTrue(self.acquire(run, roots, identities, raw))
        with tempfile.TemporaryDirectory() as directory:
            run, roots, identities, raw = self.fixture(Path(directory))
            with patch.object(acquisition.os, "write", return_value=0):
                self.assertFalse(self.acquire(run, roots, identities, raw))
            self.assertFalse((run / "source/manifest.json").exists())


if __name__ == "__main__":
    unittest.main()
