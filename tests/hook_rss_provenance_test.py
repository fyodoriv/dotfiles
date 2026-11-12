import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

MODULE = Path(__file__).parent / "helpers/hook_rss_provenance.py"
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("hook_rss_provenance", MODULE)
provenance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(provenance)


class ReceiptControls(unittest.TestCase):
    def test_private_expected_parent_must_match(self):
        with tempfile.TemporaryDirectory() as directory:
            parent_file = Path(directory) / "parent"
            parent_file.write_text("123\n")
            parent_file.chmod(0o600)
            verify = getattr(provenance, "expected_parent_valid", lambda *_: False)
            self.assertTrue(verify(parent_file, 123))
            self.assertFalse(verify(parent_file, 124))
            parent_file.chmod(0o644)
            self.assertFalse(verify(parent_file, 123))

    def test_admission_requires_one_matching_exclusive_parent(self):
        line = "waited=1 pid=123 slot=exclusive\n"
        self.assertTrue(provenance.admission_valid(line, 123, "exclusive"))
        self.assertFalse(provenance.admission_valid(line, 124, "exclusive"))
        self.assertFalse(provenance.admission_valid(line, 123, "1"))
        self.assertFalse(provenance.admission_valid(line + line, 123, "exclusive"))
        self.assertFalse(provenance.admission_valid("", 123, "exclusive"))

    def test_receipt_requires_complete_positive_samples_and_valid_flags(self):
        flags = dict.fromkeys(("admission", "source", "harness", "tools", "output"), True)
        windows = [[100] * 15, [100] * 15]
        self.assertTrue(provenance.summary(windows, flags, [1] * 4, 4)["aa_pass"])
        self.assertFalse(provenance.summary([[100] * 14, [100] * 15], flags, [1] * 4, 4)["valid"])
        self.assertFalse(provenance.summary([[0] * 15, [100] * 15], flags, [1] * 4, 4)["valid"])
        self.assertFalse(provenance.summary(windows, {**flags, "tools": False}, [1] * 4, 4)["valid"])
        self.assertFalse(provenance.summary(windows, flags, [5] * 4, 4)["valid"])
        self.assertFalse(provenance.summary([[100] * 15, [110] * 15], flags, [1] * 4, 4)["aa_pass"])
        safe = provenance.summary(windows, {**flags, "private": "PRIVATE_CANARY_123"}, [1] * 4, 4)
        self.assertNotIn("PRIVATE_CANARY_123", json.dumps(safe))

    def test_bad_admission_stops_before_any_timed_command(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            harness = root / provenance.TRACKED[-1]
            harness.parent.mkdir(parents=True)
            harness.write_text("fixture")
            digest = hashlib.sha256(harness.read_bytes()).hexdigest()
            wait = root / "wait.log"
            wait.write_text("waited=1 pid=999999 slot=exclusive\n")
            with patch.dict(os.environ, {"HEAVY_RUN_SLOT": "exclusive"}), \
                    patch.object(provenance, "source_clean", return_value=True), \
                    patch.object(provenance, "tool_snapshot", return_value=("fixture",)), \
                    patch.object(provenance.subprocess, "run", side_effect=AssertionError("timed command ran")):
                result = provenance.collect(root, "a" * 40, digest, "b" * 32, wait, executing=harness)
            self.assertFalse(result["valid"])
            self.assertEqual(result["samples"], [])

    def test_harness_path_and_digest_must_both_match(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original, other = root / "original", root / "other"
            original.write_text("fixture")
            other.write_text("fixture")
            digest = hashlib.sha256(original.read_bytes()).hexdigest()
            self.assertTrue(provenance.harness_matches(original, original, digest))
            self.assertFalse(provenance.harness_matches(other, original, digest))
            self.assertFalse(provenance.harness_matches(original, original, "0" * 64))

    def test_partial_samples_survive_without_private_fields(self):
        flags = dict.fromkeys(("admission", "source", "harness", "tools", "output"), True)
        receipt = provenance.summary([[100, 101]], flags, [1, 1], 4)
        self.assertFalse(receipt["valid"])
        self.assertEqual(receipt["samples"], [[100, 101]])
        self.assertEqual(receipt["medians"], [])
        self.assertNotIn("PRIVATE_CANARY_123", json.dumps(receipt))

    def test_bad_source_or_harness_stops_before_timed_commands(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            harness = root / provenance.TRACKED[-1]
            harness.parent.mkdir(parents=True)
            harness.write_text("fixture")
            digest = hashlib.sha256(harness.read_bytes()).hexdigest()
            wait = root / "wait.log"
            wait.write_text(f"waited=1 pid={os.getppid()} slot=exclusive\n")
            for source_ok, selected_digest in ((False, digest), (True, "0" * 64)):
                with patch.dict(os.environ, {"HEAVY_RUN_SLOT": "exclusive"}), \
                        patch.object(provenance, "source_clean", return_value=source_ok), \
                        patch.object(provenance, "tool_snapshot", return_value=("fixture",)), \
                        patch.object(provenance.subprocess, "run", side_effect=AssertionError("timed command ran")):
                    receipt = provenance.collect(root, "a" * 40, selected_digest, "b" * 32, wait, executing=harness)
                self.assertFalse(receipt["valid"])
                self.assertEqual(receipt["samples"], [])

    def test_unknown_tools_or_wrong_executing_path_never_time(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            harness = root / provenance.TRACKED[-1]
            harness.parent.mkdir(parents=True)
            harness.write_text("fixture")
            digest = hashlib.sha256(harness.read_bytes()).hexdigest()
            wait = root / "wait.log"
            wait.write_text(f"waited=1 pid={os.getppid()} slot=exclusive\n")
            with patch.dict(os.environ, {"HEAVY_RUN_SLOT": "exclusive"}), \
                    patch.object(provenance, "source_clean", return_value=True), \
                    patch.object(provenance, "tool_snapshot", return_value=("fixture",)), \
                    patch.object(provenance.subprocess, "run", side_effect=AssertionError("timed command ran")):
                receipt = provenance.collect(root, "a" * 40, digest, "b" * 32, wait)
            self.assertFalse(receipt["valid"])
            with patch.dict(os.environ, {"HEAVY_RUN_SLOT": "exclusive"}), \
                    patch.object(provenance, "source_clean", return_value=True), \
                    patch.object(provenance, "tool_snapshot", side_effect=ValueError("unknown")), \
                    patch.object(provenance.subprocess, "run", side_effect=AssertionError("timed command ran")):
                with self.assertRaises(ValueError):
                    provenance.collect(root, "a" * 40, digest, "b" * 32, wait, executing=harness)

    def test_high_load_stops_before_timed_commands(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            harness = root / provenance.TRACKED[-1]
            harness.parent.mkdir(parents=True)
            harness.write_text("fixture")
            digest = hashlib.sha256(harness.read_bytes()).hexdigest()
            wait = root / "wait.log"
            wait.write_text(f"waited=1 pid={os.getppid()} slot=exclusive\n")
            with patch.dict(os.environ, {"HEAVY_RUN_SLOT": "exclusive"}), \
                    patch.object(provenance, "source_clean", return_value=True), \
                    patch.object(provenance, "installed_root", return_value=True), \
                    patch.object(provenance, "tool_snapshot", return_value=("fixture",)), \
                    patch.object(provenance.os, "getloadavg", return_value=(5.0, 5.0, 5.0)), \
                    patch.object(provenance.os, "cpu_count", return_value=4), \
                    patch.object(provenance.subprocess, "run", side_effect=AssertionError("timed command ran")):
                receipt = provenance.collect(root, "a" * 40, digest, "b" * 32, wait, executing=harness)
            self.assertFalse(receipt["valid"])
            self.assertEqual(receipt["failure"], {"class": "load", "window": 0, "index": 0})

    def test_midrun_failure_retains_only_bounded_samples(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            harness = root / provenance.TRACKED[-1]
            harness.parent.mkdir(parents=True)
            harness.write_text("fixture")
            digest = hashlib.sha256(harness.read_bytes()).hexdigest()
            wait = root / "wait.log"
            wait.write_text(f"waited=1 pid={os.getppid()} slot=exclusive\n")
            calls = []

            def fake_run(argv, **_kwargs):
                calls.append(1)
                Path(argv[-1]).write_text("")
                return SimpleNamespace(returncode=1 if len(calls) == 3 else 0, stdout=b"",
                                       stderr=b" 100 maximum resident set size\n")

            with patch.dict(os.environ, {"HEAVY_RUN_SLOT": "exclusive"}), \
                    patch.object(provenance, "source_clean", return_value=True), \
                    patch.object(provenance, "installed_root", return_value=True), \
                    patch.object(provenance, "tool_snapshot", return_value=("fixture",)), \
                    patch.object(provenance.os, "getloadavg", return_value=(1.0, 1.0, 1.0)), \
                    patch.object(provenance.os, "cpu_count", return_value=4), \
                    patch.object(provenance.subprocess, "run", side_effect=fake_run):
                receipt = provenance.collect(root, "a" * 40, digest, "b" * 32, wait, executing=harness)
            self.assertFalse(receipt["valid"])
            self.assertEqual(receipt["samples"], [[100, 100]])
            self.assertEqual(receipt["failure"], {"class": "exit", "window": 0, "index": 2})

    def test_startup_chain_requires_stable_files_and_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            one, two = Path(directory) / "one", Path(directory) / "two"
            one.write_text("first")
            two.write_text("second")
            environ = {"BASH_ENV": str(one), "ENV": str(two),
                       "HOOK_RSS_BASH_ENV_SHA256": hashlib.sha256(one.read_bytes()).hexdigest(),
                       "HOOK_RSS_ENV_SHA256": hashlib.sha256(two.read_bytes()).hexdigest()}
            decoded = [str(one), str(two), "path", str(one), str(two)]
            self.assertTrue(provenance.startup_chain_valid(decoded, environ))
            self.assertFalse(provenance.startup_chain_valid(decoded[:3] + [str(two), str(two)], environ))
            one.write_text("changed")
            self.assertFalse(provenance.startup_chain_valid(decoded, environ))

    def test_exceptions_preserve_partial_and_completed_samples(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            harness = root / provenance.TRACKED[-1]
            harness.parent.mkdir(parents=True)
            harness.write_text("fixture")
            digest = hashlib.sha256(harness.read_bytes()).hexdigest()
            wait = root / "wait.log"
            wait.write_text(f"waited=1 pid={os.getppid()} slot=exclusive\n")
            for during in (True, False):
                calls = []

                def fake_run(argv, **_kwargs):
                    calls.append(1)
                    if during and len(calls) == 3:
                        raise OSError("private fixture")
                    Path(argv[-1]).write_text("")
                    return SimpleNamespace(returncode=0, stdout=b"", stderr=b" 100 maximum resident set size\n")

                snapshots = [("before",), ("after",)] if during else [("before",), ValueError("private fixture")]
                with patch.dict(os.environ, {"HEAVY_RUN_SLOT": "exclusive"}), \
                        patch.object(provenance, "source_clean", return_value=True), \
                        patch.object(provenance, "installed_root", return_value=True), \
                        patch.object(provenance, "tool_snapshot", side_effect=snapshots), \
                        patch.object(provenance.os, "getloadavg", return_value=(1.0, 1.0, 1.0)), \
                        patch.object(provenance.os, "cpu_count", return_value=4), \
                        patch.object(provenance.subprocess, "run", side_effect=fake_run):
                    receipt = provenance.collect(root, "a" * 40, digest, "b" * 32, wait, executing=harness)
                self.assertFalse(receipt["valid"])
                self.assertEqual(receipt["samples"], [[100, 100]] if during else [[100] * 15, [100] * 15])
                self.assertEqual(receipt["failure"]["class"], "observation" if during else "postflight")
                self.assertNotIn("private fixture", json.dumps(receipt))

    def test_changed_tools_invalidate_complete_samples(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            harness = root / provenance.TRACKED[-1]
            harness.parent.mkdir(parents=True)
            harness.write_text("fixture")
            digest = hashlib.sha256(harness.read_bytes()).hexdigest()
            wait = root / "wait.log"
            wait.write_text(f"waited=1 pid={os.getppid()} slot=exclusive\n")

            def fake_run(argv, **_kwargs):
                Path(argv[-1]).write_text("")
                return SimpleNamespace(returncode=0, stdout=b"", stderr=b" 100 maximum resident set size\n")

            with patch.dict(os.environ, {"HEAVY_RUN_SLOT": "exclusive"}), \
                    patch.object(provenance, "source_clean", return_value=True), \
                    patch.object(provenance, "installed_root", return_value=True), \
                    patch.object(provenance, "tool_snapshot", side_effect=[("before",), ("after",)]), \
                    patch.object(provenance.os, "getloadavg", return_value=(1.0, 1.0, 1.0)), \
                    patch.object(provenance.os, "cpu_count", return_value=4), \
                    patch.object(provenance.subprocess, "run", side_effect=fake_run):
                receipt = provenance.collect(root, "a" * 40, digest, "b" * 32, wait, executing=harness)
            self.assertFalse(receipt["valid"])
            self.assertFalse(receipt["flags"]["tools"])


if __name__ == "__main__":
    unittest.main()
