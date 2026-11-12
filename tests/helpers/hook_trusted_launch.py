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


def reserve_run(parent, run_id):
    info = parent.lstat()
    if (not parent.is_absolute() or not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid() or
            stat.S_IMODE(info.st_mode) & 0o077 or not re.fullmatch(r"[0-9a-f]{32}", run_id)):
        raise ValueError("private run reservation required")
    run_dir = parent / ("hook-rss-" + run_id)
    run_dir.mkdir(mode=0o700)
    return run_dir.resolve()


def read_private(path, limit=1_000_000):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, "rb") as handle:
        info = os.fstat(handle.fileno())
        if (not path.is_absolute() or not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or
                stat.S_IMODE(info.st_mode) != 0o600 or info.st_nlink != 1 or info.st_size > limit):
            raise ValueError("private file required")
        data = handle.read(limit + 1)
        after = os.fstat(handle.fileno())
        if len(data) != info.st_size or after.st_size != info.st_size or after.st_mtime_ns != info.st_mtime_ns:
            raise ValueError("private file changed")
        return data


def strict_json(data):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("duplicate field")
            result[key] = value
        return result
    return json.loads(data, object_pairs_hook=unique)


def parse_audit(data):
    audit = strict_json(data)
    keys = {"launcher", "harness", "perl", "BASH_ENV", "ENV", "wrapper"}
    if (type(audit) is not dict or set(audit) != keys or
            any(type(value) is not str or not re.fullmatch(r"[0-9a-f]{64}", value) for value in audit.values())):
        raise ValueError("invalid audit")
    return audit


def read_audit(path):
    return parse_audit(read_private(path, 4096))


def write_private_json(path, value):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w") as handle:
        json.dump(value, handle, sort_keys=True)
        handle.write("\n")


def verify_retained_link(run_dir, revision, audit_bytes, parent_pid, expected_run_id, final_name="launch.json"):
    try:
        parse_audit(audit_bytes)
        info = run_dir.lstat()
        if (not run_dir.is_absolute() or not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid() or
                stat.S_IMODE(info.st_mode) != 0o700 or type(parent_pid) is not int or parent_pid <= 0):
            return False
        intent_bytes = read_private(run_dir / "intent.json", 4096)
        parent_bytes = read_private(run_dir / "parent", 64)
        wait_bytes = read_private(run_dir / "wait.log", 4096)
        receipt_bytes = read_private(run_dir / "receipt.json", 65536)
        final = strict_json(read_private(run_dir / final_name, 4096))
        intent = strict_json(intent_bytes)
        receipt = strict_json(receipt_bytes)
        if (type(intent) is not dict or set(intent) != {"format", "run_id", "revision", "audit_sha256"} or
                type(intent["format"]) is not int or intent["format"] != 1 or
                not re.fullmatch(r"[0-9a-f]{32}", intent["run_id"]) or
                intent["run_id"] != expected_run_id or
                not re.fullmatch(r"[0-9a-f]{40}", revision) or intent["revision"] != revision or
                intent["audit_sha256"] != hashlib.sha256(audit_bytes).hexdigest()):
            return False
        expected = {"format": 1, "intent_sha256": hashlib.sha256(intent_bytes).hexdigest(),
                    "parent_pid": parent_pid, "parent_sha256": hashlib.sha256(parent_bytes).hexdigest(),
                    "wait_sha256": hashlib.sha256(wait_bytes).hexdigest(),
                    "receipt_sha256": hashlib.sha256(receipt_bytes).hexdigest(), "verdict": "qualified"}
        if type(final) is not dict or final != expected or type(final.get("format")) is not int or type(final.get("parent_pid")) is not int:
            return False
        if parent_bytes != f"{parent_pid}\n".encode("ascii"):
            return False
        rows = re.findall(rb"\bpid=(\d+)\s+slot=(\S+)", wait_bytes)
        if len(wait_bytes.splitlines()) != 1 or rows != [(str(parent_pid).encode("ascii"), b"exclusive")]:
            return False
        keys = {"valid", "samples", "medians", "aa_ratio", "aa_pass", "flags", "load_ok", "run_id", "failure"}
        if type(receipt) is not dict or set(receipt) != keys or receipt["run_id"] != intent["run_id"]:
            return False
        windows = receipt["samples"]
        if (type(windows) is not list or len(windows) != 2 or
                any(type(window) is not list or len(window) != 15 or
                    any(type(value) is not int or not 0 < value <= (2**63 - 1) for value in window) for window in windows)):
            return False
        medians = [sorted(window)[7] for window in windows]
        ratio = medians[1] / medians[0]
        flags = receipt["flags"]
        return (receipt["valid"] is True and receipt["aa_pass"] is True and receipt["load_ok"] is True and
                receipt["failure"] is None and type(receipt["medians"]) is list and
                all(type(value) is int for value in receipt["medians"]) and receipt["medians"] == medians and
                type(receipt["aa_ratio"]) in (int, float) and
                receipt["aa_ratio"] == ratio and 0.95 <= ratio <= 1.05 and type(flags) is dict and
                set(flags) == {"admission", "source", "harness", "tools", "output"} and all(value is True for value in flags.values()))
    except (KeyError, OSError, TypeError, UnicodeError, ValueError):
        return False


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


