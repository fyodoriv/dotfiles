import importlib.util
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
MODULE = Path(__file__).parent / "helpers/hook_trusted_launch.py"


class LaunchControls(unittest.TestCase):
    def test_concurrent_run_id_reservations_have_one_winner(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            script = ("import importlib.util, pathlib, sys\n"
                      "s=importlib.util.spec_from_file_location('m',sys.argv[1]); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)\n"
                      "try: m.reserve_run(pathlib.Path(sys.argv[2]), 'a'*32)\n"
                      "except FileExistsError: sys.exit(1)\n")
            env = {**os.environ, "PYTHONDONTWRITEBYTECODE": "1"}
            processes = [subprocess.Popen([sys.executable, "-c", script, str(MODULE.resolve()), str(root)],
                                          env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) for _ in range(2)]
            try:
                results = [process.wait(timeout=5) for process in processes]
                self.assertEqual(sorted(results), [0, 1])
            finally:
                for process in processes:
                    if process.poll() is None:
                        process.terminate()
                        process.wait(timeout=5)

    def test_retained_link_rejects_altered_or_private_inputs(self):
        spec = importlib.util.spec_from_file_location("trusted_launch", MODULE)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        verify = getattr(module, "verify_retained_link", lambda *_: False)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            audit = dict.fromkeys(("launcher", "harness", "perl", "BASH_ENV", "ENV", "wrapper"), "a" * 64)
            audit_bytes = json.dumps(audit, sort_keys=True).encode()
            flags = dict.fromkeys(("admission", "source", "harness", "tools", "output"), True)
            receipt = {"run_id": "b" * 32, "valid": True, "aa_pass": True, "samples": [[100] * 15, [100] * 15],
                       "medians": [100, 100], "aa_ratio": 1.0, "flags": flags, "load_ok": True, "failure": None}
            receipt_bytes = json.dumps(receipt).encode()
            wait_bytes = b"waited=0 pid=123 slot=exclusive\n"
            (root / "receipt.json").write_bytes(receipt_bytes)
            (root / "wait.log").write_bytes(wait_bytes)
            (root / "parent").write_text("123\n")
            for name in ("receipt.json", "wait.log", "parent"):
                (root / name).chmod(0o600)
            intent = {"format": 1, "run_id": receipt["run_id"], "revision": "c" * 40,
                      "audit_sha256": hashlib.sha256(audit_bytes).hexdigest()}
            intent_bytes = json.dumps(intent).encode()
            (root / "intent.json").write_bytes(intent_bytes)
            (root / "intent.json").chmod(0o600)
            record = {"format": 1, "intent_sha256": hashlib.sha256(intent_bytes).hexdigest(), "parent_pid": 123,
                      "parent_sha256": hashlib.sha256(b"123\n").hexdigest(),
                      "wait_sha256": hashlib.sha256(wait_bytes).hexdigest(),
                      "receipt_sha256": hashlib.sha256(receipt_bytes).hexdigest(), "verdict": "qualified"}
            target = root / "launch.json"
            self.assertFalse(verify(root, intent["revision"], audit_bytes, 123, intent["run_id"]))
            target.write_text(json.dumps(record))
            target.chmod(0o600)
            self.assertTrue(verify(root, intent["revision"], audit_bytes, 123, intent["run_id"]))
            self.assertFalse(verify(root, intent["revision"], audit_bytes, 123, "f" * 32))
            self.assertFalse(verify(root, "d" * 40, audit_bytes, 123, intent["run_id"]))
            self.assertFalse(verify(root, intent["revision"], audit_bytes + b" ", 123, intent["run_id"]))
            self.assertFalse(verify(root, intent["revision"], audit_bytes, 124, intent["run_id"]))
            for name in ("intent.json", "parent", "wait.log", "receipt.json", "launch.json"):
                path = root / name
                path.chmod(0o644)
                self.assertFalse(verify(root, intent["revision"], audit_bytes, 123, intent["run_id"]))
                path.chmod(0o600)
                moved = root / (name + ".saved")
                path.rename(moved)
                path.symlink_to(moved)
                self.assertFalse(verify(root, intent["revision"], audit_bytes, 123, intent["run_id"]))
                path.unlink()
                moved.rename(path)
                hardlink = root / (name + ".hardlink")
                os.link(path, hardlink)
                self.assertFalse(verify(root, intent["revision"], audit_bytes, 123, intent["run_id"]))
                hardlink.unlink()
            for key in ("run_id", "revision", "audit_sha256"):
                changed = json.dumps({**intent, key: "0" * len(intent[key])}).encode()
                (root / "intent.json").write_bytes(changed)
                target.write_text(json.dumps({**record, "intent_sha256": hashlib.sha256(changed).hexdigest()}))
                self.assertFalse(verify(root, intent["revision"], audit_bytes, 123, intent["run_id"]))
            (root / "intent.json").write_bytes(intent_bytes)
            for key in ("intent_sha256", "parent_pid", "parent_sha256", "wait_sha256", "receipt_sha256", "verdict"):
                with self.subTest(key=key):
                    target.write_text(json.dumps({**record, key: 124 if key == "parent_pid" else "PRIVATE_CANARY_123"}))
                    self.assertFalse(verify(root, intent["revision"], audit_bytes, 123, intent["run_id"]))
            target.write_text(json.dumps(record)[:-1] + ', "format": 1}')
            self.assertFalse(verify(root, intent["revision"], audit_bytes, 123, intent["run_id"]))
            target.write_text("not json")
            self.assertFalse(verify(root, intent["revision"], audit_bytes, 123, intent["run_id"]))
            target.write_text(json.dumps(record))
            target.chmod(0o644)
            self.assertFalse(verify(root, intent["revision"], audit_bytes, 123, intent["run_id"]))
            target.chmod(0o600)
            (root / "wait.log").write_bytes(wait_bytes + b"tampered")
            self.assertFalse(verify(root, intent["revision"], audit_bytes, 123, intent["run_id"]))
            (root / "wait.log").write_bytes(wait_bytes)
            (root / "receipt.json").write_bytes(receipt_bytes + b" ")
            self.assertFalse(verify(root, intent["revision"], audit_bytes, 123, intent["run_id"]))
            bad_samples = json.dumps({**receipt, "samples": [[0] * 15, [100] * 15]}).encode()
            (root / "receipt.json").write_bytes(bad_samples)
            target.write_text(json.dumps({**record, "receipt_sha256": hashlib.sha256(bad_samples).hexdigest()}))
            self.assertFalse(verify(root, intent["revision"], audit_bytes, 123, intent["run_id"]))
            huge_samples = json.dumps({**receipt, "samples": [[1] * 15, [10**400] * 15]}).encode()
            (root / "receipt.json").write_bytes(huge_samples)
            target.write_text(json.dumps({**record, "receipt_sha256": hashlib.sha256(huge_samples).hexdigest()}))
            self.assertFalse(verify(root, intent["revision"], audit_bytes, 123, intent["run_id"]))
            (root / "receipt.json").write_bytes(receipt_bytes)
            boolean_medians = json.dumps({**receipt, "samples": [[1] * 15, [1] * 15],
                                          "medians": [True, True]}).encode()
            (root / "receipt.json").write_bytes(boolean_medians)
            target.write_text(json.dumps({**record, "receipt_sha256": hashlib.sha256(boolean_medians).hexdigest()}))
            self.assertFalse(verify(root, intent["revision"], audit_bytes, 123, intent["run_id"]))
            (root / "receipt.json").write_bytes(receipt_bytes)
            duplicated_wait = wait_bytes + wait_bytes
            (root / "wait.log").write_bytes(duplicated_wait)
            target.write_text(json.dumps({**record, "wait_sha256": hashlib.sha256(duplicated_wait).hexdigest()}))
            self.assertFalse(verify(root, intent["revision"], audit_bytes, 123, intent["run_id"]))

    def test_full_synthetic_launch_and_preflight_rejections(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            helpers = root / "tests/helpers"
            helpers.mkdir(parents=True)
            wrapper = helpers / "hook_trusted_launch.py"
            shutil.copyfile(MODULE, wrapper)
            harness = helpers / "hook_rss_provenance.py"
            harness.write_text('''import json, os, pathlib
def installed_root(root): return True
def source_clean(root, revision): return True
def expected_parent_valid(path, parent):
    return path.is_file() and path.read_text() == str(parent) + "\\n"
if __name__ == "__main__":
    root = pathlib.Path(os.environ["HOOK_RSS_RUN_DIR"])
    parent = os.getppid()
    row = (root / "wait.log").read_text()
    if expected_parent_valid(root / "parent", parent) and row == f"pid={parent} slot=exclusive\\n" and os.environ.get("HEAVY_RUN_SLOT") == "exclusive":
        (pathlib.Path(os.environ["HOME"]) / "marker").write_text("started")
        flags = dict.fromkeys(("admission", "source", "harness", "tools", "output"), True)
        (root / "receipt.json").write_text(json.dumps({"run_id": os.environ["HOOK_RSS_RUN_ID"], "valid": True,
            "aa_pass": True, "samples": [[100] * 15, [100] * 15], "medians": [100, 100],
            "aa_ratio": 1.0, "flags": flags, "load_ok": True, "failure": None}))
        (root / "receipt.json").chmod(0o600)
    else:
        raise SystemExit(1)
''')
            bin_dir = root / "bin"
            bin_dir.mkdir()
            launcher = bin_dir / "heavy-run"
            launcher.write_text("#!" + sys.executable + "\n" + '''import os, subprocess, sys
parent = os.environ.get("FIXTURE_PARENT", str(os.getpid()))
slot = os.environ.get("FIXTURE_SLOT", "exclusive")
with open(os.environ["HEAVY_RUN_WAIT_LOG"], "a") as log: log.write(f"pid={parent} slot={slot}\\n")
os.environ["HEAVY_RUN_SLOT"] = "exclusive"
status = subprocess.call(sys.argv[2:])
if os.environ.get("FIXTURE_AUDIT_EDIT"): open(os.environ["FIXTURE_AUDIT_EDIT"], "a").write(" ")
sys.exit(status)
''')
            launcher.chmod(0o700)
            perl = bin_dir / "perl"
            perl.write_text("fixture")
            perl.chmod(0o700)
            startup, env_file = root / "startup", root / "env"
            startup.write_text(":\n")
            env_file.write_text(":\n")
            (root / ".local/state/dotfiles/rust-migration").mkdir(mode=0o700, parents=True)
            env = {"HOME": str(root), "PATH": str(bin_dir) + ":/usr/bin:/bin",
                   "BASH_ENV": str(startup), "ENV": str(env_file), "PYTHONDONTWRITEBYTECODE": "1"}
            digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
            audit = {"launcher": digest(launcher), "harness": digest(harness), "wrapper": digest(wrapper),
                     "perl": digest(perl), "BASH_ENV": digest(startup), "ENV": digest(env_file)}
            audit_file = root / "audit.json"
            audit_file.write_text(json.dumps(audit))
            audit_file.chmod(0o600)
            spec = importlib.util.spec_from_file_location("synthetic_launch", wrapper)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            with patch.object(module, "verify_retained_link", wraps=module.verify_retained_link) as verify_once:
                self.assertTrue(module.run_qualified(root, "a" * 40, audit_file, env, "b" * 32))
                self.assertEqual(verify_once.call_count, 1)
            run_dirs = list((root / ".local/state/dotfiles/rust-migration").glob("hook-rss-*"))
            self.assertEqual(len(run_dirs), 1)
            run_dir = run_dirs[0]
            parent_pid = int((run_dir / "parent").read_text())
            self.assertTrue(module.verify_retained_link(run_dir, "a" * 40, audit_file.read_bytes(), parent_pid, "b" * 32))
            marker = root / "marker"
            self.assertTrue(marker.exists())
            marker.unlink()
            self.assertFalse(module.run_qualified(root, "a" * 40, audit_file, env, "b" * 32))
            self.assertFalse(marker.exists())
            self.assertTrue(module.run_qualified(root, "a" * 40, audit_file, env, "d" * 32))
            self.assertTrue(marker.exists())
            marker.unlink()
            for index, key in enumerate(("launcher", "harness", "wrapper", "BASH_ENV", "ENV", "perl")):
                with self.subTest(key=key):
                    audit_file.write_text(json.dumps({**audit, key: "0" * 64}))
                    self.assertFalse(module.run_qualified(root, "a" * 40, audit_file, env, f"{100 + index:032x}"))
                    self.assertFalse(marker.exists())
            audit_file.write_text(json.dumps(audit))
            for index, change in enumerate(({"HEAVY_RUN_HELD": "fixture"}, {"FIXTURE_PARENT": "999999"}, {"FIXTURE_SLOT": "shared"})):
                with self.subTest(change=change):
                    self.assertFalse(module.run_qualified(root, "a" * 40, audit_file, {**env, **change}, f"{200 + index:032x}"))
                    self.assertFalse(marker.exists())
            occupied_id = "e" * 32
            occupied = root / ".local/state/dotfiles/rust-migration" / ("hook-rss-" + occupied_id)
            occupied.mkdir(mode=0o700)
            (occupied / "wait.log").write_text("existing")
            self.assertFalse(module.run_qualified(root, "a" * 40, audit_file, env, occupied_id))
            self.assertFalse(marker.exists())
            changed_id = "f" * 32
            self.assertFalse(module.run_qualified(root, "a" * 40, audit_file,
                                                 {**env, "FIXTURE_AUDIT_EDIT": str(audit_file)}, changed_id))
            self.assertTrue(marker.exists())
            self.assertFalse((root / ".local/state/dotfiles/rust-migration" / ("hook-rss-" + changed_id) / "launch.json").exists())
            marker.unlink()
            audit_file.write_text(json.dumps({**audit, "launcher": "PRIVATE_CANARY_123"}))
            result = subprocess.run([sys.executable, str(wrapper), "--run", "a" * 40, str(audit_file), "b" * 32],
                                    cwd=root, env=env, capture_output=True, timeout=5)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn(b"PRIVATE_CANARY_123", result.stdout + result.stderr)
            self.assertNotIn(audit["perl"].encode(), result.stdout + result.stderr)
            self.assertFalse(marker.exists())

    def test_interruption_keeps_synthetic_owner_until_sample_finishes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            sample = root / "sample.py"
            sample.write_text("import pathlib, sys, time\n"
                              "root=pathlib.Path(sys.argv[1]); (root/'started').write_text('yes')\n"
                              "time.sleep(.4); (root/'finished').write_text('yes')\n")
            launcher = root / "launcher"
            launcher.write_text("#!" + sys.executable + "\n" +
                "import pathlib, subprocess, sys\n"
                "root=pathlib.Path(sys.argv[-1]); subprocess.call(sys.argv[2:])\n"
                "(root/'owner-exited').write_text(str((root/'finished').exists()))\n")
            launcher.chmod(0o700)
            controller = root / "controller.py"
            controller.write_text("import importlib.util, os, pathlib, signal, sys, threading, time\n"
                "root=pathlib.Path(sys.argv[1]); spec=importlib.util.spec_from_file_location('launch', sys.argv[2])\n"
                "m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)\n"
                "def interrupt():\n"
                " while not (root/'started').exists(): time.sleep(.01)\n"
                " os.killpg(os.getpgrp(), signal.SIGINT)\n"
                "threading.Thread(target=interrupt, daemon=True).start()\n"
                "_, status=m.launch_and_wait(root/'launcher', [sys.executable, str(root/'sample.py'), str(root)], root, dict(os.environ))\n"
                "(root/'status').write_text(str(status))\n")
            result = subprocess.run([sys.executable, str(controller), str(root), str(MODULE.resolve())],
                                    capture_output=True, timeout=8, start_new_session=True)
            deadline = time.monotonic() + 2
            while not (root / "finished").exists() and time.monotonic() < deadline:
                time.sleep(.02)
            self.assertEqual(result.returncode, 0)
            self.assertTrue((root / "owner-exited").exists())
            self.assertEqual((root / "owner-exited").read_text(), "True")
            self.assertNotEqual((root / "status").read_text(), "0")

    def test_unknown_revision_never_starts_a_launcher(self):
        spec = importlib.util.spec_from_file_location("trusted_launch", MODULE)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        run = getattr(module, "run_qualified", lambda *_: True)
        with patch.object(module, "spawn_with_parent") as spawn:
            self.assertFalse(run(Path("/fixture"), "invalid", Path("/fixture/audit"), {}, "b" * 32))
            spawn.assert_not_called()

    def test_bootstrap_failure_never_starts_the_launcher(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "parent.new").write_text("already present")
            launcher = root / "launcher"
            launcher.write_text("#!" + sys.executable + "\n" +
                                "import pathlib, sys\npathlib.Path(sys.argv[1]).write_text('started')\n")
            launcher.chmod(0o700)
            marker = root / "marker"
            result = subprocess.run([sys.executable, str(MODULE), "--bootstrap", str(root),
                                     str(launcher), str(marker)], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(marker.exists())
            self.assertNotIn(str(root).encode(), result.stderr)

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

    def test_audit_record_requires_private_regular_file(self):
        spec = importlib.util.spec_from_file_location("trusted_launch", MODULE)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        read = getattr(module, "read_audit", lambda *_: None)
        with tempfile.TemporaryDirectory() as directory:
            audit_path = Path(directory) / "audit.json"
            audit = dict.fromkeys(("launcher", "harness", "perl", "BASH_ENV", "ENV", "wrapper"), "a" * 64)
            audit_path.write_text(json.dumps(audit))
            audit_path.chmod(0o600)
            self.assertEqual(read(audit_path), audit)
            audit_path.chmod(0o644)
            with self.assertRaises(ValueError):
                read(audit_path)

    def test_perl_selection_uses_bash_startup_path(self):
        spec = importlib.util.spec_from_file_location("trusted_launch", MODULE)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        resolve = getattr(module, "resolve_perl", lambda *_: None)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            perl = root / "perl"
            perl.write_text("fixture")
            perl.chmod(0o700)
            startup = root / "startup"
            startup.write_text('PATH="' + str(root) + ':$PATH"\n')
            env = {**os.environ, "BASH_ENV": str(startup)}
            self.assertEqual(resolve(env), perl)

    def test_exact_launch_environment_rejects_conditional_queue_override(self):
        spec = importlib.util.spec_from_file_location("trusted_launch", MODULE)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        valid = getattr(module, "launch_environment_valid", lambda *_: False)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            startup = root / "startup"
            startup.write_text(":\n")
            env = {"PATH": "/usr/bin:/bin", "BASH_ENV": str(startup),
                   "HEAVY_RUN_WAIT_LOG": str(root / "wait.log"), "HOOK_RSS_RUN_ID": "fixture"}
            self.assertTrue(valid(env, env["HEAVY_RUN_WAIT_LOG"]))
            startup.write_text('if [ -n "${HEAVY_RUN_WAIT_LOG:-}" ]; then export HEAVY_RUN_DIR=/fixture; fi\n')
            self.assertFalse(valid(env, env["HEAVY_RUN_WAIT_LOG"]))

    def test_launcher_requires_audited_inputs(self):
        spec = importlib.util.spec_from_file_location("trusted_launch", MODULE)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        valid = getattr(module, "audited_inputs_valid", lambda *_: False)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            launcher, harness, perl, bash_env, env_file = [root / name for name in
                ("launcher", "harness", "perl", "bash_env", "env")]
            for path in (launcher, harness, perl, bash_env, env_file):
                path.write_text("fixture" if path != bash_env else 'PATH="' + str(root) + ':$PATH"\n')
            perl.chmod(0o700)
            digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
            audit = {"launcher": digest(launcher), "harness": digest(harness), "perl": digest(perl),
                     "BASH_ENV": digest(bash_env), "ENV": digest(env_file)}
            env = {"PATH": "/usr/bin:/bin", "BASH_ENV": str(bash_env), "ENV": str(env_file)}
            self.assertTrue(valid(launcher, harness, env, audit))
            for key in audit:
                with self.subTest(key=key):
                    self.assertFalse(valid(launcher, harness, env, {**audit, key: "0" * 64}))
            self.assertFalse(valid(launcher, harness, {**env, "HEAVY_RUN_DIR": "/other"}, audit))
            bash_env.write_text('export HEAVY_RUN_DIR=/fixture\nPATH="' + str(root) + ':$PATH"\n')
            self.assertFalse(valid(launcher, harness, env, {**audit, "BASH_ENV": digest(bash_env)}))

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
            child.write_text("import importlib.util, os, pathlib\n"
                "spec=importlib.util.spec_from_file_location('p', os.environ['FIXTURE_LIB'])\n"
                "p=importlib.util.module_from_spec(spec); spec.loader.exec_module(p)\n"
                "root=pathlib.Path(os.environ['FIXTURE_ROOT'])\n"
                "if p.wait_expected_parent(root/'parent', os.getppid(), timeout=3) and p.admission_valid((root/'wait.log').read_text(), os.getppid(), os.environ['HEAVY_RUN_SLOT']): (root/'marker').write_text('started')\n")
            log = root / "wait.log"
            log.write_text("")
            log.chmod(0o600)
            env = {**os.environ, "PYTHONDONTWRITEBYTECODE": "1", "HEAVY_RUN_WAIT_LOG": str(log), "FIXTURE_ROOT": str(root),
                   "FIXTURE_LIB": str(Path(__file__).parent / "helpers/hook_rss_provenance.py")}
            process = spawn(launcher, [sys.executable, str(child)], root, env)
            self.assertIsNotNone(process)
            try:
                self.assertEqual(process.wait(timeout=5), 0)
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=5)
            self.assertTrue((root / "marker").exists())
            self.assertEqual((root / "parent").read_text(), f"{process.pid}\n")
            (root / "marker").unlink()
            (root / "parent").unlink()
            log.write_text("")
            process = spawn(launcher, [sys.executable, str(child)], root, {**env, "SYNTHETIC_SLOT": "shared"})
            try:
                self.assertEqual(process.wait(timeout=5), 0)
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=5)
            self.assertFalse((root / "marker").exists())


if __name__ == "__main__":
    unittest.main()
