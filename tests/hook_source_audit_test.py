import hashlib
import json
from pathlib import Path
import sys
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).parent / "helpers"))
import hook_source_audit as audit


class SourceAuditControls(unittest.TestCase):
    def fixture(self):
        manifest = b"private manifest"
        value = {"format": 1, "run_id": "a" * 32, "old_revision": "b" * 40,
                 "candidate_revision": "c" * 40, "manifest_sha256": hashlib.sha256(manifest).hexdigest(),
                 "local_filesystems": True, "roots": {
                     "old": {"path": "/scratch/old", "dev": 1, "ino": 2},
                     "new": {"path": "/scratch/new", "dev": 1, "ino": 3}}}
        return value, manifest

    def test_expected_private_audit_has_both_root_identities(self):
        value, manifest = self.fixture()
        self.assertIsNotNone(audit.parse_source_audit(json.dumps(value).encode(), manifest,
                                                       "a" * 32, "b" * 40, "c" * 40))

    def test_wrong_or_ambiguous_audit_is_refused(self):
        for mutation in ("wrong_id", "wrong_revision", "wrong_manifest", "nonlocal", "bool_device", "bool_inode",
                         "relative_root", "unnormalized", "nul_path", "same_root", "same_path", "duplicate", "extra"):
            with self.subTest(mutation=mutation):
                value, manifest = self.fixture()
                if mutation == "wrong_id": value["run_id"] = "f" * 32
                elif mutation == "wrong_revision": value["old_revision"] = "f" * 40
                elif mutation == "wrong_manifest": value["manifest_sha256"] = "f" * 64
                elif mutation == "nonlocal": value["local_filesystems"] = False
                elif mutation == "bool_device": value["roots"]["old"]["dev"] = True
                elif mutation == "bool_inode": value["roots"]["old"]["ino"] = True
                elif mutation == "relative_root": value["roots"]["old"]["path"] = "relative"
                elif mutation == "unnormalized": value["roots"]["old"]["path"] = "/scratch/../old"
                elif mutation == "nul_path": value["roots"]["old"]["path"] = "/scratch/old\0x"
                elif mutation == "same_root": value["roots"]["new"] = dict(value["roots"]["old"])
                elif mutation == "same_path": value["roots"]["new"]["path"] = value["roots"]["old"]["path"]
                elif mutation == "extra": value["private"] = "PRIVATE_CANARY"
                raw = json.dumps(value).encode()
                if mutation == "duplicate": raw = b'{"format":1,' + raw[1:]
                self.assertIsNone(audit.parse_source_audit(raw, manifest, "a" * 32, "b" * 40, "c" * 40))


if __name__ == "__main__":
    unittest.main()
