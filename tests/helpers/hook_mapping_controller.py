"""Pre-fetch intent ordering and private retention preparation."""
from pathlib import Path

import hook_mapping_intent as intent
import hook_remote_mapping as remote


def collect_private(root, identity, run_id, old, candidate, request_digest, fetch):
    """Retain records only after intent checks; caller establishes provenance."""
    try:
        root = Path(root)
        if (not intent.verify(root, identity, run_id, old, candidate, request_digest) or
                {p.name for p in root.iterdir()} != {"request.json"}):
            return None
        result = remote.collect(old, candidate, fetch)
        if (result is None or not intent.verify(root, identity, run_id, old, candidate, request_digest) or
                {p.name for p in root.iterdir()} != {"request.json"}):
            return None
        archive_digest = remote.store_archive(root, identity, run_id, old, candidate, result["records"])
        if (archive_digest is None or not intent.verify(root, identity, run_id, old, candidate, request_digest) or
                {p.name for p in root.iterdir()} != {"request.json", "mapping.json"} or
                remote.read_archive(root, identity, archive_digest, run_id, old, candidate) != result["records"]):
            return None
        return archive_digest
    except (OSError, TypeError, ValueError):
        return None
