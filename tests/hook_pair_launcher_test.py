import importlib.util
import hashlib
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).parent / "helpers"))
import hook_trusted_launch as trusted
import hook_pair_receipts as records
import hook_status_pairs as pairs
import hook_source_snapshot as snapshots

MODULE = Path(__file__).parent / "helpers/hook_pair_launcher.py"
spec = importlib.util.spec_from_file_location("hook_pair_launcher", MODULE)
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)


class LaunchControls(unittest.TestCase):
    def source_inputs(self, root):
        old_root = root / "old-checkout"
        old_root.mkdir()
        roots = {"old": old_root, "new": root}
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
        manifest = {"format": 1, "run_id": "e" * 32, "old_revision": "c" * 40,
                    "candidate_revision": "b" * 40, "files": rows}
        manifest_path = root / "source-manifest.json"
        trusted.write_private_json(manifest_path, manifest)
        identities = {}
        for side, path in roots.items():
            info = path.stat()
            identities[side] = {"path": str(path), "dev": info.st_dev, "ino": info.st_ino}
        audit = {"format": 1, "run_id": "e" * 32, "old_revision": "c" * 40,
                 "candidate_revision": "b" * 40, "manifest_sha256": hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
                 "local_filesystems": True, "roots": identities}
        audit_path = root / "source-audit.json"
        trusted.write_private_json(audit_path, audit)
        return audit_path, manifest_path

    def test_invalid_identity_never_starts_a_child(self):
        with patch.object(launcher, "launch_and_wait", side_effect=AssertionError("child started")):
            self.assertFalse(launcher.run_qualified(Path("/scratch"), "bad", "b" * 40,
                                                    "c" * 40, Path("/missing"), {}, "d" * 32))

    def test_private_intent_exists_before_queue_admission(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            parent = root / ".local/state/dotfiles/rust-migration"
            parent.mkdir(parents=True)
            parent.chmod(0o700)
            script = root / "tests/helpers/hook_pair_launcher.py"
            script.parent.mkdir(parents=True)
            script.write_text("fixture")
            audit = root / "audit.json"
            trusted.write_private_json(audit, dict.fromkeys(("launcher", "harness", "perl", "BASH_ENV", "ENV", "wrapper"), "a" * 64))
            source_audit, source_manifest = self.source_inputs(root)
            seen = []
            def fake_launch(_launcher, _command, run_dir, _env, _workdir):
                intent = trusted.strict_json(trusted.read_private(run_dir / "intent.json", 4096))
                seen.append(intent["run_id"])
                return SimpleNamespace(pid=123), 1
            with patch.object(launcher, "__file__", str(script)), \
                    patch.object(launcher, "audited_inputs_valid", return_value=True), \
                    patch.object(launcher, "matches_digest", return_value=True), \
                    patch.object(launcher, "resolve_perl", return_value="/scratch/perl"), \
                    patch.object(launcher, "source_clean", return_value=True), \
                    patch.object(launcher, "pair_source_clean", return_value=True), \
                    patch.object(launcher, "old_source_available", return_value=True, create=True), \
                    patch.object(launcher, "installed_root", return_value=True), \
                    patch.object(launcher, "launch_and_wait", side_effect=fake_launch):
                valid = launcher.run_qualified(root, "b" * 40, "c" * 40, "d" * 40,
                                               audit, {"HOME": str(root)}, "e" * 32, source_audit, source_manifest)
            self.assertFalse(valid)
            self.assertEqual(seen, ["e" * 32])
            self.assertFalse((parent / ("hook-rss-" + "e" * 32) / "launch.json").exists())

    def test_unavailable_old_source_never_starts_a_child(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            parent = root / ".local/state/dotfiles/rust-migration"
            parent.mkdir(parents=True)
            parent.chmod(0o700)
            script = root / "tests/helpers/hook_pair_launcher.py"
            script.parent.mkdir(parents=True)
            script.write_text("fixture")
            audit = root / "audit.json"
            trusted.write_private_json(audit, dict.fromkeys(("launcher", "harness", "perl", "BASH_ENV", "ENV", "wrapper"), "a" * 64))
            source_audit, source_manifest = self.source_inputs(root)
            with patch.object(launcher, "__file__", str(script)), \
                    patch.object(launcher, "audited_inputs_valid", return_value=True), \
                    patch.object(launcher, "matches_digest", return_value=True), \
                    patch.object(launcher, "source_clean", return_value=True), \
                    patch.object(launcher, "pair_source_clean", return_value=True), \
                    patch.object(launcher, "old_source_available", return_value=False, create=True), \
                    patch.object(launcher, "installed_root", return_value=True), \
                    patch.object(launcher, "resolve_perl", return_value="/scratch/perl"), \
                    patch.object(launcher, "launch_and_wait", side_effect=AssertionError("child started")):
                self.assertFalse(launcher.run_qualified(root, "b" * 40, "c" * 40, "d" * 40,
                                                        audit, {"HOME": str(root)}, "e" * 32, source_audit, source_manifest))

    def test_complete_synthetic_run_publishes_only_verified_record(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            parent = root / ".local/state/dotfiles/rust-migration"
            parent.mkdir(parents=True)
            parent.chmod(0o700)
            script = root / "tests/helpers/hook_pair_launcher.py"
            script.parent.mkdir(parents=True)
            script.write_text("fixture")
            audit = root / "audit.json"
            trusted.write_private_json(audit, dict.fromkeys(("launcher", "harness", "perl", "BASH_ENV", "ENV", "wrapper"), "a" * 64))
            source_audit, source_manifest = self.source_inputs(root)
            def fake_launch(_launcher, _command, run_dir, _env, _workdir):
                parent_file = run_dir / "parent"
                parent_file.write_text("123\n")
                parent_file.chmod(0o600)
                (run_dir / "wait.log").write_text("waited=1 pid=123 slot=exclusive\n")
                sink = records.AttemptSink(run_dir, "e" * 32)
                result = pairs.capture(lambda _case, side: (100 if side == "old" else 75, 0, b"", b""),
                                       lambda: True, lambda: True, sink.record)
                trusted.write_private_json(run_dir / "receipt.json", {
                    "format": 1, "run_id": "e" * 32, "valid": result["valid"], "passed": result["passed"],
                    "median_ratios": result["median_ratios"], "flags": dict.fromkeys(pairs.FLAGS, True), "failure": None,
                })
                return SimpleNamespace(pid=123), 0
            with patch.object(launcher, "__file__", str(script)), \
                    patch.object(launcher, "audited_inputs_valid", return_value=True), \
                    patch.object(launcher, "matches_digest", return_value=True), \
                    patch.object(launcher, "resolve_perl", return_value="/scratch/perl"), \
                    patch.object(launcher, "source_clean", return_value=True), \
                    patch.object(launcher, "pair_source_clean", return_value=True), \
                    patch.object(launcher, "old_source_available", return_value=True), \
                    patch.object(launcher, "installed_root", return_value=True), \
                    patch.object(Path, "unlink", side_effect=AssertionError("unexpected cleanup")), \
                    patch.object(launcher, "launch_and_wait", side_effect=fake_launch):
                self.assertTrue(launcher.run_qualified(root, "b" * 40, "c" * 40, "d" * 40,
                                                       audit, {"HOME": str(root)}, "e" * 32, source_audit, source_manifest))
            run_dir = parent / ("hook-rss-" + "e" * 32)
            self.assertTrue((run_dir / "launch.json").is_file())
            self.assertEqual((run_dir / "launch.json").stat().st_ino, (run_dir / "launch.pending").stat().st_ino)
            self.assertEqual((run_dir / "launch.json").stat().st_nlink, 2)

    def test_wrong_audited_root_never_starts_a_child(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            parent = root / ".local/state/dotfiles/rust-migration"
            parent.mkdir(parents=True)
            parent.chmod(0o700)
            script = root / "tests/helpers/hook_pair_launcher.py"
            script.parent.mkdir(parents=True)
            script.write_text("fixture")
            audit = root / "audit.json"
            trusted.write_private_json(audit, dict.fromkeys(("launcher", "harness", "perl", "BASH_ENV", "ENV", "wrapper"), "a" * 64))
            source_audit, source_manifest = self.source_inputs(root)
            value = json.loads(source_audit.read_text())
            value["roots"]["old"]["ino"] += 1
            source_audit.write_text(json.dumps(value))
            with patch.object(launcher, "__file__", str(script)), \
                    patch.object(launcher, "audited_inputs_valid", return_value=True), \
                    patch.object(launcher, "matches_digest", return_value=True), \
                    patch.object(launcher, "source_clean", return_value=True), \
                    patch.object(launcher, "pair_source_clean", return_value=True), \
                    patch.object(launcher, "old_source_available", return_value=True), \
                    patch.object(launcher, "installed_root", return_value=True), \
                    patch.object(launcher, "launch_and_wait", side_effect=AssertionError("child started")):
                self.assertFalse(launcher.run_qualified(root, "b" * 40, "c" * 40, "d" * 40,
                                                        audit, {"HOME": str(root)}, "e" * 32, source_audit, source_manifest))

    def test_synthetic_failures_never_publish_a_final_record(self):
        for mode in ("wrong_parent", "shared_wait", "partial", "forged_flag", "rejected_pending", "source_changed", "audit_changed", "source_audit_changed", "manifest_changed", "link_failure"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                parent = root / ".local/state/dotfiles/rust-migration"
                parent.mkdir(parents=True)
                parent.chmod(0o700)
                script = root / "tests/helpers/hook_pair_launcher.py"
                script.parent.mkdir(parents=True)
                script.write_text("fixture")
                audit = root / "audit.json"
                trusted.write_private_json(audit, dict.fromkeys(("launcher", "harness", "perl", "BASH_ENV", "ENV", "wrapper"), "a" * 64))
                source_audit, source_manifest = self.source_inputs(root)
                def fake_launch(_launcher, _command, run_dir, _env, _workdir):
                    parent_file = run_dir / "parent"
                    parent_file.write_text("999\n" if mode == "wrong_parent" else "123\n")
                    parent_file.chmod(0o600)
                    (run_dir / "wait.log").write_text("waited=1 pid=123 slot=shared\n" if mode == "shared_wait" else "waited=1 pid=123 slot=exclusive\n")
                    sink = records.AttemptSink(run_dir, "e" * 32)
                    result = pairs.capture(lambda _case, side: (100 if side == "old" else 75, 0, b"", b""),
                                           lambda: True, lambda: True, sink.record)
                    if mode == "partial":
                        (run_dir / "attempts/119.json").unlink()
                    flags = dict.fromkeys(pairs.FLAGS, True)
                    if mode == "forged_flag":
                        flags["source"] = False
                    trusted.write_private_json(run_dir / "receipt.json", {
                        "format": 1, "run_id": "e" * 32, "valid": result["valid"], "passed": result["passed"],
                        "median_ratios": result["median_ratios"], "flags": flags, "failure": None,
                    })
                    if mode == "audit_changed":
                        audit.write_text("{}")
                    elif mode == "source_audit_changed":
                        source_audit.write_text("{}")
                    elif mode == "manifest_changed":
                        source_manifest.write_text("{}")
                    return SimpleNamespace(pid=123), 0
                original_verify = launcher.verify_pair_link
                original_link = launcher.os.link
                def verify(*args, **kwargs):
                    return None if mode == "rejected_pending" else original_verify(*args, **kwargs)
                def link(source, destination, *args, **kwargs):
                    if mode == "link_failure" and Path(destination).name == "launch.json":
                        raise OSError("private fixture")
                    return original_link(source, destination, *args, **kwargs)
                with patch.object(launcher, "__file__", str(script)), \
                        patch.object(launcher, "audited_inputs_valid", return_value=True), \
                        patch.object(launcher, "matches_digest", return_value=True), \
                        patch.object(launcher, "resolve_perl", return_value="/scratch/perl"), \
                        patch.object(launcher, "source_clean", side_effect=[True, False] if mode == "source_changed" else None, return_value=True), \
                        patch.object(launcher, "pair_source_clean", return_value=True), \
                        patch.object(launcher, "old_source_available", return_value=True), \
                        patch.object(launcher, "installed_root", return_value=True), \
                        patch.object(launcher, "launch_and_wait", side_effect=fake_launch), \
                        patch.object(launcher.os, "link", side_effect=link), \
                        patch.object(launcher, "verify_pair_link", side_effect=verify):
                    self.assertFalse(launcher.run_qualified(root, "b" * 40, "c" * 40, "d" * 40,
                                                            audit, {"HOME": str(root)}, "e" * 32, source_audit, source_manifest))
                run_dir = parent / ("hook-rss-" + "e" * 32)
                self.assertFalse((run_dir / "launch.json").exists())
                if mode != "link_failure":
                    self.assertFalse((run_dir / "launch.pending").exists())


if __name__ == "__main__":
    unittest.main()
