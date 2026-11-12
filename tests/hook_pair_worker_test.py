import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).parent / "helpers"))
import hook_pair_worker as worker
import hook_source_snapshot_test as snapshot_tests
from hook_trusted_launch import write_private_json


class WorkerControls(unittest.TestCase):
    def fixture(self, root):
        run_id = "a" * 32
        run_dir = root / ".local/state/dotfiles/rust-migration" / ("hook-rss-" + run_id)
        run_dir.mkdir(parents=True)
        run_dir.chmod(0o700)
        env = {"HOME": str(root), "DOTFILES_DIR": str(root), "HEAVY_RUN_SLOT": "exclusive",
               "HEAVY_RUN_WAIT_LOG": str(run_dir / "wait.log"),
               "HOOK_PAIR_RUN_DIR": str(run_dir), "HOOK_PAIR_RUN_ID": run_id,
               "HOOK_PAIR_CANDIDATE": "b" * 40, "HOOK_PAIR_OLD": "c" * 40,
               "HOOK_PAIR_HARNESS_REVISION": "d" * 40, "HOOK_PAIR_AUDIT_SHA256": "e" * 64,
               "HOOK_PAIR_SOURCE_AUDIT_SHA256": "f" * 64, "HOOK_PAIR_MANIFEST_SHA256": "0" * 64}
        intent = {"format": 1, "run_id": run_id, "candidate_revision": env["HOOK_PAIR_CANDIDATE"],
                  "old_revision": env["HOOK_PAIR_OLD"], "harness_revision": env["HOOK_PAIR_HARNESS_REVISION"],
                  "audit_sha256": env["HOOK_PAIR_AUDIT_SHA256"],
                  "source_audit_sha256": env["HOOK_PAIR_SOURCE_AUDIT_SHA256"],
                  "source_manifest_sha256": env["HOOK_PAIR_MANIFEST_SHA256"]}
        write_private_json(run_dir / "intent.json", intent)
        for name, text in (("parent", "123\n"), ("wait.log", "waited=1 pid=123 slot=exclusive\n")):
            p = run_dir / name
            p.write_text(text)
            p.chmod(0o600)
        return run_dir, env

    def test_exact_private_intent_and_exclusive_admission(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            run_dir, env = self.fixture(root)
            self.assertTrue(worker.identity_ok(root, run_dir, env, 123))
            self.assertFalse(worker.identity_ok(root, run_dir, env, 124))
            self.assertFalse(worker.identity_ok(root, run_dir, {**env, "HEAVY_RUN_SLOT": "shared"}, 123))
            self.assertFalse(worker.identity_ok(root, run_dir, {**env, "HEAVY_RUN_WAIT_LOG": "/wrong"}, 123))
            self.assertFalse(worker.identity_ok(root, run_dir, {k: v for k, v in env.items() if k != "HEAVY_RUN_WAIT_LOG"}, 123))
            self.assertFalse(worker.identity_ok(root, run_dir, {**env, "HOOK_PAIR_CANDIDATE": "f" * 40}, 123))
            self.assertFalse(worker.identity_ok(root, run_dir, {**env, "HOOK_PAIR_HARNESS_REVISION": "f" * 40}, 123))
            self.assertFalse(worker.identity_ok(root, run_dir, {**env, "HOOK_PAIR_SOURCE_AUDIT_SHA256": "1" * 64}, 123))
            self.assertFalse(worker.identity_ok(root, run_dir, {**env, "HOOK_PAIR_MANIFEST_SHA256": "1" * 64}, 123))
            self.assertFalse(worker.identity_ok(root, run_dir, {**env, "HOOK_PAIR_OLD": "f" * 40}, 123))
            (run_dir / "wait.log").write_text("pid=123 slot=exclusive\npid=123 slot=exclusive\n")
            self.assertFalse(worker.identity_ok(root, run_dir, env, 123))

    def test_changed_or_ambiguous_intent_never_qualifies(self):
        for mode in ("wrong_digest", "duplicate", "bool_format", "mode"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                run_dir, env = self.fixture(root)
                path = run_dir / "intent.json"
                data = json.loads(path.read_text())
                if mode == "wrong_digest":
                    data["audit_sha256"] = "f" * 64
                    path.write_text(json.dumps(data))
                elif mode == "duplicate":
                    path.write_text('{"format":1,' + path.read_text()[1:])
                elif mode == "bool_format":
                    data["format"] = True
                    path.write_text(json.dumps(data))
                else:
                    path.chmod(0o644)
                self.assertFalse(worker.identity_ok(root, run_dir, env, 123))

    def test_parent_and_wait_files_require_private_regular_files(self):
        for name in ("parent", "wait.log"):
            for mode in ("symlink", "permissions"):
                with self.subTest(name=name, mode=mode), tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    run_dir, env = self.fixture(root)
                    path = run_dir / name
                    if mode == "permissions":
                        path.chmod(0o644)
                    else:
                        target = run_dir / (name + ".target")
                        path.rename(target)
                        path.symlink_to(target)
                    self.assertFalse(worker.identity_ok(root, run_dir, env, 123))

    def test_materialization_binds_old_and_candidate_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def fetch(revision, path):
                content = (revision if path.endswith("block-dangerous-git.sh") else "shared").encode()
                mode = "100755" if path.endswith(".sh") and not path.startswith("lib/") else "100644"
                return mode, content
            fixture = worker.materialize(root, "old", "new", fetch)
            self.assertTrue(worker.fixture_unchanged(fixture))
            (root / "new/hooks/literal-status-only.sh").unlink()
            os.symlink("../source/block-dangerous-git.sh", root / "new/hooks/literal-status-only.sh")
            self.assertFalse(worker.fixture_unchanged(fixture))

    def test_verified_snapshot_is_required_before_fixture_writes(self):
        for mutation in ("none", "digest", "manifest", "revision", "changed", "missing", "mode", "scratch"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                run_dir, env = self.fixture(root)
                source = run_dir / "source"
                source.mkdir(mode=0o700)
                raw = snapshot_tests.SnapshotControls().fixture(source)
                env.update({"HOOK_PAIR_OLD": "b" * 40, "HOOK_PAIR_CANDIDATE": "c" * 40,
                            "HOOK_PAIR_MANIFEST_SHA256": hashlib.sha256(raw).hexdigest()})
                intent_path = run_dir / "intent.json"
                intent = json.loads(intent_path.read_text())
                intent.update({"old_revision": env["HOOK_PAIR_OLD"],
                               "candidate_revision": env["HOOK_PAIR_CANDIDATE"],
                               "source_manifest_sha256": env["HOOK_PAIR_MANIFEST_SHA256"]})
                intent_path.write_text(json.dumps(intent))
                scratch = run_dir / "scratch"
                scratch.mkdir(mode=0o700)
                if mutation == "digest": env["HOOK_PAIR_MANIFEST_SHA256"] = "1" * 64
                elif mutation == "manifest": raw += b" "
                elif mutation == "scratch":
                    scratch = run_dir / "other"
                    scratch.mkdir(mode=0o700)
                elif mutation == "revision": env["HOOK_PAIR_OLD"] = "f" * 40
                elif mutation == "changed": (source / "000.src").write_bytes(b"changed")
                elif mutation == "missing": (source / "000.src").unlink()
                elif mutation == "mode": (source / "000.src").chmod(0o644)
                fixture = worker.materialize_verified(root, run_dir, scratch, env, 123, raw)
                if mutation == "none":
                    self.assertIsNotNone(fixture)
                    self.assertEqual((scratch / "old/source/block-dangerous-git.sh").read_bytes(), b"hook-old")
                    self.assertEqual((scratch / "new/source/block-dangerous-git.sh").read_bytes(), b"hook-new")
                    for side in ("old", "new"):
                        for name in ("block-dangerous-git.sh", "bootstrap-endpoint-path.sh", "plain-document-write.jq"):
                            self.assertEqual(os.readlink(scratch / side / "hooks" / name), "../source/" + name)
                            expected = ("hook-" + side if name == "block-dangerous-git.sh" else
                                        "shared-agent-hooks/" + name).encode()
                            self.assertEqual((scratch / side / "source" / name).read_bytes(), expected)
                    self.assertEqual((scratch / "new/source/literal-status-only.sh").read_bytes(),
                                     b"shared-agent-hooks/literal-status-only.sh")
                    self.assertTrue(worker.fixture_unchanged(fixture))
                    (scratch / "new/source/block-dangerous-git.sh").write_bytes(b"mutated")
                    self.assertFalse(worker.fixture_unchanged(fixture))
                else:
                    self.assertIsNone(fixture)
                    self.assertEqual(list(scratch.iterdir()), [])

    def test_changed_shared_helper_stops_before_materialization(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def fetch(revision, path):
                value = revision if path.endswith("bootstrap-endpoint-path.sh") else "same"
                mode = "100755" if path.endswith(".sh") and not path.startswith("lib/") else "100644"
                return mode, value.encode()
            with self.assertRaises(ValueError):
                worker.materialize(root, "old", "new", fetch)
            self.assertEqual(list(root.iterdir()), [])

    def test_preexisting_scratch_symlink_cannot_redirect_writes(self):
        with tempfile.TemporaryDirectory() as directory:
            outer = Path(directory)
            scratch, external = outer / "scratch", outer / "external"
            scratch.mkdir(mode=0o700)
            external.mkdir()
            (scratch / "old").symlink_to(external)
            def fetch(revision, path):
                mode = "100755" if path.endswith(".sh") and not path.startswith("lib/") else "100644"
                return mode, b"fixture"
            with self.assertRaises(ValueError):
                worker.materialize(scratch, "old", "new", fetch)
            self.assertEqual(list(external.iterdir()), [])



if __name__ == "__main__":
    unittest.main()
