"""Safety checks for the fixture benchmark without starting a process."""

import importlib.util
import json
import os
import shutil
import subprocess
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/app-priority-synthetic-benchmark.py"
SPEC = importlib.util.spec_from_file_location("app_priority_benchmark", SCRIPT)
benchmark = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(benchmark)


class BenchmarkTests(unittest.TestCase):
    def test_workflow_cancels_only_superseded_pull_request_runs(self):
        workflow = SCRIPT.parents[1] / ".github/workflows/app-priority-fixture.yml"
        data = subprocess.check_output([
            "ruby", "-rjson", "-ryaml", "-e",
            "puts JSON.dump(YAML.load_file(ARGV.fetch(0)))", str(workflow)
        ], text=True)
        concurrency = json.loads(data).get("concurrency")
        self.assertEqual(concurrency, {
            "group": "app-priority-fixture-${{ github.event.pull_request.number || github.run_id }}",
            "cancel-in-progress": "${{ github.event_name == 'pull_request' }}",
        })

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


def hosted_fixture():
    return (os.environ.get("GITHUB_ACTIONS") == "true"
            and os.environ.get("RUNNER_ENVIRONMENT") == "github-hosted"
            and os.environ.get("RUNNER_OS") in {"Linux", "macOS"})


@unittest.skipUnless(hosted_fixture(), "physical fixture runs only on hosted runners")
class CandidateFixtureTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="app-priority-candidate-")
        self.root = Path(self.temporary.name)
        self.home, self.config, self.mockbin = benchmark.prepare(self.root)
        self.repo = SCRIPT.parents[1]
        self.candidate = self.root / "candidate"
        (self.candidate / "bin").mkdir(parents=True)
        (self.candidate / "lib").mkdir()
        shutil.copyfile(self.repo / "scripts/app-priority-candidate.sh",
                        self.candidate / "bin/app-priority")
        for name in ("stats.sh", "colors.sh"):
            shutil.copyfile(self.repo / "lib" / name, self.candidate / "lib" / name)

    def tearDown(self):
        self.temporary.cleanup()

    def observe(self, tree):
        return benchmark.sample(tree, self.root, self.home, self.config, self.mockbin)[1:]

    def test_default_fixture_keeps_all_actions_and_output(self):
        benchmark.compare(self.observe(self.repo), self.observe(self.candidate))

    def test_malformed_grouped_output_falls_back_to_individual_queries(self):
        pgrep = self.mockbin / "pgrep"
        source = pgrep.read_text()
        source = source.replace('printf "101 claude\\\\n201 codex\\\\n301 Slack\\\\n401 bats\\\\n"',
                                'printf "invalid\\n"')
        self.assertNotEqual(source, pgrep.read_text())
        pgrep.write_text(source)
        benchmark.compare(self.observe(self.repo), self.observe(self.candidate))

    def test_duplicate_grouped_pid_falls_back_to_individual_queries(self):
        pgrep = self.mockbin / "pgrep"
        source = pgrep.read_text()
        expected = 'printf "101 claude\\\\n201 codex\\\\n301 Slack\\\\n401 bats\\\\n"'
        replacement = 'printf "101 claude\\n101 claude\\n"'
        self.assertIn(expected, source)
        pgrep.write_text(source.replace(expected, replacement))
        benchmark.compare(self.observe(self.repo), self.observe(self.candidate))

    def test_explicit_config_uses_original_selection(self):
        folder = self.config / "dotfiles"
        folder.mkdir()
        (folder / "priority-apps.txt").write_text("Slack\n")
        self.assertEqual(self.observe(self.repo), self.observe(self.candidate))
        self.assertEqual(self.observe(self.candidate)[0], b"taskpolicy -B -t 0 -l 0 -p 301\n")


if __name__ == "__main__":
    unittest.main()
