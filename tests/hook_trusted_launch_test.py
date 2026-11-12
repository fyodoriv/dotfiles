import importlib.util
import hashlib
import os
from pathlib import Path
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
MODULE = Path(__file__).parent / "helpers/hook_trusted_launch.py"


class LaunchControls(unittest.TestCase):
    def test_queue_overrides_are_rejected_before_launch(self):
        if MODULE.exists():
            spec = importlib.util.spec_from_file_location("trusted_launch", MODULE)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            safe = module.safe_queue_environment
        else:
            safe = lambda _env: False
        self.assertTrue(safe({"HOME": "/fixture"}))
        for name in ("HEAVY_RUN_HELD", "HEAVY_RUN_SLOT", "HEAVY_RUN_DIR", "HEAVY_RUN_PROBE"):
            with self.subTest(name=name):
                self.assertFalse(safe({name: "fixture"}))

    def test_expected_file_digest_rejects_changes_and_missing_files(self):
        spec = importlib.util.spec_from_file_location("trusted_launch", MODULE)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        matches = getattr(module, "matches_digest", lambda *_: False)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture"
            path.write_bytes(b"fixture")
            digest = hashlib.sha256(b"fixture").hexdigest()
            self.assertTrue(matches(path, digest))
            self.assertFalse(matches(path, "0" * 64))
            self.assertFalse(matches(Path(directory) / "missing", digest))
            path.write_bytes(b"changed")
            self.assertFalse(matches(path, digest))

    def test_private_log_is_new_empty_and_not_reused(self):
        spec = importlib.util.spec_from_file_location("trusted_launch", MODULE)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        create = getattr(module, "create_private_log", lambda *_: None)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            log = create(root)
            self.assertEqual(log, root / "wait.log")
            self.assertEqual(log.read_bytes(), b"")
            self.assertEqual(log.stat().st_mode & 0o777, 0o600)
            with self.assertRaises(FileExistsError):
                create(root)

    def test_synthetic_launcher_binds_parent_before_child_runs(self):
        spec = importlib.util.spec_from_file_location("trusted_launch", MODULE)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        spawn = getattr(module, "spawn_with_parent", lambda *_: None)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            launcher = root / "launcher"
            launcher.write_text("#!" + sys.executable + "\n" +
                "import os, subprocess, sys\n"
                "with open(os.environ['HEAVY_RUN_WAIT_LOG'], 'a') as log:\n"
                " log.write('pid=%s slot=%s\\n' % (os.getpid(), os.environ.get('SYNTHETIC_SLOT', 'exclusive')))\n"
                "os.environ['HEAVY_RUN_SLOT'] = 'exclusive'\n"
                "sys.exit(subprocess.call(sys.argv[2:]))\n")
            launcher.chmod(0o700)
            child = root / "child.py"
            child.write_text("import importlib.util, os, pathlib, time\n"
                "spec=importlib.util.spec_from_file_location('p', os.environ['FIXTURE_LIB'])\n"
                "p=importlib.util.module_from_spec(spec); spec.loader.exec_module(p)\n"
                "root=pathlib.Path(os.environ['FIXTURE_ROOT'])\n"
                "deadline=time.monotonic()+3\n"
                "while not p.expected_parent_valid(root/'parent', os.getppid()) and time.monotonic()<deadline: time.sleep(.01)\n"
                "if p.expected_parent_valid(root/'parent', os.getppid()) and p.admission_valid((root/'wait.log').read_text(), os.getppid(), os.environ['HEAVY_RUN_SLOT']): (root/'marker').write_text('started')\n")
            log = root / "wait.log"
            log.write_text("")
            log.chmod(0o600)
            env = {**os.environ, "PYTHONDONTWRITEBYTECODE": "1", "HEAVY_RUN_WAIT_LOG": str(log), "FIXTURE_ROOT": str(root),
                   "FIXTURE_LIB": str(Path(__file__).parent / "helpers/hook_rss_provenance.py")}
            process = spawn(launcher, [sys.executable, str(child)], root, env)
            self.assertIsNotNone(process)
            self.assertEqual(process.wait(timeout=5), 0)
            self.assertTrue((root / "marker").exists())
            self.assertEqual((root / "parent").read_text(), f"{process.pid}\n")


if __name__ == "__main__":
    unittest.main()
