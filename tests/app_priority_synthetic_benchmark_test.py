"""Safety checks for the fixture benchmark without starting a process."""

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/app-priority-synthetic-benchmark.py"
SPEC = importlib.util.spec_from_file_location("app_priority_benchmark", SCRIPT)
benchmark = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(benchmark)


class BenchmarkTests(unittest.TestCase):
    def test_only_hosted_macos_is_admitted(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertFalse(benchmark.hosted())
        with patch.dict(os.environ, {"GITHUB_ACTIONS": "true", "RUNNER_OS": "macOS",
                                    "RUNNER_ENVIRONMENT": "github-hosted"}, clear=True):
            self.assertTrue(benchmark.hosted())

    def test_action_and_output_changes_refuse(self):
        base = (benchmark.EXPECTED_ACTIONS, b"", b"")
        benchmark.compare(base, base)
        for candidate in [(b"", b"", b""), (b"renice 10\n", b"", b""),
                          (base[0], b"different", b""), (base[0], b"", b"error")]:
            with self.assertRaises(RuntimeError):
                benchmark.compare(base, candidate)

    def test_sample_uses_only_mock_action_commands_and_isolated_home(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home, config, mockbin = benchmark.prepare(root)
            class Result:
                returncode = 0
                stdout = b""
                stderr = b""
            def fake_run(command, *, env, **kwargs):
                self.assertEqual(command[0], "/bin/bash")
                self.assertEqual(env["HOME"], str(home))
                self.assertEqual(env["XDG_CONFIG_HOME"], str(config))
                self.assertEqual(env["PATH"], str(mockbin) + ":/usr/bin:/bin")
                self.assertEqual(env["DOTFILES_STATS_LOG"], "0")
                self.assertNotIn("BASH_ENV", env)
                for name in ("pgrep", "ps", "taskpolicy", "renice"):
                    self.assertTrue((mockbin / name).is_file())
                Path(env["ACTION_LOG"]).write_bytes(b"taskpolicy -b -p 101\n")
                return Result()
            with patch.object(benchmark.subprocess, "run", side_effect=fake_run):
                _, actions, _, _ = benchmark.sample(root, root, home, config, mockbin)
            self.assertEqual(actions, b"taskpolicy -b -p 101\n")


if __name__ == "__main__":
    unittest.main()
