import json
import math
import re
import statistics
import sys
from pathlib import Path

if len(sys.argv) != 3:
    raise SystemExit("expected before and after evidence")
before, after = (json.loads(Path(path).read_text()) for path in sys.argv[1:])
commands = ["/usr/bin/git --version", "./bin/git --version", "/usr/bin/git rev-parse --git-dir", "./bin/git rev-parse --git-dir"]
hash_paths = {"bin/git", "docs/plans/git-wrapper-lazy-483-bench.sh", "docs/plans/git-wrapper-lazy-483-evaluate.py", "tests/git-wrapper-lazy-483.bats", "/usr/bin/git"}
for item, phase in ((before, "before"), (after, "after")):
    if item.get("phase") != phase or item.get("startedNs", 0) >= item.get("endedNs", 0):
        raise SystemExit("invalid phase or timing")
    cpu = item.get("logicalCpus")
    loads = (item.get("loadBefore"), item.get("loadAfter"))
    if type(cpu) is not int or cpu <= 0 or any(type(load) not in (int, float) or not math.isfinite(load) or load < 0 or load > cpu for load in loads):
        raise SystemExit("invalid load")
    if not isinstance(item.get("hashes"), dict) or set(item["hashes"]) != hash_paths or any(not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{64}", value) for value in item["hashes"].values()):
        raise SystemExit("invalid measurement hashes")
    if not isinstance(item.get("head"), str) or not re.fullmatch(r"[0-9a-f]{40}", item["head"]) or not isinstance(item.get("environmentHash"), str) or not re.fullmatch(r"[0-9a-f]{64}", item["environmentHash"]):
        raise SystemExit("invalid measurement identity")
    if [row.get("command") for row in item.get("results", [])] != commands:
        raise SystemExit("invalid command order")
    for row in item["results"]:
        if len(row.get("times", [])) != 20 or any(not isinstance(x, (int, float)) or not math.isfinite(x) or x <= 0 for x in row["times"]):
            raise SystemExit("incomplete samples")
        if any(not isinstance(row.get(k), (int, float)) or not math.isfinite(row[k]) or row[k] < 0 for k in ("median", "stddev")):
            raise SystemExit("invalid statistics")
        if abs(statistics.median(row["times"]) - row["median"]) > 1e-9:
            raise SystemExit("median does not match samples")
if before["endedNs"] >= after["startedNs"] or before["head"] != after["head"] or before["environmentHash"] != after["environmentHash"]:
    raise SystemExit("measurements are not comparable")
for path, value in before["hashes"].items():
    if path != "bin/git" and after["hashes"].get(path) != value:
        raise SystemExit("measurement input changed")
if before["hashes"].get("bin/git") == after["hashes"].get("bin/git"):
    raise SystemExit("wrapper did not change")
for phase in (before, after):
    for row in phase["results"]:
        print(f"{phase['phase']} {row['command']}: median={row['median']:.6f}s stddev={row['stddev']:.6f}s")
passed = True
for index, label in ((0, "version"), (2, "git-dir")):
    old = before["results"][index + 1]["median"] - before["results"][index]["median"]
    new = after["results"][index + 1]["median"] - after["results"][index]["median"]
    if old <= 0.005:
        raise SystemExit(f"{label}: invalid baseline")
    improvement = (old - new) / old
    print(f"{label}: before={old:.6f}s after={new:.6f}s improvement={improvement:.2%}")
    if improvement < 0.30:
        passed = False
if not passed:
    raise SystemExit("threshold missed")
