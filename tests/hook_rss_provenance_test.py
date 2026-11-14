import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
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
    def make_hook_sources(self, root):
        source = root / "agent-hooks"
        source.mkdir(exist_ok=True)
        for name in provenance.HOOK_LINKS:
            (source / name).write_text("fixture\n")

    def test_scratch_hook_links_require_exact_targets(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "repo"
            source = root / "agent-hooks"
            links = Path(directory) / "hooks"
            source.mkdir(parents=True)
            links.mkdir()
            for name in ("block-dangerous-git.sh", "bootstrap-endpoint-path.sh", "literal-status-only.sh"):
                (source / name).write_text("fixture\n")
                (links / name).symlink_to(source / name)
            self.assertTrue(provenance.scratch_links_valid(root, links))
            (links / "literal-status-only.sh").unlink()
            (links / "literal-status-only.sh").symlink_to(source / "block-dangerous-git.sh")
            self.assertFalse(provenance.scratch_links_valid(root, links))

    def test_source_check_refuses_paths_missing_from_pinned_revision(self):
        with patch.object(provenance, "TRACKED", ("agent-hooks/literal-status-only.sh",)), \
                patch.object(provenance.subprocess, "run") as run:
            run.side_effect = lambda command, **_kwargs: SimpleNamespace(
                returncode=1 if command[1] == "cat-file" else 0
            )
            self.assertFalse(provenance.source_clean(Path("/scratch"), "a" * 40))

    def test_source_check_refuses_dirty_tracked_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "helper.sh").write_text("fixture\n")
            with patch.object(provenance, "TRACKED", ("helper.sh",)), \
                    patch.object(provenance.subprocess, "run") as run:
                run.side_effect = lambda command, **_kwargs: SimpleNamespace(
                    returncode=1 if command[1] == "diff" else 0
                )
                self.assertFalse(provenance.source_clean(root, "a" * 40))

    def test_real_untracked_and_dirty_candidate_are_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            template = root / "empty-template"
            template.mkdir()
            env = {"PATH": os.environ["PATH"], "HOME": str(root),
                   "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_SYSTEM": os.devnull}

            def git(*args):
                return subprocess.run(["git", "-c", f"init.templateDir={template}",
                                       "-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false",
                                       "-c", "user.name=Fixture", "-c", "user.email=fixture@example.com", *args],
                                      cwd=root, env=env, check=True, capture_output=True, text=True).stdout.strip()

            git("init", "--quiet")
            (root / "marker").write_text("base\n")
            git("add", "marker")
            git("commit", "--quiet", "-m", "fixture")
            base = git("rev-parse", "HEAD")
            helper = root / "helper.sh"
            helper.write_text("candidate\n")
            with patch.object(provenance, "TRACKED", ("helper.sh",)):
                self.assertFalse(provenance.source_clean(root, base))
                git("add", "helper.sh")
                git("commit", "--quiet", "-m", "fixture helper")
                candidate = git("rev-parse", "HEAD")
                self.assertTrue(provenance.source_clean(root, candidate))
                helper.write_text("changed\n")
                self.assertFalse(provenance.source_clean(root, candidate))

    def test_changed_source_or_link_invalidates_collection(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_hook_sources(root)
            harness = root / provenance.TRACKED[-1]
            harness.parent.mkdir(parents=True)
            harness.write_text("fixture")
            digest = hashlib.sha256(harness.read_bytes()).hexdigest()
            wait = root / "wait.log"
            wait.write_text(f"waited=1 pid={os.getppid()} slot=exclusive\n")

            def fake_run(argv, **_kwargs):
                Path(argv[-1]).write_text("")
                return SimpleNamespace(returncode=0, stdout=b"", stderr=b" 100 maximum resident set size\n")

            for changed in ("source", "link"):
                with self.subTest(changed=changed), patch.dict(os.environ, {"HEAVY_RUN_SLOT": "exclusive"}), \
                        patch.object(provenance, "source_clean", side_effect=[True, changed != "source"]), \
                        patch.object(provenance, "scratch_links_valid", side_effect=[True, changed != "link"]), \
                        patch.object(provenance, "installed_root", return_value=True), \
                        patch.object(provenance, "tool_snapshot", return_value=("fixture",)), \
                        patch.object(provenance.os, "getloadavg", return_value=(1.0, 1.0, 1.0)), \
                        patch.object(provenance.os, "cpu_count", return_value=4), \
                        patch.object(provenance.subprocess, "run", side_effect=fake_run):
                    receipt = provenance.collect(root, "a" * 40, digest, "b" * 32, wait, executing=harness)
                self.assertFalse(receipt["valid"])

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

    def test_parent_wait_fails_closed_for_missing_wrong_and_symlink(self):
        wait = getattr(provenance, "wait_expected_parent", lambda *_args, **_kwargs: False)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            parent = root / "parent"
            self.assertFalse(wait(parent, 123, timeout=0))
            parent.write_text("124\n")
            parent.chmod(0o600)
            self.assertFalse(wait(parent, 123, timeout=0))
            parent.write_text("123\n")
            self.assertTrue(wait(parent, 123, timeout=0))
            target = root / "target"
            parent.rename(target)
            parent.symlink_to(target)
            self.assertFalse(wait(parent, 123, timeout=0))

    def test_main_never_collects_when_parent_is_not_bound(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            with patch.dict(os.environ, {"HOOK_RSS_RUN_DIR": str(root), "DOTFILES_DIR": str(root)}), \
                    patch.object(provenance.Path, "cwd", return_value=root), \
                    patch.object(provenance, "installed_root", return_value=True), \
                    patch.object(provenance, "wait_expected_parent", return_value=False), \
                    patch.object(provenance, "collect", side_effect=AssertionError("collection ran")):
                with self.assertRaisesRegex(ValueError, "parent"):
                    provenance.main()

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
            self.make_hook_sources(root)
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
            self.make_hook_sources(root)
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
            self.make_hook_sources(root)
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
            self.make_hook_sources(root)
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
                    patch.object(provenance.os, "getloadavg", return_value=(938.0, 938.0, 938.0)), \
                    patch.object(provenance.os, "cpu_count", return_value=937), \
                    patch.object(provenance.subprocess, "run", side_effect=AssertionError("timed command ran")):
                receipt = provenance.collect(root, "a" * 40, digest, "b" * 32, wait, executing=harness)
            self.assertFalse(receipt["valid"])
            self.assertEqual(receipt["failure"], {"class": "load", "reason": "load-over-limit", "window": 0, "index": 0})
            self.assertNotIn("938.0", json.dumps(receipt))
            self.assertNotIn("937", json.dumps(receipt))

    def test_unavailable_cpu_count_stops_before_timed_commands(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_hook_sources(root)
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
                    patch.object(provenance.os, "getloadavg", return_value=(938.0, 938.0, 938.0)), \
                    patch.object(provenance.os, "cpu_count", return_value=None), \
                    patch.object(provenance.subprocess, "run", side_effect=AssertionError("timed command ran")):
                receipt = provenance.collect(root, "a" * 40, digest, "b" * 32, wait, executing=harness)
            self.assertFalse(receipt["valid"])
            self.assertEqual(receipt["failure"], {"class": "load", "reason": "cpu-unavailable", "window": 0, "index": 0})
            self.assertNotIn("938.0", json.dumps(receipt))
            self.assertNotIn("937", json.dumps(receipt))

    def test_post_window_load_preserves_earlier_failure(self):
        for sample_fails in (False, True):
            with self.subTest(sample_fails=sample_fails), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.make_hook_sources(root)
                harness = root / provenance.TRACKED[-1]
                harness.parent.mkdir(parents=True)
                harness.write_text("fixture")
                digest = hashlib.sha256(harness.read_bytes()).hexdigest()
                wait = root / "wait.log"
                wait.write_text(f"waited=1 pid={os.getppid()} slot=exclusive\n")
                def fake_run(argv, **_kwargs):
                    Path(argv[-1]).write_text("")
                    return SimpleNamespace(returncode=1 if sample_fails else 0, stdout=b"", stderr=b" 100 maximum resident set size\n")
                with patch.dict(os.environ, {"HEAVY_RUN_SLOT": "exclusive"}), \
                        patch.object(provenance, "source_clean", return_value=True), \
                        patch.object(provenance, "installed_root", return_value=True), \
                        patch.object(provenance, "tool_snapshot", return_value=("fixture",)), \
                        patch.object(provenance.os, "getloadavg", side_effect=[(1.0, 1.0, 1.0), (938.0, 938.0, 938.0)]), \
                        patch.object(provenance.os, "cpu_count", return_value=937), \
                        patch.object(provenance.subprocess, "run", side_effect=fake_run):
                    receipt = provenance.collect(root, "a" * 40, digest, "b" * 32, wait, executing=harness)
                expected = {"class": "exit", "window": 0, "index": 0} if sample_fails else {"class": "load", "reason": "load-over-limit", "window": 0, "index": 15}
                self.assertEqual(receipt["failure"], expected)
                self.assertNotIn("938.0", json.dumps(receipt))
                self.assertNotIn("937", json.dumps(receipt))

    def test_midrun_failure_retains_only_bounded_samples(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_hook_sources(root)
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
            self.make_hook_sources(root)
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
            self.make_hook_sources(root)
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
