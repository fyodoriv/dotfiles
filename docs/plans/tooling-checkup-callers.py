#!/usr/bin/env python3
"""Record literal references to pinned tooling-checkup script names."""
import json
from pathlib import Path
import subprocess
import sys

REVISION = "3d3b904ea144b3b49fac3130d3f28c9ddcd205c1"
OUTPUT = Path("docs/plans/tooling-checkup-callers.json")


def generate():
    tree = {}
    raw = subprocess.check_output(["git", "ls-tree", "-r", "-z", REVISION])
    for entry in raw.split(b"\0"):
        if not entry:
            continue
        meta, raw_path = entry.split(b"\t", 1)
        mode, kind, blob = meta.decode("ascii").split()
        if kind == "blob":
            tree[raw_path.decode("utf-8")] = {"mode": mode, "blob": blob}
    paths = [path for path in tree if path.startswith("skills/tooling-checkup/scripts/")]
    if len(paths) != 11:
        raise ValueError("unexpected skill script scope")
    names = [Path(path).name for path in paths]
    if len(names) != len(set(names)):
        raise ValueError("ambiguous script basenames")
    command = ["git", "grep", "-I", "-n", "-z", "-F"]
    for name in names:
        command.extend(["-e", name])
    result = subprocess.run([*command, REVISION, "--"], stdout=subprocess.PIPE, check=False)
    if result.returncode not in (0, 1):
        raise ValueError("literal reference search failed")
    remaining, references = result.stdout, []
    prefix = (REVISION + ":").encode("ascii")
    while remaining:
        raw_path, remaining = remaining.split(b"\0", 1)
        raw_line, remaining = remaining.split(b"\0", 1)
        raw_text, remaining = remaining.split(b"\n", 1)
        if not raw_path.startswith(prefix):
            raise ValueError("unexpected search revision")
        path, text = raw_path[len(prefix):].decode("utf-8"), raw_text.decode("utf-8")
        if path not in tree:
            raise ValueError("reference path absent from tree")
        references.append({"path": path, "blob": tree[path]["blob"], "line": int(raw_line),
                           "names": [name for name in names if name in text]})
    return {"format": 1, "revision": REVISION,
            "files": [{"path": path, **tree[path]} for path in paths], "references": references}


def main():
    if sys.argv[1:] not in (["--generate"], ["--check"]):
        raise SystemExit("usage: tooling-checkup-callers.py --generate|--check")
    expected = generate()
    if sys.argv[1:] == ["--generate"]:
        print('{\n  "format": 1,')
        print(f'  "revision": {json.dumps(REVISION)},')
        for key in ("files", "references"):
            print(f'  {json.dumps(key)}: [')
            for index, row in enumerate(expected[key]):
                suffix = "," if index + 1 < len(expected[key]) else ""
                print(f"    {json.dumps(row)}{suffix}")
            print("  ]," if key == "files" else "  ]")
        print("}")
        return
    actual = json.loads(OUTPUT.read_text())
    if actual != expected:
        raise SystemExit("skill reference receipt differs from pinned sources")
    count = 0
    for key, fields in (("files", ("remove", "duplicate", "blob", "mode")),
                        ("references", ("remove", "duplicate", "blob", "line", "names"))):
        rows = actual[key]
        for index, row in enumerate(rows):
            for field in fields:
                if field == "remove":
                    changed = rows[:index] + rows[index + 1:]
                elif field == "duplicate":
                    changed = rows + [row]
                else:
                    value = -1 if field == "line" else ["planted"] if field == "names" else "planted"
                    changed = rows[:index] + [{**row, field: value}] + rows[index + 1:]
                if changed == expected[key]:
                    raise SystemExit("a planted error was accepted")
                count += 1
    print(f"checked {len(actual['files'])} scripts and {len(actual['references'])} references; rejected {count} planted errors")


if __name__ == "__main__":
    main()
