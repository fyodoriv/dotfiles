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


def collect_public(root, identity, run_id, old, candidate, request_digest):
    """Use only the fixed public API and registered default bounds."""
    try:
        fetcher = remote.RecordFetcher(remote.restricted_opener(), per_record=1_000_000,
                                       total=8_000_000, timeout=10)
        return collect_private(root, identity, run_id, old, candidate, request_digest, fetcher.fetch)
    except (OSError, TypeError, ValueError):
        return None
