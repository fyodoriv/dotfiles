#!/usr/bin/env python3
"""Trusted-controller preparation for private, exclusive hook pair timings."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

sys.dont_write_bytecode = True
from hook_pair_binding import verify_pair_link
from hook_pair_receipts import read_attempts
from hook_rss_provenance import installed_root, source_clean
from hook_pair_private import expected_parent_valid, read_private
from hook_remote_mapping import decode_archive, store_archive, verify_source_binding
from hook_run_locality import check as run_locality_check
from hook_snapshot_acquire import acquire
from hook_source_audit import parse_source_audit
from hook_trusted_launch import (audited_inputs_valid, create_private_log, launch_and_wait, matches_digest,
                                 parse_audit, reserve_run, resolve_perl, write_private_json)

PAIR_TRACKED = ("tests/helpers/hook_effective_helper.py", "tests/helpers/hook_run_locality.py", "tests/helpers/hook_remote_mapping.py", "tests/helpers/hook_pair_private.py", "tests/helpers/hook_pair_launcher.py", "tests/helpers/hook_pair_binding.py",
                "tests/helpers/hook_pair_receipts.py", "tests/helpers/hook_status_pairs.py",
                "tests/helpers/hook_pair_worker.py", "tests/helpers/hook_source_snapshot.py",
                "tests/helpers/hook_snapshot_acquire.py", "tests/helpers/hook_source_audit.py",
                "tests/helpers/hook_rss_provenance.py",
                "tests/helpers/hook_trusted_launch.py", "bin/heavy-run")
OLD_TRACKED = ("agent-hooks/block-dangerous-git.sh", "agent-hooks/bootstrap-endpoint-path.sh",
               "agent-hooks/plain-document-write.jq", "lib/dotfiles-endpoint-paths.sh")


def old_source_available(root, revision):
    for path in OLD_TRACKED:
        result = subprocess.run(["git", "cat-file", "-e", f"{revision}:{path}"], cwd=root,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.returncode:
            return False
    return True


def pair_source_clean(root, revision):
    for path in PAIR_TRACKED:
        result = subprocess.run(["git", "cat-file", "-e", f"{revision}:{path}"], cwd=root,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.returncode or (root / path).is_symlink() or not (root / path).is_file():
            return False
    result = subprocess.run(["git", "diff", "--quiet", revision, "--", *PAIR_TRACKED], cwd=root,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return result.returncode == 0


def run_qualified(root, candidate, old, harness_revision, audit_path, environ, run_id,
                  source_audit_path=None, source_manifest_path=None, mapping_path=None, expected_mapping_sha256=None,
                  expected_source_audit_sha256=None, locality_inspector=None):
    if (type(run_id) is not str or not re.fullmatch(r"[0-9a-f]{32}", run_id) or
            any(type(revision) is not str or not re.fullmatch(r"[0-9a-f]{40}", revision)
                for revision in (candidate, old, harness_revision))):
        return False
    launcher = root / "bin/heavy-run"
    harness = root / "tests/helpers/hook_pair_launcher.py"
    wrapper = root / "tests/helpers/hook_trusted_launch.py"
    try:
        audit_bytes = read_private(audit_path, 4096)
        audit = parse_audit(audit_bytes)
        source_audit_bytes = read_private(source_audit_path, 65536)
        source_manifest = read_private(source_manifest_path, 65536)
        mapping_archive = read_private(mapping_path, 11_000_000)
        source_audit = parse_source_audit(source_audit_bytes, source_manifest, run_id, old, candidate)
        if (Path(__file__).resolve() != harness.resolve() or not matches_digest(wrapper, audit["wrapper"]) or
                not audited_inputs_valid(launcher, harness, environ, audit) or not installed_root(root) or
                not source_clean(root, candidate) or not pair_source_clean(root, harness_revision) or
                not old_source_available(root, old) or source_audit is None or
                not verify_source_binding(run_id, old, candidate, source_manifest, source_audit_bytes, mapping_archive,
                                          expected_source_audit_sha256, expected_mapping_sha256) or
                source_audit["roots"]["new"]["path"] != str(root)):
            return False
        parent = Path(environ["HOME"]) / ".local/state/dotfiles/rust-migration"
        run_dir = reserve_run(parent, run_id)
        roots = {side: Path(source_audit["roots"][side]["path"]) for side in ("old", "new")}
        identities = {side: (source_audit["roots"][side]["dev"], source_audit["roots"][side]["ino"])
                      for side in ("old", "new")}
        info = run_dir.stat()
        if not run_locality_check(run_dir, (info.st_dev, info.st_ino), locality_inspector):
            return False
        if not acquire(run_dir, source_manifest, run_id, old, candidate, roots, identities, (info.st_dev, info.st_ino)):
            return False
        records = decode_archive(mapping_archive, expected_mapping_sha256, run_id, old, candidate)
        if (records is None or store_archive(run_dir, (info.st_dev, info.st_ino), run_id, old, candidate, records) !=
                expected_mapping_sha256):
            return False
        wait_log = create_private_log(run_dir)
        intent = {"format": 1, "run_id": run_id, "candidate_revision": candidate, "old_revision": old,
                  "harness_revision": harness_revision, "audit_sha256": hashlib.sha256(audit_bytes).hexdigest(),
                  "source_audit_sha256": expected_source_audit_sha256,
                  "source_manifest_sha256": hashlib.sha256(source_manifest).hexdigest(),
                  "mapping_sha256": expected_mapping_sha256}
        write_private_json(run_dir / "intent.json", intent)
        child_env = dict(environ)
        child_env.update({"DOTFILES_DIR": str(root), "HEAVY_RUN_WAIT_LOG": str(wait_log),
                          "HOOK_PAIR_RUN_DIR": str(run_dir), "HOOK_PAIR_RUN_ID": run_id,
                          "HOOK_PAIR_CANDIDATE": candidate, "HOOK_PAIR_OLD": old,
                          "HOOK_PAIR_HARNESS_REVISION": harness_revision,
                          "HOOK_PAIR_AUDIT_SHA256": hashlib.sha256(audit_bytes).hexdigest(),
                          "HOOK_PAIR_SOURCE_AUDIT_SHA256": expected_source_audit_sha256,
                          "HOOK_PAIR_MANIFEST_SHA256": hashlib.sha256(source_manifest).hexdigest(),
                          "HOOK_PAIR_MAPPING_SHA256": expected_mapping_sha256,
                          "HOOK_RSS_BASH_ENV_SHA256": audit["BASH_ENV"], "HOOK_RSS_ENV_SHA256": audit["ENV"]})
        selected_perl = resolve_perl(child_env, str(wait_log))
        if selected_perl != resolve_perl(environ) or not matches_digest(selected_perl, audit["perl"]):
            return False
        process, status = launch_and_wait(launcher, [sys.executable, str(harness), "--collect"], run_dir, child_env, root)
        if (status != 0 or not expected_parent_valid(run_dir / "parent", process.pid) or
                not source_clean(root, candidate) or not pair_source_clean(root, harness_revision) or
                not old_source_available(root, old) or
                not matches_digest(wrapper, audit["wrapper"]) or
                not audited_inputs_valid(launcher, harness, environ, audit) or
                resolve_perl(child_env, str(wait_log)) != selected_perl or
                read_private(audit_path, 4096) != audit_bytes or
                read_private(source_audit_path, 65536) != source_audit_bytes or
                read_private(source_manifest_path, 65536) != source_manifest or
                read_private(mapping_path, 11_000_000) != mapping_archive):
            return False
        attempts = read_attempts(run_dir, run_id)
        if attempts is None:
            return False
        raw = lambda name, limit: read_private(run_dir / name, limit)
        attempt_bytes = json.dumps(attempts, sort_keys=True, separators=(",", ":")).encode()
        final = {"format": 1, "intent_sha256": hashlib.sha256(raw("intent.json", 4096)).hexdigest(),
                 "parent_pid": process.pid, "parent_sha256": hashlib.sha256(raw("parent", 64)).hexdigest(),
                 "wait_sha256": hashlib.sha256(raw("wait.log", 4096)).hexdigest(),
                 "receipt_sha256": hashlib.sha256(raw("receipt.json", 65536)).hexdigest(),
                 "attempts_sha256": hashlib.sha256(attempt_bytes).hexdigest(), "verdict": "qualified"}
        staging = run_dir / "launch.pending"
        write_private_json(staging, final)
        if verify_pair_link(run_dir, run_id, candidate, old, harness_revision, audit_bytes,
                            source_audit_bytes, source_manifest, mapping_archive, expected_mapping_sha256,
                            expected_source_audit_sha256, process.pid, final_name="launch.pending") is None:
            staging.unlink()
            return False
        final_path = run_dir / "launch.json"
        os.link(staging, final_path)
        return True
    except (KeyError, OSError, TypeError, UnicodeError, ValueError, subprocess.SubprocessError, json.JSONDecodeError):
        return False
