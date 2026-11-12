"""Verify retained pair observations against independently supplied identity.

The attempt digest covers normalized, validated JSON records, not file bytes.
"""
import hashlib
import json
from pathlib import Path
import re

from hook_pair_receipts import private_dir, read_attempts
from hook_status_pairs import CASES, FLAGS, summarize
from hook_trusted_launch import parse_audit, read_private, strict_json


def verify_pair_link(root, run_id, candidate, old, harness, audit_bytes, parent_pid):
    try:
        root = Path(root)
        if (not private_dir(root) or type(parent_pid) is not int or parent_pid <= 0 or
                type(run_id) is not str or not re.fullmatch(r"[0-9a-f]{32}", run_id) or
                any(type(revision) is not str or not re.fullmatch(r"[0-9a-f]{40}", revision)
                    for revision in (candidate, old, harness))):
            return None
        parse_audit(audit_bytes)
        intent_bytes = read_private(root / "intent.json", 4096)
        parent_bytes = read_private(root / "parent", 64)
        wait_bytes = read_private(root / "wait.log", 4096)
        receipt_bytes = read_private(root / "receipt.json", 65536)
        intent = strict_json(intent_bytes)
        receipt = strict_json(receipt_bytes)
        final = strict_json(read_private(root / "launch.json", 4096))
        expected_intent = {"format": 1, "run_id": run_id, "candidate_revision": candidate,
                           "old_revision": old, "harness_revision": harness,
                           "audit_sha256": hashlib.sha256(audit_bytes).hexdigest()}
        if type(intent) is not dict or intent != expected_intent or type(intent.get("format")) is not int:
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
        return summary
    except (KeyError, OSError, TypeError, UnicodeError, ValueError):
        return None
