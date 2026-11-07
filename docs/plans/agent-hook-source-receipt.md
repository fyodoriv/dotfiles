# Agent hook source receipt experiment

## Goal and decision

Extend the Rust migration source collection to the tracked `agent-hooks/`
family. This is one source-evidence slice, not completion of the repository
inventory or the shared validator. Reuse Git's tree and blob identities and
the existing source-receipt pattern. Do not invent the future validator schema.

The receipt will record each tracked path, mode and blob at revision
`fb319879feb3f036fe1243fbb22821b9be69c5df`, plus selected exact source-line
anchors for entrypoints and embedded interpreter boundaries. An independent
reviewer must read every source file and assess the selected boundaries.
Anchors prove the quoted lines exist; they do not by themselves prove that
every executable boundary has been found.

## Registered prediction

Question: can a pinned receipt account for the entire tracked hook source
family without accepting a false identity or quoted source line? Predict
**100%** path, mode and blob agreement with the pinned Git tree, exact source
agreement for every recorded anchor, and **zero accepted errors** in the
frozen mutation controls below. A source reviewer must independently check
all tracked files and identify any missing boundary before delivery.

Success requires the command below to exit zero, every file and recorded
anchor to be checked, all planted identity and anchor errors to be rejected,
and independent source review to pass. Any accepted planted error, omitted
tracked file, incorrect anchor or unresolved review finding rejects the
receipt format. Change the evidence method rather than lower the threshold.

Anchor: the existing [source inventory](rust-source-inventory.md); Basili,
Caldiera and Rombach (1994), Goal Question Metric; Munafò et al. (2017),
preregistration. This prediction precedes receipt collection. The source
receipt is documentation, not proof of deployed behavior or migration.

## Measurement

After this registration lands, create
`docs/plans/agent-hook-source-receipt.json`. Run the exact command below from
the repository root. It checks the pinned tree and source lines, then plants
one missing file, wrong blob, and wrong mode per file; one wrong line and
wrong text per anchor; and a duplicate anchor. Missing data is a failure.
The command does not modify the receipt, the checkout, or the Git index.

```sh
python3 - <<'PY'
import copy, json, subprocess, sys
from pathlib import Path

revision = "fb319879feb3f036fe1243fbb22821b9be69c5df"
receipt = json.loads(Path("docs/plans/agent-hook-source-receipt.json").read_text())
raw = subprocess.check_output(["git", "ls-tree", "-r", "-z", revision, "--", "agent-hooks/"])
tree = {}
for item in raw.split(b"\0"):
    if not item:
        continue
    meta, path = item.split(b"\t", 1)
    mode, kind, blob = meta.decode().split()
    if kind != "blob":
        raise SystemExit("unexpected Git object kind")
    tree[path.decode()] = {"mode": mode, "blob": blob}
if not tree:
    raise SystemExit("empty pinned source family")
lines = {path: subprocess.check_output(["git", "show", f"{revision}:{path}"]).decode().splitlines()
         for path in tree}

def valid(data):
    try:
        if set(data) != {"format", "revision", "files", "anchors"}:
            return False
        if data["format"] != 1 or data["revision"] != revision:
            return False
        files, anchors = data["files"], data["anchors"]
        if not isinstance(files, list) or not isinstance(anchors, list):
            return False
        if any(set(row) != {"path", "mode", "blob"} for row in files):
            return False
        found = {row["path"]: {"mode": row["mode"], "blob": row["blob"]} for row in files}
        if len(found) != len(files) or found != tree:
            return False
        seen = set()
        for row in anchors:
            if set(row) != {"path", "line", "text"}:
                return False
            path, number, text = row["path"], row["line"], row["text"]
            if path not in lines or type(number) is not int or not 1 <= number <= len(lines[path]):
                return False
            if not isinstance(text, str) or lines[path][number - 1] != text or (path, number) in seen:
                return False
            seen.add((path, number))
        return bool(anchors) and {path for path, _ in seen} == set(tree)
    except (KeyError, TypeError, ValueError):
        return False

if not valid(receipt):
    raise SystemExit("receipt did not match pinned sources")
mutants = []
for i in range(len(receipt["files"])):
    for field in ("remove", "blob", "mode"):
        case = copy.deepcopy(receipt)
        if field == "remove":
            case["files"].pop(i)
        else:
            case["files"][i][field] = "invalid"
        mutants.append(case)
for i in range(len(receipt["anchors"])):
    for field in ("line", "text"):
        case = copy.deepcopy(receipt)
        case["anchors"][i][field] = -1 if field == "line" else "invalid planted text"
        mutants.append(case)
case = copy.deepcopy(receipt)
case["anchors"].append(copy.deepcopy(case["anchors"][0]))
mutants.append(case)
if not mutants or any(valid(case) for case in mutants):
    raise SystemExit("a planted error was accepted")
print(f"checked {len(tree)} files and {len(receipt['anchors'])} anchors; rejected {len(mutants)} planted errors")
PY
```
