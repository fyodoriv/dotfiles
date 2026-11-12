#!/usr/bin/env python3
"""Compare selected historical bin interpreter boundaries with pinned sources."""
import copy
import json
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
from strict_receipt_json import same_json, strict_json

CURRENT = "0490b7b981c976c03cde98e064fffb6e38623622"
RECEIPT = Path("docs/plans/current-bin-boundaries.json")


def git(*args):
    return subprocess.check_output(["git", *args])


def generate():
    historical = strict_json(git("show", CURRENT + ":docs/plans/rust-bin-source-inventory-evidence.json"))
    old = historical["revision"]
    boundaries = historical["embedded_boundaries"]
    if len(boundaries) != 7 or sum(len(row["call_lines"]) for row in boundaries) != 8:
        raise ValueError("unexpected historical boundary scope")
    paths = sorted({row["path"] for row in boundaries})
    if len(paths) != 3:
        raise ValueError("unexpected historical source scope")
    blobs, lines = {}, {}
    for revision in (old, CURRENT):
        for path in paths:
            blobs[revision, path] = git("rev-parse", f"{revision}:{path}").decode("ascii").strip()
            lines[revision, path] = git("show", f"{revision}:{path}").decode("utf-8").splitlines()
    rows = []
    for boundary in boundaries:
        path = boundary["path"]
        def mapped(numbers):
            result = []
            for number in numbers:
                text = lines[old, path][number - 1]
                matches = [i + 1 for i, line in enumerate(lines[CURRENT, path]) if line == text]
                if len(matches) != 1:
                    raise ValueError("ambiguous or missing source anchor")
                result.append({"old_line": number, "current_line": matches[0], "text": text})
            return result
        rows.append({"name": boundary["name"], "path": path, "interpreter": boundary["interpreter"],
                     "old_blob": blobs[old, path], "current_blob": blobs[CURRENT, path],
                     "definitions": mapped(boundary["definition_lines"]), "calls": mapped(boundary["call_lines"])})
    return {"format": 1, "historical_revision": old, "current_revision": CURRENT, "boundaries": rows}


def main():
    if sys.argv[1:] not in (["--generate"], ["--check"]):
        raise SystemExit("usage: current-bin-boundaries.py --generate|--check")
    expected = generate()
    if sys.argv[1:] == ["--generate"]:
        print(json.dumps(expected, indent=2))
        return
    receipt = strict_json(RECEIPT.read_text())
    if not same_json(receipt, expected):
        raise SystemExit("boundary receipt does not match pinned sources")
    count = 0
    for index in range(len(receipt["boundaries"])):
        for field in ("remove", "duplicate", "name", "path", "old_blob", "current_blob", "definition", "call"):
            case = copy.deepcopy(receipt)
            rows = case["boundaries"]
            if field == "remove":
                rows.pop(index)
            elif field == "duplicate":
                rows.append(copy.deepcopy(rows[index]))
            elif field == "definition":
                rows[index]["definitions"][0]["text"] = "planted error"
            elif field == "call":
                rows[index]["calls"][0]["current_line"] = -1
            else:
                rows[index][field] = "planted error"
            if case == expected:
                raise SystemExit("a planted error was accepted")
            count += 1
    print(f"checked {len(receipt['boundaries'])} boundaries and 8 calls; rejected {count} planted errors")


if __name__ == "__main__":
    main()
