import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).parent / "helpers"))
import hook_pair_binding as binding
import hook_pair_receipts as records
import hook_status_pairs as pairs
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
        intent = {"format": 1, "run_id": run_id, "candidate_revision": candidate,
                  "old_revision": old, "harness_revision": harness, "audit_sha256": hashlib.sha256(audit).hexdigest()}
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
        write_private_json(root / "launch.json", final)
        return run_id, candidate, old, harness, audit

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
            (root / "launch.json").rename(root / "launch.pending")
            self.assertIsNone(binding.verify_pair_link(root, *args, 123))
            self.assertIsNotNone(binding.verify_pair_link(root, *args, 123, final_name="launch.pending"))
            self.assertIsNone(binding.verify_pair_link(root, *args, 123, final_name="../launch.pending"))

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
            self.assertIsNone(binding.verify_pair_link(root, *args[:4], b"{}", 123))
            audit = json.loads(args[4])
            audit["launcher"] = "f" * 64
            self.assertIsNone(binding.verify_pair_link(root, *args[:4], json.dumps(audit).encode(), 123))

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
