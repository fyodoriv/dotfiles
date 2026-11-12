"""Resolve fixed source entries from independently supplied GitHub records."""
import re
import ssl
from http.client import HTTPException
import time
from urllib.error import HTTPError, URLError
from urllib.request import HTTPRedirectHandler, HTTPSHandler, ProxyHandler, Request, build_opener
from hook_source_snapshot import EXPECTED
from hook_trusted_launch import strict_json


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


def decode_record(raw, limit):
    """Decode one bounded record while rejecting duplicate JSON keys."""
    try:
        if type(raw) is not bytes or type(limit) is not int or limit < 0 or len(raw) > limit:
            return None
        value = strict_json(raw)
        return value if type(value) is dict else None
    except (TypeError, UnicodeError, ValueError, RecursionError):
        return None


API_ROOT = "https://api.github.com/repos/fyodoriv/dotfiles/git"


class RefuseRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def restricted_opener():
    return build_opener(ProxyHandler({}), RefuseRedirect(), HTTPSHandler(context=ssl.create_default_context())).open


class RecordFetcher:
    """Bound individual and aggregate public API record reads."""
    def __init__(self, opener, per_record=1_000_000, total=8_000_000, timeout=10):
        if (not callable(opener) or type(per_record) is not int or not 0 < per_record <= 1_000_000 or
                type(total) is not int or not 0 < total <= 8_000_000 or
                type(timeout) not in (int, float) or not 0 < timeout <= 10):
            raise ValueError("invalid fetch bounds")
        self.opener, self.per_record, self.remaining, self.timeout = opener, per_record, total, timeout
        self.calls, self.failed = 0, False

    def fetch(self, kind, revision):
        if (self.failed or self.calls >= 12 or kind not in ("commits", "trees") or
                not object_id(revision) or self.remaining <= 0):
            self.failed = True
            return None
        self.calls += 1
        url = API_ROOT + "/" + kind + "/" + revision
        limit = min(self.per_record, self.remaining)
        request = Request(url, headers={"Accept": "application/vnd.github+json", "User-Agent": "dotfiles-source-audit"})
        started = time.monotonic()
        try:
            with self.opener(request, timeout=self.timeout) as response:
                if response.status != 200 or response.geturl() != url:
                    self.failed = True
                    return None
                raw = response.read(limit + 1)
            self.remaining = max(0, self.remaining - len(raw))
            if time.monotonic() - started > self.timeout or decode_record(raw, limit) is None:
                self.failed = True
                return None
            return raw
        except (OSError, HTTPException, HTTPError, URLError, TypeError, ValueError):
            self.failed = True
            return None
