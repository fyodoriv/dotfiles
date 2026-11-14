"""Validate retained source-audit metadata; it is not attestation.

The local-filesystem assertion covers both source roots and the run directory.
"""
import hashlib
import os
import re

from hook_trusted_launch import strict_json


def parse_source_audit(raw, manifest, run_id, old_revision, candidate_revision):
    try:
        if (type(raw) is not bytes or len(raw) > 65536 or type(manifest) is not bytes or len(manifest) > 65536 or
                type(run_id) is not str or not re.fullmatch(r"[0-9a-f]{32}", run_id) or
                any(type(value) is not str or not re.fullmatch(r"[0-9a-f]{40}", value)
                    for value in (old_revision, candidate_revision))):
            return None
        audit = strict_json(raw)
        keys = {"format", "run_id", "old_revision", "candidate_revision", "manifest_sha256", "local_filesystems", "roots"}
        if (type(audit) is not dict or set(audit) != keys or type(audit["format"]) is not int or
                audit["format"] != 1 or audit["run_id"] != run_id or audit["old_revision"] != old_revision or
                audit["candidate_revision"] != candidate_revision or
                audit["manifest_sha256"] != hashlib.sha256(manifest).hexdigest() or
                audit["local_filesystems"] is not True or type(audit["roots"]) is not dict or
                set(audit["roots"]) != {"old", "new"}):
            return None
        identities = []
        for side in ("old", "new"):
            row = audit["roots"][side]
            if (type(row) is not dict or set(row) != {"path", "dev", "ino"} or
                    type(row["path"]) is not str or not os.path.isabs(row["path"]) or
                    os.path.normpath(row["path"]) != row["path"] or "\0" in row["path"] or
                    any(type(row[key]) is not int or row[key] <= 0 for key in ("dev", "ino"))):
                return None
            identities.append((row["dev"], row["ino"]))
        if identities[0] == identities[1] or audit["roots"]["old"]["path"] == audit["roots"]["new"]["path"]:
            return None
        return audit
    except (KeyError, OSError, TypeError, UnicodeError, ValueError):
        return None
