#!/usr/bin/env python3
"""Trusted-launch checks for a private hook memory receipt."""
import hashlib
import importlib.util
import json
import os
import re
import signal
import stat
import subprocess
import sys
import tempfile
from pathlib import Path


class CleanupIncomplete(Exception):
    pass


def safe_queue_environment(environ):
    return not any(name.startswith("HEAVY_RUN_") and value for name, value in environ.items())


def matches_digest(path, expected):
    try:
        return bool(path.is_absolute() and path.is_file() and re.fullmatch(r"[0-9a-f]{64}", expected) and
                    hashlib.sha256(path.read_bytes()).hexdigest() == expected)
    except OSError:
        return False


def resolve_perl(environ, allowed_wait_log=""):
    script = ('for n in ${!HEAVY_RUN_@}; do '
              'if [[ "$n" == HEAVY_RUN_WAIT_LOG && "${!n}" == "$1" && -n "$1" ]]; then continue; fi; '
              '[[ -z "${!n}" ]] || exit 2; done; '
              '[[ "${HEAVY_RUN_WAIT_LOG:-}" == "$1" ]] || exit 2; command -v perl')
    result = subprocess.run(["/bin/bash", "-c", script, "_", allowed_wait_log], env=environ,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if result.returncode or result.stderr or result.stdout.count(b"\n") != 1:
        raise ValueError("Perl selection unavailable")
    path = Path(result.stdout.decode("utf-8").strip())
    if not path.is_absolute() or not path.is_file() or not os.access(path, os.X_OK):
        raise ValueError("Perl selection unavailable")
    return path


def launch_environment_valid(environ, expected_wait_log):
    try:
        resolve_perl(environ, expected_wait_log)
        return True
    except (OSError, UnicodeError, ValueError, subprocess.SubprocessError):
        return False


def audited_inputs_valid(launcher, harness, environ, audit):
    if (not safe_queue_environment(environ) or
            any(name.startswith("BASH_FUNC_") for name in environ)):
        return False
    if not matches_digest(launcher, audit.get("launcher", "")) or not matches_digest(harness, audit.get("harness", "")):
        return False
    for name in ("BASH_ENV", "ENV"):
        if not matches_digest(Path(environ.get(name, "")), audit.get(name, "")):
            return False
    try:
        return matches_digest(resolve_perl(environ), audit.get("perl", ""))
    except (OSError, UnicodeError, ValueError, subprocess.SubprocessError):
        return False


def create_private_log(run_dir):
    info = run_dir.lstat()
    if (not run_dir.is_absolute() or not stat.S_ISDIR(info.st_mode) or
            info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) != 0o700):
        raise ValueError("private directory required")
    log = run_dir / "wait.log"
    fd = os.open(log, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    os.close(fd)
    return log


def read_audit(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, "rb") as handle:
        info = os.fstat(handle.fileno())
        if (not path.is_absolute() or not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or
                stat.S_IMODE(info.st_mode) != 0o600 or info.st_nlink != 1 or info.st_size > 4096):
            raise ValueError("private audit required")
        audit = json.load(handle)
    keys = {"launcher", "harness", "perl", "BASH_ENV", "ENV", "wrapper"}
    if (type(audit) is not dict or set(audit) != keys or
            any(type(value) is not str or not re.fullmatch(r"[0-9a-f]{64}", value) for value in audit.values())):
        raise ValueError("invalid audit")
    return audit


def spawn_with_parent(launcher, command, run_dir, environ, workdir=None):
    parent = run_dir / "parent"
    staging = run_dir / "parent.new"
    if parent.exists() or staging.exists():
        raise FileExistsError("parent record exists")
    return subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "--bootstrap", str(run_dir),
                             str(launcher), "--exclusive", *command], cwd=workdir or run_dir,
                            env=environ, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                            start_new_session=True)


def launch_and_wait(launcher, command, run_dir, environ, workdir=None):
    signals = (signal.SIGINT, signal.SIGTERM, signal.SIGHUP)
    previous_mask = signal.pthread_sigmask(signal.SIG_BLOCK, signals)
    previous_handlers = {sig: signal.getsignal(sig) for sig in signals}
    child = None
    was_interrupted = False

    def interrupted(_sig, _frame):
        nonlocal was_interrupted
        was_interrupted = True

    try:
        for sig in signals:
            signal.signal(sig, interrupted)
        child = spawn_with_parent(launcher, command, run_dir, environ, workdir)
        signal.pthread_sigmask(signal.SIG_SETMASK, previous_mask)
        status = child.wait()
        return child, 1 if was_interrupted else status
    except BaseException:
        signal.pthread_sigmask(signal.SIG_BLOCK, signals)
        if child is not None and child.poll() is None:
            try:
                child.wait()
            except (OSError, subprocess.SubprocessError) as error:
                raise CleanupIncomplete("owned child could not be reaped") from error
        raise
    finally:
        signal.pthread_sigmask(signal.SIG_BLOCK, signals)
        for sig, handler in previous_handlers.items():
            signal.signal(sig, handler)
        signal.pthread_sigmask(signal.SIG_SETMASK, previous_mask)


