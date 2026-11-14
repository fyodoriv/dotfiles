"""Synthetic source-mapping records for launcher tests."""
import json
import hook_remote_mapping as remote
from hook_source_snapshot import parse_manifest


def archive(run_id, old, candidate, manifest):
    rows = parse_manifest(manifest, run_id, old, candidate)
    roots = {"old": "1" * 40, "new": "2" * 40}
    subtrees = {"old": {"agent-hooks": "3" * 40, "lib": "4" * 40},
                "new": {"agent-hooks": "5" * 40, "lib": "6" * 40}}
    records = {}
    for side, revision in (("old", old), ("new", candidate)):
        records[("commits", revision)] = json.dumps({"sha": revision, "tree": {"sha": roots[side]}}).encode()
        root_entries = [{"path": name, "type": "tree", "mode": "040000", "sha": oid}
                        for name, oid in subtrees[side].items()]
        records[("trees", roots[side])] = json.dumps({"sha": roots[side], "truncated": False, "tree": root_entries}).encode()
        for name, oid in subtrees[side].items():
            entries = [{"path": row["path"].split("/")[1], "type": "blob", "mode": row["mode"], "sha": row["blob"]}
                       for row in rows if row["side"] == side and row["path"].startswith(name + "/")]
            records[("trees", oid)] = json.dumps({"sha": oid, "truncated": False, "tree": entries}).encode()
    return remote.encode_archive(run_id, old, candidate, records)
