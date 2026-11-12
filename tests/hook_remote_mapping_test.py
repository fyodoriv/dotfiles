import copy
import json
import hashlib
from http.client import IncompleteRead
import os
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).parent / "helpers"))
import hook_remote_mapping as mapping
import hook_source_snapshot as snapshots


class MappingControls(unittest.TestCase):
    def fixture(self):
        old, new = "a" * 40, "b" * 40
        roots = {old: "c" * 40, new: "d" * 40}
        trees = {}
        commits = {rev: {"sha": rev, "tree": {"sha": tree}} for rev, tree in roots.items()}
        for index, (rev, root) in enumerate(roots.items()):
            hook_tree, lib_tree = ("e" if index == 0 else "f") * 40, ("1" if index == 0 else "2") * 40
            trees[root] = {"sha": root, "truncated": False, "tree": [
                {"path": "agent-hooks", "mode": "040000", "type": "tree", "sha": hook_tree},
                {"path": "lib", "mode": "040000", "type": "tree", "sha": lib_tree}]}
            entries = [
                {"path": "block-dangerous-git.sh", "mode": "100755", "type": "blob", "sha": "3" * 40},
                {"path": "bootstrap-endpoint-path.sh", "mode": "100755", "type": "blob", "sha": "4" * 40},
                {"path": "plain-document-write.jq", "mode": "100644", "type": "blob", "sha": "5" * 40}]
            if rev == new:
                entries.append({"path": "literal-status-only.sh", "mode": "100755", "type": "blob", "sha": "6" * 40})
            trees[hook_tree] = {"sha": hook_tree, "truncated": False, "tree": entries}
            trees[lib_tree] = {"sha": lib_tree, "truncated": False, "tree": [
                {"path": "dotfiles-endpoint-paths.sh", "mode": "100644", "type": "blob", "sha": "7" * 40}]}
        return old, new, commits, trees

    def test_exact_mapping(self):
        old, new, commits, trees = self.fixture()
        result = mapping.resolve(old, new, commits, trees)
        expected = {}
        for side in ("old", "new"):
            for name, mode, blob in (("block-dangerous-git.sh", "100755", "3"),
                                     ("bootstrap-endpoint-path.sh", "100755", "4"),
                                     ("plain-document-write.jq", "100644", "5")):
                expected[(side, "agent-hooks/" + name)] = (mode, blob * 40)
            expected[(side, "lib/dotfiles-endpoint-paths.sh")] = ("100644", "7" * 40)
        expected[("new", "agent-hooks/literal-status-only.sh")] = ("100755", "6" * 40)
        self.assertEqual(result, expected)

    def test_collection_binds_each_requested_record(self):
        old, new, commits, trees = self.fixture()
        records = {(kind, key): json.dumps(value).encode() for kind, group in
                   (("commits", commits), ("trees", trees)) for key, value in group.items()}
        requests = []
        def fetch(kind, key):
            requests.append((kind, key))
            return records.get((kind, key))
        result = mapping.collect(old, new, fetch)
        self.assertIsNotNone(result)
        self.assertEqual(len(result["mapping"]), 9)
        self.assertEqual(set(result["records"]), set(requests))
        self.assertEqual(result["records"], {key: records[key] for key in requests})
        self.assertEqual(result["mapping"], mapping.resolve(old, new, commits, trees))
        self.assertEqual(len(requests), 8)
        for key in list(records):
            changed = records.pop(key)
            self.assertIsNone(mapping.collect(old, new, fetch))
            records[key] = changed
        first = ("trees", "e" * 40)
        records[first] = json.dumps(trees["f" * 40]).encode()
        self.assertIsNone(mapping.collect(old, new, fetch))

    def test_collection_reuses_shared_trees_and_rejects_bad_records(self):
        old, new, commits, trees = self.fixture()
        trees["c" * 40]["tree"][0]["sha"] = "f" * 40
        trees["c" * 40]["tree"][1]["sha"] = "2" * 40
        records = {(kind, key): json.dumps(value).encode() for kind, group in
                   (("commits", commits), ("trees", trees)) for key, value in group.items()}
        calls = []
        def fetch(kind, oid):
            calls.append((kind, oid))
            return records.get((kind, oid))
        self.assertIsNotNone(mapping.collect(old, new, fetch))
        self.assertEqual(len(calls), 6)
        for key, bad in ((("commits", old), b'{"sha":1,"sha":2}'),
                         (("trees", "f" * 40), b'{'),
                         (("commits", new), json.dumps(commits[old]).encode()),
                         (("trees", "c" * 40), json.dumps(trees["d" * 40]).encode())):
            original = records[key]
            records[key] = bad
            self.assertIsNone(mapping.collect(old, new, fetch))
            records[key] = original
        duplicate = copy.deepcopy(trees["c" * 40])
        duplicate["tree"].append(copy.deepcopy(duplicate["tree"][0]))
        records[("trees", "c" * 40)] = json.dumps(duplicate).encode()
        self.assertIsNone(mapping.collect(old, new, fetch))
        self.assertIsNone(mapping.collect(old, new, lambda *args: (_ for _ in ()).throw(RuntimeError("private"))))

    def test_independent_replay_matches_every_manifest_blob(self):
        old, new, commits, trees = self.fixture()
        run_id = "9" * 32
        raw_records = {(kind, key): json.dumps(value).encode() for kind, group in
                       (("commits", commits), ("trees", trees)) for key, value in group.items()}
        resolved = mapping.resolve(old, new, commits, trees)
        files = [{"side": side, "path": path, "mode": mode, "file": f"{index:03}.src",
                  "blob": resolved[(side, path)][1], "sha256": "8" * 64}
                 for index, (side, path, mode) in enumerate(snapshots.EXPECTED)]
        manifest = json.dumps({"format": 1, "run_id": run_id, "old_revision": old,
                               "candidate_revision": new, "files": files}).encode()
        self.assertTrue(mapping.verify_retained(old, new, run_id, manifest, raw_records))
        for mutation in ("blob", "mode", "missing", "extra", "wrong_record", "wrong_run", "wrong_revision", "duplicate_json", "oversize", "too_many", "total_limit"):
            with self.subTest(mutation=mutation):
                retained = dict(raw_records)
                changed = copy.deepcopy(files)
                if mutation == "blob": changed[0]["blob"] = "9" * 40
                elif mutation == "mode": changed[0]["mode"] = "100644"
                elif mutation == "duplicate_json": retained[("commits", old)] = b'{"sha":1,"sha":2}'
                elif mutation == "oversize": retained[("commits", old)] = b"x" * 1_000_001
                elif mutation == "too_many":
                    for i in range(5): retained[("trees", str(i) * 40)] = b"{}"
                elif mutation == "total_limit":
                    retained = {("trees", str(i) * 40): b"x" * 1_000_000 for i in range(9)}
                elif mutation == "missing": retained.pop(("trees", "e" * 40))
                elif mutation == "extra": retained[("trees", "9" * 40)] = b"{}"
                elif mutation == "wrong_record": retained[("trees", "e" * 40)] = retained[("trees", "f" * 40)]
                data = json.dumps({"format": 1, "run_id": run_id, "old_revision": old,
                                   "candidate_revision": new, "files": changed}).encode()
                self.assertFalse(mapping.verify_retained(old, "0" * 40 if mutation == "wrong_revision" else new,
                                                         "0" * 32 if mutation == "wrong_run" else run_id, data, retained))

    def test_private_archive_requires_external_digest_and_identity(self):
        old, new, commits, trees = self.fixture()
        run_id = "9" * 32
        records = {(kind, key): json.dumps(value).encode() for kind, group in
                   (("commits", commits), ("trees", trees)) for key, value in group.items()}
        archive = mapping.encode_archive(run_id, old, new, records)
        digest = hashlib.sha256(archive).hexdigest()
        self.assertEqual(mapping.decode_archive(archive, digest, run_id, old, new), records)
        self.assertIsNone(mapping.decode_archive(archive + b" ", digest, run_id, old, new))
        self.assertIsNone(mapping.decode_archive(archive, "0" * 64, run_id, old, new))
        self.assertIsNone(mapping.decode_archive(archive, digest, "0" * 32, old, new))
        self.assertIsNone(mapping.decode_archive(archive, digest, run_id, old, "0" * 40))
        obj = json.loads(archive)
        for mutation in ("duplicate", "origin", "bad_base64", "padding", "extra", "wrong_format", "missing_record", "extra_record"):
            value = copy.deepcopy(obj)
            if mutation == "duplicate": value["records"].append(copy.deepcopy(value["records"][0]))
            elif mutation == "origin": value["origin"] = "https://example.com"
            elif mutation == "bad_base64": value["records"][0]["body"] = "!"
            elif mutation == "padding": value["records"][0]["body"] = "YQ="
            elif mutation == "missing_record": value["records"].pop()
            elif mutation == "extra_record": value["records"].append({"kind": "trees", "sha": "0" * 40, "body": "e30="})
            elif mutation == "extra": value["unexpected"] = True
            else: value["format"] = True
            raw = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
            self.assertIsNone(mapping.decode_archive(raw, hashlib.sha256(raw).hexdigest(), run_id, old, new))
        for raw in (archive + b" ", b'{"format":1,' + archive[1:]):
            self.assertIsNone(mapping.decode_archive(raw, hashlib.sha256(raw).hexdigest(), run_id, old, new))

    def test_bounded_strict_record_decoder(self):
        raw = b'{"sha":"' + b'a' * 40 + b'","tree":{"sha":"' + b'b' * 40 + b'"}}'
        self.assertEqual(mapping.decode_record(raw, len(raw))["sha"], "a" * 40)
        for invalid in (raw + b" ", b'{"sha":1,"sha":2}', b'[]', b'\xff', b'{'):
            self.assertIsNone(mapping.decode_record(invalid, len(raw)))
        self.assertIsNone(mapping.decode_record(raw, len(raw) - 1))
        self.assertIsNone(mapping.decode_record(raw, True))

    def test_bounded_fetch_rejects_wrong_origins_and_responses(self):
        class Response:
            def __init__(self, url, data, status=200):
                self.url, self.data, self.status = url, data, status
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def geturl(self): return self.url
            def read(self, limit): return self.data[:limit]
        url = mapping.API_ROOT + "/commits/" + "a" * 40
        good = b'{"sha":"' + b'a' * 40 + b'"}'
        def opener(request, timeout):
            self.assertEqual(request.full_url, url)
            self.assertGreater(timeout, 0)
            return Response(url, good)
        fetcher = mapping.RecordFetcher(opener, per_record=100, total=len(good))
        self.assertEqual(fetcher.fetch("commits", "a" * 40), good)
        self.assertIsNone(fetcher.fetch("commits", "a" * 40))
        self.assertIsNone(mapping.RecordFetcher(opener).fetch("commits/../trees", "a" * 40))
        self.assertIsNone(mapping.RecordFetcher(opener).fetch("commits", "a" * 39))
        for response in (Response("https://example.com", good), Response(url, good, 302),
                         Response(url, b"x" * 101), Response(url, b'{"x":1,"x":2}')):
            with self.subTest(response=response):
                self.assertIsNone(mapping.RecordFetcher(lambda request, timeout: response, per_record=100).fetch("commits", "a" * 40))

    def test_fetcher_is_direct_and_fails_closed(self):
        from urllib.request import ProxyHandler, HTTPSHandler
        with patch.dict(os.environ, {"HTTPS_PROXY": "http://127.0.0.1:1234", "https_proxy": "http://127.0.0.1:1234"}):
            opener = mapping.restricted_opener().__self__
            self.assertFalse(any(isinstance(h, ProxyHandler) and h.proxies for h in opener.handlers))
            self.assertTrue(any(isinstance(h, HTTPSHandler) and h._context.check_hostname for h in opener.handlers))
        calls = []
        def fail(request, timeout):
            calls.append(request)
            self.assertIsNone(request.get_header("Proxy-authorization"))
            raise OSError("injected")
        fetcher = mapping.RecordFetcher(fail)
        self.assertIsNone(fetcher.fetch("trees", "a" * 40))
        self.assertIsNone(fetcher.fetch("trees", "a" * 40))
        self.assertEqual(len(calls), 1)
        for timeout in (float("nan"), float("inf"), 0, 11, True):
            with self.subTest(timeout=timeout), self.assertRaises(ValueError):
                mapping.RecordFetcher(fail, timeout=timeout)

    def test_fetcher_bounds_calls_and_stops_after_truncation(self):
        class Response:
            status = 200
            def __init__(self, url, data): self.url, self.data = url, data
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def geturl(self): return self.url
            def read(self, size): return self.data[:size]
        calls = []
        def opener(request, timeout):
            calls.append(request.full_url)
            return Response(request.full_url, b"{}")
        fetcher = mapping.RecordFetcher(opener, per_record=10, total=30)
        for _ in range(12): self.assertEqual(fetcher.fetch("trees", "a" * 40), b"{}")
        self.assertIsNone(fetcher.fetch("trees", "a" * 40))
        self.assertEqual(len(calls), 12)
        short = mapping.RecordFetcher(opener, per_record=10, total=3)
        self.assertEqual(short.fetch("trees", "a" * 40), b"{}")
        self.assertIsNone(short.fetch("trees", "a" * 40))
        self.assertIsNone(short.fetch("trees", "a" * 40))
        def truncated(request, timeout):
            class BrokenResponse(Response):
                def read(self, size): raise IncompleteRead(b"{")
            return BrokenResponse(request.full_url, b"")
        broken = mapping.RecordFetcher(truncated)
        self.assertIsNone(broken.fetch("trees", "a" * 40))
        self.assertTrue(broken.failed)
        self.assertIsNone(mapping.decode_record(b"[" * 2000 + b"]" * 2000, 5000))

    def test_rejects_unverified_commit_and_tree_responses(self):
        for mutation in ("commit_sha", "root", "tree_sha", "truncated", "missing_tree", "duplicate", "missing_path", "mode", "type", "blob", "bad_path", "bool_truncated", "branch_type", "branch_mode", "bad_revision", "missing_commit", "branch_sha", "row_type", "null_root"):
            with self.subTest(mutation=mutation):
                old, new, commits, trees = self.fixture()
                if mutation == "branch_sha": trees["c" * 40]["tree"][0]["sha"] = "bad"
                elif mutation == "row_type": trees["c" * 40]["tree"].append(None)
                elif mutation == "null_root": commits[old]["tree"] = None
                elif mutation == "branch_type": trees["c" * 40]["tree"][0]["type"] = "blob"
                elif mutation == "branch_mode": trees["c" * 40]["tree"][0]["mode"] = "120000"
                elif mutation == "bad_revision": old = "a" * 39
                elif mutation == "missing_commit": del commits[old]
                elif mutation == "commit_sha": commits[old]["sha"] = "9" * 40
                elif mutation == "root": commits[old]["tree"]["sha"] = "9" * 40
                elif mutation == "tree_sha": trees["c" * 40]["sha"] = "9" * 40
                elif mutation == "truncated": trees["c" * 40]["truncated"] = True
                elif mutation == "bool_truncated": trees["c" * 40]["truncated"] = 0
                elif mutation == "missing_tree": del trees["e" * 40]
                elif mutation == "duplicate": trees["e" * 40]["tree"].append(copy.deepcopy(trees["e" * 40]["tree"][0]))
                elif mutation == "missing_path": trees["e" * 40]["tree"].pop(0)
                elif mutation == "mode": trees["e" * 40]["tree"][0]["mode"] = "120000"
                elif mutation == "type": trees["e" * 40]["tree"][0]["type"] = "commit"
                elif mutation == "blob": trees["e" * 40]["tree"][0]["sha"] = "bad"
                else: trees["e" * 40]["tree"][0]["path"] = "../block-dangerous-git.sh"
                self.assertIsNone(mapping.resolve(old, new, commits, trees))

if __name__ == "__main__":
    unittest.main()
