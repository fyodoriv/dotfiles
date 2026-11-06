#!/bin/bash
set -euo pipefail
case "${1:-}" in before|after) ;; *) exit 2 ;; esac
unset DOTFILES_REAL_GIT DOTFILES_SYSTEM_GIT DOTFILES_PUBLIC_PUSH_ALLOWLIST DOTFILES_PRIVATE_PUSH_ALLOWLIST
python3 -I - "$1" <<'PY'
import hashlib
import json
import math
import os
import subprocess
import statistics
import sys
import time
from pathlib import Path

phase = sys.argv[1]
root = Path(os.environ["GIT_LAZY_EVIDENCE_DIR"])
if not root.is_absolute() or not root.is_dir() or root.is_symlink() or root.stat().st_mode & 0o077:
    raise SystemExit("evidence directory must be private")
run = root / phase
run.mkdir(mode=0o700)
final = root / (phase + ".json")
if final.exists():
    raise SystemExit("evidence already exists")
commands = ["/usr/bin/git --version", "./bin/git --version", "/usr/bin/git rev-parse --git-dir", "./bin/git rev-parse --git-dir"]
subprocess.run(["/usr/bin/git", "--version"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True, timeout=30)
cpu = int(subprocess.check_output(["sysctl", "-n", "hw.logicalcpu"], text=True, timeout=10))
load_before = os.getloadavg()[0]
if load_before > cpu:
    raise SystemExit("pre-benchmark load exceeds CPU count")
paths = ["bin/git", "docs/plans/git-wrapper-lazy-483-bench.sh", "docs/plans/git-wrapper-lazy-483-evaluate.py", "tests/git-wrapper-lazy-483.bats", "/usr/bin/git"]
hashes = {path: hashlib.sha256(Path(path).read_bytes()).hexdigest() for path in paths}
head = subprocess.check_output(["/usr/bin/git", "rev-parse", "HEAD"], text=True, timeout=10).strip()
env_keys = sorted(k for k in os.environ if k in ("HOME", "PATH") or k.startswith(("GIT_", "DOTFILES_")))
env_hash = hashlib.sha256(json.dumps([(k, os.environ[k]) for k in env_keys], separators=(",", ":")).encode()).hexdigest()
started = time.time_ns()
raw_path = run / "hyperfine.json"
proc = subprocess.run(["hyperfine", "--warmup", "3", "--runs", "20", "--export-json", str(raw_path), *commands], capture_output=True, timeout=300)
(run / "stdout.txt").write_bytes(proc.stdout)
(run / "stderr.txt").write_bytes(proc.stderr)
(run / "exit.txt").write_text(str(proc.returncode) + "\n")
if proc.returncode != 0:
    raise SystemExit("hyperfine failed")
load_after = os.getloadavg()[0]
ended = time.time_ns()
if load_after > cpu:
    raise SystemExit("post-benchmark load exceeds CPU count")
data = json.loads(raw_path.read_bytes())
results = data.get("results", [])
if [item.get("command") for item in results] != commands:
    raise SystemExit("benchmark command order changed")
for item in results:
    if len(item.get("times", [])) != 20 or not all(isinstance(t, (int, float)) and math.isfinite(t) and t > 0 for t in item["times"]):
        raise SystemExit("benchmark sample is incomplete")
    if any(not isinstance(item.get(k), (int, float)) or not math.isfinite(item[k]) or item[k] < 0 for k in ("median", "stddev")):
        raise SystemExit("benchmark statistics missing")
    if abs(statistics.median(item["times"]) - item["median"]) > 1e-9:
        raise SystemExit("benchmark median does not match samples")
record = {"phase": phase, "head": head, "hashes": hashes, "environmentHash": env_hash, "loadBefore": load_before, "loadAfter": load_after, "logicalCpus": cpu, "startedNs": started, "endedNs": ended, "results": results}
with final.open("x") as output:
    json.dump(record, output)
print(f"{phase}: complete")
PY
