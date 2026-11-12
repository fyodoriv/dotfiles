"""Resolve fixed source entries from independently supplied GitHub records."""
import re
from hook_source_snapshot import EXPECTED


def object_id(value):
    return type(value) is str and re.fullmatch(r"[0-9a-f]{40}", value) is not None


def resolve(old, candidate, commits, trees):
    try:
        if (not object_id(old) or not object_id(candidate) or old == candidate or
                type(commits) is not dict or type(trees) is not dict):
            return None
        roots = {}
        for side, revision in (("old", old), ("new", candidate)):
            commit = commits[revision]
            if (type(commit) is not dict or commit.get("sha") != revision or
                    type(commit.get("tree")) is not dict or not object_id(commit["tree"].get("sha"))):
                return None
            roots[side] = commit["tree"]["sha"]
        def entries(tree_id):
            tree = trees[tree_id]
            if (type(tree) is not dict or tree.get("sha") != tree_id or tree.get("truncated") is not False or
                    type(tree.get("tree")) is not list or len(tree["tree"]) > 100000):
                raise ValueError("invalid tree")
            result = {}
            for row in tree["tree"]:
                if (type(row) is not dict or type(row.get("path")) is not str or not row["path"] or
                        "/" in row["path"] or row["path"] in (".", "..") or row["path"] in result):
                    raise ValueError("invalid entry")
                result[row["path"]] = row
            return result
        result = {}
        for side, path, mode in EXPECTED:
            tree_id = roots[side]
            parts = path.split("/")
            for index, part in enumerate(parts):
                row = entries(tree_id)[part]
                leaf = index == len(parts) - 1
                if (row.get("type") != ("blob" if leaf else "tree") or
                        row.get("mode") != (mode if leaf else "040000") or not object_id(row.get("sha"))):
                    return None
                tree_id = row["sha"]
            result[side, path] = (mode, tree_id)
        return result
    except (KeyError, TypeError, ValueError):
        return None