def bootstrap(run_dir, command):
    parent = run_dir / "parent"
    staging = run_dir / "parent.new"
    fd = os.open(staging, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w") as handle:
        handle.write(f"{os.getpid()}\n")
    os.link(staging, parent)
    staging.unlink()
    signal.pthread_sigmask(signal.SIG_UNBLOCK, (signal.SIGINT, signal.SIGTERM, signal.SIGHUP))
    os.execv(command[0], command)


def run_qualified(root, revision, audit_path, environ):
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        return False
    launcher = root / "bin/heavy-run"
    harness = root / "tests/helpers/hook_rss_provenance.py"
    wrapper = root / "tests/helpers/hook_trusted_launch.py"
    try:
        audit = read_audit(audit_path)
        if (Path(__file__).resolve() != wrapper.resolve() or not matches_digest(wrapper, audit["wrapper"]) or
                not audited_inputs_valid(launcher, harness, environ, audit)):
            return False
        sys.dont_write_bytecode = True
        spec = importlib.util.spec_from_file_location("hook_rss_provenance", harness)
        provenance = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(provenance)
        if not provenance.installed_root(root) or not provenance.source_clean(root, revision):
            return False
        parent = Path(environ["HOME"]) / ".local/state/dotfiles/rust-migration"
        info = parent.lstat()
        if (not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid() or
                stat.S_IMODE(info.st_mode) & 0o077):
            return False
        run_dir = Path(tempfile.mkdtemp(prefix="hook-rss-", dir=parent)).resolve()
        wait_log = create_private_log(run_dir)
        run_id = os.urandom(16).hex()
        child_env = dict(environ)
        child_env.update({"DOTFILES_DIR": str(root), "HEAVY_RUN_WAIT_LOG": str(wait_log),
                          "HOOK_RSS_RUN_DIR": str(run_dir), "HOOK_RSS_REVISION": revision,
                          "HOOK_RSS_HARNESS_SHA256": audit["harness"], "HOOK_RSS_RUN_ID": run_id,
                          "HOOK_RSS_BASH_ENV_SHA256": audit["BASH_ENV"], "HOOK_RSS_ENV_SHA256": audit["ENV"]})
        selected_perl = resolve_perl(child_env, str(wait_log))
        if selected_perl != resolve_perl(environ) or not matches_digest(selected_perl, audit["perl"]):
            return False
        process, status = launch_and_wait(launcher, [sys.executable, str(harness)], run_dir, child_env, root)
        if (status != 0 or not provenance.expected_parent_valid(run_dir / "parent", process.pid) or
                not provenance.source_clean(root, revision) or
                not matches_digest(wrapper, audit["wrapper"]) or
                not audited_inputs_valid(launcher, harness, environ, audit) or
                resolve_perl(child_env, str(wait_log)) != selected_perl):
            return False
        receipt = json.loads((run_dir / "receipt.json").read_text())
        return (type(receipt) is dict and receipt.get("run_id") == run_id and
                receipt.get("valid") is True and receipt.get("aa_pass") is True)
    except (KeyError, OSError, UnicodeError, ValueError, subprocess.SubprocessError, json.JSONDecodeError):
        return False


if __name__ == "__main__":
    try:
        if len(sys.argv) >= 4 and sys.argv[1] == "--bootstrap":
            bootstrap(Path(sys.argv[2]), sys.argv[3:])
        if len(sys.argv) != 4 or sys.argv[1] != "--run":
            raise ValueError("invalid launch")
        valid = run_qualified(Path.cwd().resolve(), sys.argv[2], Path(sys.argv[3]), dict(os.environ))
        print("hook launch: " + ("qualified" if valid else "inconclusive"))
        raise SystemExit(0 if valid else 1)
    except CleanupIncomplete:
        print("hook launch: cleanup incomplete", file=sys.stderr)
        raise SystemExit(1)
    except Exception:
        print("hook launch: inconclusive", file=sys.stderr)
        raise SystemExit(1)
