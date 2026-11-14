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
import hook_pair_binding as binding
import hook_fake_mapping
import hook_pair_receipts as records
import hook_status_pairs as pairs
import hook_source_snapshot as snapshots
from hook_trusted_launch import write_private_json


class BindingControls(unittest.TestCase):
    def reseal(self, root, name, key):
        final_path = root / "launch.json"
        final = json.loads(final_path.read_text())
        final[key] = hashlib.sha256((root / name).read_bytes()).hexdigest()
        final_path.write_text(json.dumps(final))

    def build(self, root, candidate_ns=75):
        root.chmod(0o700)
        run_id, candidate, old, harness = "a" * 32, "b" * 40, "c" * 40, "d" * 40
        audit = json.dumps(dict.fromkeys(("launcher", "harness", "perl", "BASH_ENV", "ENV", "wrapper"), "e" * 64)).encode()
        sink = records.AttemptSink(root, run_id)
        result = pairs.capture(lambda _case, side: (100 if side == "old" else candidate_ns, 0, b"", b""),
                               lambda: True, lambda: True, sink.record)
        source = root / "source"
        source.mkdir(mode=0o700)
        rows = []
        for index, (side, path, mode) in enumerate(snapshots.EXPECTED):
            data = ("hook-" + side if path == snapshots.HOOK else "shared-" + path).encode()
            name = f"{index:03}.src"
            file = source / name
            file.write_bytes(data)
            file.chmod(0o600)
            oid = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data, usedforsecurity=False).hexdigest()
            rows.append({"side": side, "path": path, "mode": mode, "file": name,
                         "blob": oid, "sha256": hashlib.sha256(data).hexdigest()})
        manifest = {"format": 1, "run_id": run_id, "old_revision": old,
                    "candidate_revision": candidate, "files": rows}
        source_manifest = json.dumps(manifest, sort_keys=True).encode()
        (source / "manifest.json").write_bytes(source_manifest)
        (source / "manifest.json").chmod(0o600)
        source_audit = json.dumps({"format": 1, "run_id": run_id, "old_revision": old,
                                   "candidate_revision": candidate, "manifest_sha256": hashlib.sha256(source_manifest).hexdigest(),
                                   "local_filesystems": True, "roots": {"old": {"path": "/scratch/old", "dev": 1, "ino": 2},
                                                                          "new": {"path": "/scratch/new", "dev": 1, "ino": 3}}}).encode()
        mapping_archive = hook_fake_mapping.archive(run_id, old, candidate, source_manifest)
        mapping_digest = hashlib.sha256(mapping_archive).hexdigest()
        (root / "mapping.json").write_bytes(mapping_archive)
        (root / "mapping.json").chmod(0o600)
        intent = {"format": 1, "run_id": run_id, "candidate_revision": candidate,
                  "old_revision": old, "harness_revision": harness, "audit_sha256": hashlib.sha256(audit).hexdigest(),
                  "source_audit_sha256": hashlib.sha256(source_audit).hexdigest(),
                  "source_manifest_sha256": hashlib.sha256(source_manifest).hexdigest(),
                  "mapping_sha256": mapping_digest}
        write_private_json(root / "intent.json", intent)
        for name, content in (("parent", "123\n"), ("wait.log", "waited=1 pid=123 slot=exclusive\n")):
            path = root / name
            path.write_text(content)
            path.chmod(0o600)
        receipt = {"format": 1, "run_id": run_id, "valid": True, "passed": result["passed"],
                   "median_ratios": result["median_ratios"], "flags": dict.fromkeys(pairs.FLAGS, True), "failure": None}
        write_private_json(root / "receipt.json", receipt)
        digest = lambda name: hashlib.sha256((root / name).read_bytes()).hexdigest()
        attempt_digest = hashlib.sha256(json.dumps(result["attempts"], sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        final = {"format": 1, "intent_sha256": digest("intent.json"), "parent_pid": 123,
                 "parent_sha256": digest("parent"), "wait_sha256": digest("wait.log"),
                 "receipt_sha256": digest("receipt.json"), "attempts_sha256": attempt_digest, "verdict": "qualified"}
        write_private_json(root / "launch.pending", final)
        os.link(root / "launch.pending", root / "launch.json")
        return run_id, candidate, old, harness, audit, source_audit, source_manifest, mapping_archive, mapping_digest, hashlib.sha256(source_audit).hexdigest()

    def test_independent_binding_and_threshold(self):
        for candidate_ns, expected in ((75, True), (81, False)):
            with self.subTest(candidate_ns=candidate_ns), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                args = self.build(root, candidate_ns)
                result = binding.verify_pair_link(root, *args, 123)
                self.assertIsNotNone(result)
                self.assertEqual(result["passed"], expected)
                self.assertEqual(result["median_ratios"][pairs.CASES[0]], candidate_ns / 100)

    def test_wrong_expected_identity_or_changed_record_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            args = self.build(root)
            self.assertIsNone(binding.verify_pair_link(root, *args, 124))
            wrong = ("f" * 32, *args[1:])
            self.assertIsNone(binding.verify_pair_link(root, *wrong, 123))
            target = root / "attempts" / "001.json"
            data = json.loads(target.read_text())
            data["attempt"]["elapsed_ns"] += 1
            target.write_text(json.dumps(data))
            self.assertIsNone(binding.verify_pair_link(root, *args, 123))

    def test_pending_final_can_be_verified_before_publication(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            args = self.build(root)
            (root / "launch.json").unlink()
            self.assertIsNone(binding.verify_pair_link(root, *args, 123))
            self.assertIsNotNone(binding.verify_pair_link(root, *args, 123, final_name="launch.pending"))
            self.assertIsNone(binding.verify_pair_link(root, *args, 123, final_name="../launch.pending"))

    def test_missing_extra_or_unsafe_publication_link_never_qualifies(self):
        for mutation in ("missing_pending", "different_inode", "extra_link", "symlink", "mode", "fifo_pending", "fifo_final"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                args = self.build(root)
                pending, final = root / "launch.pending", root / "launch.json"
                if mutation == "missing_pending": pending.unlink()
                elif mutation == "different_inode":
                    content = pending.read_bytes()
                    pending.unlink()
                    pending.write_bytes(content)
                    pending.chmod(0o600)
                elif mutation == "extra_link": os.link(final, root / "extra-link")
                elif mutation == "symlink":
                    final.unlink()
                    final.symlink_to(pending)
                elif mutation in ("fifo_pending", "fifo_final"):
                    target = pending if mutation == "fifo_pending" else final
                    target.unlink()
                    os.mkfifo(target, 0o600)
                else: final.chmod(0o644)
                self.assertIsNone(binding.verify_pair_link(root, *args, 123))

    def test_published_record_opens_are_nonblocking(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            pending, final = root / "launch.pending", root / "launch.json"
            pending.write_bytes(b"fixture")
            pending.chmod(0o600)
            os.link(pending, final)
            original_open = os.open
            def checked_open(path, flags, *args, **kwargs):
                self.assertTrue(flags & os.O_NONBLOCK)
                return original_open(path, flags, *args, **kwargs)
            with patch.object(binding.os, "open", side_effect=checked_open):
                self.assertEqual(binding.read_published_pair(root), b"fixture")

    def test_missing_changed_or_wrong_snapshot_never_qualifies(self):
        for mutation in ("missing", "changed", "wrong_manifest"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                args = self.build(root)
                if mutation == "missing":
                    (root / "source/000.src").unlink()
                elif mutation == "changed":
                    (root / "source/000.src").write_bytes(b"changed")
                else:
                    args = (*args[:6], args[6] + b" ", *args[7:])
                self.assertIsNone(binding.verify_pair_link(root, *args, 123))

    def test_snapshot_changed_during_verification_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            args = self.build(root)
            original = binding.read_attempts
            def change_after_read(*read_args):
                result = original(*read_args)
                (root / "source/000.src").write_bytes(b"changed")
                return result
            with patch.object(binding, "read_attempts", side_effect=change_after_read):
                self.assertIsNone(binding.verify_pair_link(root, *args, 123))

    def test_missing_or_false_flags_never_qualify(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            args = self.build(root)
            receipt = json.loads((root / "receipt.json").read_text())
            receipt["flags"]["source"] = False
            (root / "receipt.json").write_text(json.dumps(receipt))
            final = json.loads((root / "launch.json").read_text())
            final["receipt_sha256"] = hashlib.sha256((root / "receipt.json").read_bytes()).hexdigest()
            (root / "launch.json").write_text(json.dumps(final))
            self.assertIsNone(binding.verify_pair_link(root, *args, 123))

    def test_independently_wrong_revisions_or_audit_never_qualify(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            args = self.build(root)
            for position in (1, 2, 3):
                wrong = list(args)
                wrong[position] = "f" * 40
                self.assertIsNone(binding.verify_pair_link(root, *wrong, 123))
            self.assertIsNone(binding.verify_pair_link(root, *args[:4], b"{}", *args[5:], 123))
            audit = json.loads(args[4])
            audit["launcher"] = "f" * 64
            self.assertIsNone(binding.verify_pair_link(root, *args[:4], json.dumps(audit).encode(), *args[5:], 123))
            source_audit = json.loads(args[5])
            source_audit["roots"]["old"]["ino"] += 1
            self.assertIsNone(binding.verify_pair_link(root, *args[:5], json.dumps(source_audit).encode(), *args[6:], 123))

    def test_missing_changed_or_wrong_mapping_never_qualifies(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            args = self.build(root)
            self.assertIsNotNone(binding.verify_pair_link(root, *args, 123))
            (root / "mapping.json").unlink()
            self.assertIsNone(binding.verify_pair_link(root, *args, 123))
            (root / "mapping.json").write_bytes(args[7])
            (root / "mapping.json").chmod(0o600)
            for archive, digest in ((b"{}", args[8]), (args[7], "0" * 64),
                                    (args[7] + b" ", hashlib.sha256(args[7] + b" ").hexdigest())):
                self.assertIsNone(binding.verify_pair_link(root, *args[:7], archive, digest, args[9], 123))

    def test_resealed_intent_cannot_replace_independent_audit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            args = self.build(root)
            changed_audit = json.loads(args[5])
            changed_audit["roots"]["old"]["ino"] += 1
            changed_bytes = json.dumps(changed_audit).encode()
            intent_path = root / "intent.json"
            intent = json.loads(intent_path.read_text())
            intent["source_audit_sha256"] = hashlib.sha256(changed_bytes).hexdigest()
            intent_path.write_text(json.dumps(intent))
            self.reseal(root, "intent.json", "intent_sha256")
            self.assertIsNone(binding.verify_pair_link(root, *args[:5], changed_bytes, *args[6:], 123))

    def test_changed_or_duplicated_admission_never_qualifies(self):
        for wait in ("", "waited=1 pid=123 slot=shared\n", "pid=123 slot=exclusive\npid=123 slot=exclusive\n"):
            with self.subTest(wait=wait), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                args = self.build(root)
                (root / "wait.log").write_text(wait)
                self.reseal(root, "wait.log", "wait_sha256")
                self.assertIsNone(binding.verify_pair_link(root, *args, 123))

    def test_forged_receipt_or_ambiguous_intent_never_qualifies(self):
        for mutation in ("median", "passed", "flag_type", "duplicate_intent", "bool_format"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                args = self.build(root, candidate_ns=81)
                if mutation == "duplicate_intent":
                    path = root / "intent.json"
                    path.write_text('{"format":1,' + path.read_text()[1:])
                    self.reseal(root, "intent.json", "intent_sha256")
                else:
                    path = root / "receipt.json"
                    receipt = json.loads(path.read_text())
                    if mutation == "median":
                        receipt["median_ratios"][pairs.CASES[0]] = 0.5
                    elif mutation == "passed":
                        receipt["passed"] = True
                    elif mutation == "flag_type":
                        receipt["flags"]["source"] = 1
                    else:
                        receipt["format"] = True
                    path.write_text(json.dumps(receipt))
                    self.reseal(root, "receipt.json", "receipt_sha256")
                self.assertIsNone(binding.verify_pair_link(root, *args, 123))


if __name__ == "__main__":
    unittest.main()
