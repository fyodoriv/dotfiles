"""Preflight controls for a future exclusive hook pair worker."""
from pathlib import Path
import re

from hook_pair_receipts import private_dir
from hook_trusted_launch import read_private, strict_json


def identity_ok(root, run_dir, environ, parent_pid):
    try:
        root, run_dir = Path(root), Path(run_dir)
        run_id = environ["HOOK_PAIR_RUN_ID"]
        revisions = [environ[key] for key in ("HOOK_PAIR_CANDIDATE", "HOOK_PAIR_OLD", "HOOK_PAIR_HARNESS_REVISION")]
        audit = environ["HOOK_PAIR_AUDIT_SHA256"]
        expected_dir = Path(environ["HOME"]) / ".local/state/dotfiles/rust-migration" / ("hook-rss-" + run_id)
        if (not root.is_absolute() or not private_dir(run_dir) or run_dir != expected_dir or
                environ["HOOK_PAIR_RUN_DIR"] != str(run_dir) or environ["DOTFILES_DIR"] != str(root) or
                environ["HEAVY_RUN_SLOT"] != "exclusive" or
                environ["HEAVY_RUN_WAIT_LOG"] != str(run_dir / "wait.log") or
                type(parent_pid) is not int or parent_pid <= 0 or
                type(run_id) is not str or not re.fullmatch(r"[0-9a-f]{32}", run_id) or
                any(type(revision) is not str or not re.fullmatch(r"[0-9a-f]{40}", revision) for revision in revisions) or
                type(audit) is not str or not re.fullmatch(r"[0-9a-f]{64}", audit)):
            return False
        expected = {"format": 1, "run_id": run_id, "candidate_revision": revisions[0],
                    "old_revision": revisions[1], "harness_revision": revisions[2], "audit_sha256": audit}
        intent = strict_json(read_private(run_dir / "intent.json", 4096))
        if type(intent) is not dict or intent != expected or type(intent.get("format")) is not int:
            return False
        if read_private(run_dir / "parent", 64) != f"{parent_pid}\n".encode("ascii"):
            return False
        wait = read_private(run_dir / "wait.log", 4096)
        rows = re.findall(rb"\bpid=(\d+)\s+slot=(\S+)", wait)
        return len(wait.splitlines()) == 1 and rows == [(str(parent_pid).encode("ascii"), b"exclusive")]
    except (KeyError, OSError, TypeError, UnicodeError, ValueError):
        return False
