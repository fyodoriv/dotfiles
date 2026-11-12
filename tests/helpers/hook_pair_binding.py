"""Verify retained pair observations against independently supplied identity.

The attempt digest covers normalized, validated JSON records, not file bytes.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import stat

from hook_pair_receipts import private_dir, read_attempts
from hook_source_audit import parse_source_audit
from hook_source_snapshot import read_snapshot
from hook_remote_mapping import verify_source_binding
from hook_status_pairs import CASES, FLAGS, summarize
from hook_pair_private import read_private
from hook_trusted_launch import parse_audit, strict_json


def read_published_pair(root):
    """Read the two intentional, private links to one published record."""
    pending, final = root / "launch.pending", root / "launch.json"
    def fingerprint(info):
        return (info.st_dev, info.st_ino, info.st_mode, info.st_uid, info.st_nlink,
                info.st_size, info.st_mtime_ns, info.st_ctime_ns)
    with os.fdopen(os.open(pending, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), "rb") as first, \
            os.fdopen(os.open(final, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), "rb") as second:
        left, right = os.fstat(first.fileno()), os.fstat(second.fileno())
        if (not stat.S_ISREG(left.st_mode) or left.st_uid != os.geteuid() or
                stat.S_IMODE(left.st_mode) != 0o600 or left.st_nlink != 2 or left.st_size > 4096 or
                fingerprint(left) != fingerprint(right)):
            raise ValueError("invalid published pair")
        one, two = first.read(4097), second.read(4097)
        if (len(one) != left.st_size or one != two or
                fingerprint(os.fstat(first.fileno())) != fingerprint(left) or
                fingerprint(os.fstat(second.fileno())) != fingerprint(left) or
                fingerprint(os.stat(pending, follow_symlinks=False)) != fingerprint(left) or
                fingerprint(os.stat(final, follow_symlinks=False)) != fingerprint(left)):
            raise ValueError("published pair changed")
        return one


def verify_pair_link(root, run_id, candidate, old, harness, audit_bytes, source_audit, source_manifest,
                     mapping_archive, mapping_digest, expected_source_audit_sha256, parent_pid, final_name="launch.json"):
    try:
        root = Path(root)
        if (final_name not in ("launch.json", "launch.pending") or
                not private_dir(root) or type(parent_pid) is not int or parent_pid <= 0 or
                type(run_id) is not str or not re.fullmatch(r"[0-9a-f]{32}", run_id) or
                any(type(revision) is not str or not re.fullmatch(r"[0-9a-f]{40}", revision)
                    for revision in (candidate, old, harness))):
            return None
        parse_audit(audit_bytes)
        if (parse_source_audit(source_audit, source_manifest, run_id, old, candidate) is None or
                not verify_source_binding(run_id, old, candidate, source_manifest, source_audit, mapping_archive,
                                          expected_source_audit_sha256, mapping_digest)):
            return None
        intent_bytes = read_private(root / "intent.json", 4096)
        parent_bytes = read_private(root / "parent", 64)
        wait_bytes = read_private(root / "wait.log", 4096)
        receipt_bytes = read_private(root / "receipt.json", 65536)
        intent = strict_json(intent_bytes)
        receipt = strict_json(receipt_bytes)
        final_bytes = read_published_pair(root) if final_name == "launch.json" else read_private(root / final_name, 4096)
        final = strict_json(final_bytes)
        expected_intent = {"format": 1, "run_id": run_id, "candidate_revision": candidate,
                           "old_revision": old, "harness_revision": harness,
                           "audit_sha256": hashlib.sha256(audit_bytes).hexdigest(),
                           "source_audit_sha256": expected_source_audit_sha256,
                           "source_manifest_sha256": hashlib.sha256(source_manifest).hexdigest(),
                           "mapping_sha256": mapping_digest}
        if type(intent) is not dict or intent != expected_intent or type(intent.get("format")) is not int:
            return None
        if (read_private(root / "mapping.json", 11_000_000) != mapping_archive or
                read_snapshot(root / "source", source_manifest, run_id, old, candidate) is None):
            return None
        if parent_bytes != f"{parent_pid}\n".encode("ascii"):
            return None
        rows = re.findall(rb"\bpid=(\d+)\s+slot=(\S+)", wait_bytes)
        if len(wait_bytes.splitlines()) != 1 or rows != [(str(parent_pid).encode("ascii"), b"exclusive")]:
            return None
        attempts = read_attempts(root, run_id)
        if attempts is None:
            return None
        attempt_bytes = json.dumps(attempts, sort_keys=True, separators=(",", ":")).encode()
        expected_final = {"format": 1, "intent_sha256": hashlib.sha256(intent_bytes).hexdigest(),
                          "parent_pid": parent_pid, "parent_sha256": hashlib.sha256(parent_bytes).hexdigest(),
                          "wait_sha256": hashlib.sha256(wait_bytes).hexdigest(),
                          "receipt_sha256": hashlib.sha256(receipt_bytes).hexdigest(),
                          "attempts_sha256": hashlib.sha256(attempt_bytes).hexdigest(), "verdict": "qualified"}
        if (type(final) is not dict or final != expected_final or type(final.get("format")) is not int or
                type(final.get("parent_pid")) is not int):
            return None
        keys = {"format", "run_id", "valid", "passed", "median_ratios", "flags", "failure"}
        if (type(receipt) is not dict or set(receipt) != keys or type(receipt["format"]) is not int or
                receipt["format"] != 1 or receipt["run_id"] != run_id or receipt["valid"] is not True or
                type(receipt["passed"]) is not bool or receipt["failure"] is not None or
                type(receipt["flags"]) is not dict or set(receipt["flags"]) != set(FLAGS) or
                not all(value is True for value in receipt["flags"].values())):
            return None
        cases = {name: [] for name in CASES}
        for offset in range(0, len(attempts), 2):
            first, second = attempts[offset:offset + 2]
            by_side = {first["side"]: first["elapsed_ns"], second["side"]: second["elapsed_ns"]}
            cases[first["case"]].append({"order": first["order"], "old_ns": by_side["old"], "new_ns": by_side["new"]})
        summary = summarize(cases, receipt["flags"])
        ratios = receipt["median_ratios"]
        if (not summary["valid"] or receipt["passed"] is not summary["passed"] or type(ratios) is not dict or
                set(ratios) != set(CASES) or any(type(ratios[name]) is not float or ratios[name] != summary["median_ratios"][name] for name in CASES)):
            return None
        if (read_private(root / "mapping.json", 11_000_000) != mapping_archive or
                read_snapshot(root / "source", source_manifest, run_id, old, candidate) is None):
            return None
        return summary
    except (KeyError, OSError, TypeError, UnicodeError, ValueError):
        return None
