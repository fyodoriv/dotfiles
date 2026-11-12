#!/usr/bin/env python3
"""Compare stale source identities and anchors without copying source text."""
import difflib
import json
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
from git_blob_batch import read_blobs
from strict_receipt_json import same_json, strict_json

PIN = "b3bc770aa64bc94668bd4ba9dd6bf376a726c2f5"
OUTPUT = Path("docs/plans/stale-hook-bin-ranges.json")
PATHS = ("agent-hooks/block-dangerous-git.sh", "agent-hooks/require-heavy-run.sh", "bin/kimi-goal")


def git(*args):
    return subprocess.check_output(["git", *args])


def identity(revision, path):
    entries = git("ls-tree", "-z", revision, "--", path).split(b"\0")
    entries = [entry for entry in entries if entry]
    if len(entries) != 1:
        raise ValueError("missing or ambiguous source")
    meta, raw_path = entries[0].split(b"\t", 1)
    mode, kind, blob = meta.decode("ascii").split()
    if kind != "blob" or raw_path.decode("utf-8") != path:
        raise ValueError("invalid source identity")
    return mode, blob


def generate():
    joined = strict_json(git("show", f"{PIN}:docs/plans/source-evidence-join.json"))
    candidate_revision = joined["candidate_revision"]
    candidates = [row for row in joined["candidates"] if row["path"] in PATHS]
    if len(candidates) != len(PATHS) or {r["path"] for r in candidates} != set(PATHS):
        raise ValueError("missing or duplicate candidates")
    files, ranges, anchors = [], [], []
    for row in candidates:
        path = row["path"]
        if row["status"] != "stale" or len(row["evidence"]) != 1:
            raise ValueError("ambiguous stale evidence")
        evidence = row["evidence"][0]
        receipt = strict_json(git("show", f"{PIN}:{evidence['receipt']}"))
        old = [file for file in receipt["files"] if file["path"] == path]
        if len(old) != 1 or receipt["revision"] != evidence["revision"]:
            raise ValueError("ambiguous family receipt")
        old_identity = (evidence["source_mode"], evidence["source_blob"])
        current_identity = (row["mode"], row["blob"])
        if ((old[0]["mode"], old[0]["blob"]) != old_identity or
                identity(receipt["revision"], path) != old_identity or
                identity(candidate_revision, path) != current_identity):
            raise ValueError("source identity mismatch")
        old_text, new_text = [blob.decode("utf-8").splitlines() for blob in read_blobs([old_identity[1], current_identity[1]])]
        files.append({"path": path, "old_revision": receipt["revision"], "old_mode": old_identity[0],
                      "old_blob": old_identity[1], "current_mode": current_identity[0], "current_blob": current_identity[1]})
        for op, old_start, old_end, new_start, new_end in difflib.SequenceMatcher(None, old_text, new_text, autojunk=False).get_opcodes():
            if op != "equal":
                ranges.append({"path": path, "op": op, "old_start": old_start, "old_end": old_end,
                               "new_start": new_start, "new_end": new_end})
        seen = set()
        for anchor in (a for a in receipt["anchors"] if a["path"] == path):
            line, text = anchor["line"], anchor["text"]
            if type(line) is not int or line in seen or not 1 <= line <= len(old_text) or old_text[line - 1] != text:
                raise ValueError("invalid old anchor")
            seen.add(line)
            matches = [i for i, value in enumerate(new_text, 1) if value == text]
            anchors.append({"path": path, "old_line": line, "current_lines": matches,
                            "status": "missing" if not matches else "unique" if len(matches) == 1 else "ambiguous"})
    return {"format": 1, "pin": PIN, "candidate_revision": candidate_revision,
            "files": files, "ranges": ranges, "anchors": anchors}


def main():
    if sys.argv[1:] not in (["--generate"], ["--check"]):
        raise SystemExit("usage: stale-hook-bin-ranges.py --generate|--check")
    expected = generate()
    if sys.argv[1:] == ["--generate"]:
        print(json.dumps(expected, indent=2))
        return
    actual = strict_json(OUTPUT.read_text())
    if not same_json(actual, expected):
        raise SystemExit("receipt differs from pinned sources")
    count = 0
    for key in ("files", "ranges", "anchors"):
        for index, row in enumerate(expected[key]):
            for field in ("remove", "duplicate", *row):
                if field == "remove":
                    changed = expected[key][:index] + expected[key][index + 1:]
                elif field == "duplicate":
                    changed = expected[key] + [row]
                else:
                    changed = expected[key][:index] + [{**row, field: None}] + expected[key][index + 1:]
                if same_json(changed, expected[key]):
                    raise SystemExit("a planted error was accepted")
                count += 1
    print(f"checked {len(actual['files'])} sources, {len(actual['ranges'])} ranges and {len(actual['anchors'])} anchors; rejected {count} planted errors")


if __name__ == "__main__":
    main()
