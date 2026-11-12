"""Read a private source snapshot against independently retained audit bytes."""
import hashlib
from pathlib import Path
import re

from hook_pair_receipts import private_dir
from hook_trusted_launch import read_private, strict_json

HOOK = "agent-hooks/block-dangerous-git.sh"
BOOTSTRAP = "agent-hooks/bootstrap-endpoint-path.sh"
PARSER = "agent-hooks/plain-document-write.jq"
ENDPOINT = "lib/dotfiles-endpoint-paths.sh"
STATUS = "agent-hooks/literal-status-only.sh"
SHARED = ((HOOK, "100755"), (BOOTSTRAP, "100755"), (PARSER, "100644"), (ENDPOINT, "100644"))
EXPECTED = tuple((side, path, mode) for side in ("old", "new") for path, mode in
                 (SHARED + (((STATUS, "100755"),) if side == "new" else ())))


def read_snapshot(root, expected_manifest, run_id, old_revision, candidate_revision):
    try:
        root = Path(root)
        if (not private_dir(root) or type(expected_manifest) is not bytes or len(expected_manifest) > 65536 or
                type(run_id) is not str or not re.fullmatch(r"[0-9a-f]{32}", run_id) or
                any(type(value) is not str or not re.fullmatch(r"[0-9a-f]{40}", value)
                    for value in (old_revision, candidate_revision))):
            return None
        if read_private(root / "manifest.json", 65536) != expected_manifest:
            return None
        manifest = strict_json(expected_manifest)
        if (type(manifest) is not dict or set(manifest) != {"format", "run_id", "old_revision", "candidate_revision", "files"} or
                type(manifest["format"]) is not int or manifest["format"] != 1 or manifest["run_id"] != run_id or
                manifest["old_revision"] != old_revision or manifest["candidate_revision"] != candidate_revision or
                type(manifest["files"]) is not list or len(manifest["files"]) != len(EXPECTED)):
            return None
        if {entry.name for entry in root.iterdir()} != {"manifest.json", *(f"{i:03}.src" for i in range(len(EXPECTED)))}:
            return None
        result = {}
        for index, (row, (side, path, mode)) in enumerate(zip(manifest["files"], EXPECTED)):
            if (type(row) is not dict or set(row) != {"side", "path", "mode", "file", "blob", "sha256"} or
                    row["side"] != side or row["path"] != path or row["mode"] != mode or row["file"] != f"{index:03}.src" or
                    type(row["blob"]) is not str or not re.fullmatch(r"[0-9a-f]{40}", row["blob"]) or
                    type(row["sha256"]) is not str or not re.fullmatch(r"[0-9a-f]{64}", row["sha256"])):
                return None
            data = read_private(root / row["file"], 2_000_000)
            # Git object IDs identify repository bytes; SHA-256 adds a separate digest.
            oid = hashlib.sha1(b"blob " + str(len(data)).encode("ascii") + b"\0" + data,
                               usedforsecurity=False).hexdigest()
            if oid != row["blob"] or hashlib.sha256(data).hexdigest() != row["sha256"]:
                return None
            result[(side, path)] = data
        if any(result[("old", path)] != result[("new", path)] for path in (BOOTSTRAP, PARSER, ENDPOINT)):
            return None
        return result
    except (KeyError, OSError, TypeError, UnicodeError, ValueError):
        return None