def run_qualified(root, revision, audit_path, environ, run_id):
    if not re.fullmatch(r"[0-9a-f]{40}", revision) or not re.fullmatch(r"[0-9a-f]{32}", run_id):
        return False
    launcher = root / "bin/heavy-run"
    harness = root / "tests/helpers/hook_rss_provenance.py"
    wrapper = root / "tests/helpers/hook_trusted_launch.py"
    try:
        audit_bytes = read_private(audit_path, 4096)
        audit = parse_audit(audit_bytes)
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
        run_dir = reserve_run(parent, run_id)
        wait_log = create_private_log(run_dir)
        intent = {"format": 1, "run_id": run_id, "revision": revision,
                  "audit_sha256": hashlib.sha256(audit_bytes).hexdigest()}
        write_private_json(run_dir / "intent.json", intent)
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
                resolve_perl(child_env, str(wait_log)) != selected_perl or
                read_private(audit_path, 4096) != audit_bytes):
            return False
        intent_bytes = read_private(run_dir / "intent.json", 4096)
        parent_bytes = read_private(run_dir / "parent", 64)
        wait_bytes = read_private(wait_log, 4096)
        receipt_bytes = read_private(run_dir / "receipt.json", 65536)
        final = {"format": 1, "intent_sha256": hashlib.sha256(intent_bytes).hexdigest(),
                 "parent_pid": process.pid, "parent_sha256": hashlib.sha256(parent_bytes).hexdigest(),
                 "wait_sha256": hashlib.sha256(wait_bytes).hexdigest(),
                 "receipt_sha256": hashlib.sha256(receipt_bytes).hexdigest(), "verdict": "qualified"}
        staging = run_dir / "launch.pending"
        write_private_json(staging, final)
        if not verify_retained_link(run_dir, revision, audit_bytes, process.pid, run_id, "launch.pending"):
            staging.unlink()
            return False
        os.link(staging, run_dir / "launch.json")
        staging.unlink()
        return True
    except (KeyError, OSError, UnicodeError, ValueError, subprocess.SubprocessError, json.JSONDecodeError):
        return False


if __name__ == "__main__":
    try:
        if len(sys.argv) >= 4 and sys.argv[1] == "--bootstrap":
            bootstrap(Path(sys.argv[2]), sys.argv[3:])
        if len(sys.argv) != 5 or sys.argv[1] != "--run":
            raise ValueError("invalid launch")
        valid = run_qualified(Path.cwd().resolve(), sys.argv[2], Path(sys.argv[3]), dict(os.environ), sys.argv[4])
        print("hook launch: " + ("qualified" if valid else "inconclusive"))
        raise SystemExit(0 if valid else 1)
    except CleanupIncomplete:
        print("hook launch: cleanup incomplete", file=sys.stderr)
        raise SystemExit(1)
    except Exception:
        print("hook launch: inconclusive", file=sys.stderr)
        raise SystemExit(1)
