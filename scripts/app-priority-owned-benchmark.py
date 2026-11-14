"""Compare priority decisions on owned hosted children without changing priority."""

import argparse
import json
import os
from pathlib import Path
import statistics
import subprocess
import tempfile
import time


def allowed():
    return (os.environ.get("GITHUB_ACTIONS") == "true"
            and os.environ.get("RUNNER_ENVIRONMENT") == "github-hosted"
            and os.environ.get("RUNNER_OS") == "macOS")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--child", type=Path, required=True)
    args = parser.parse_args()
    if not allowed():
        raise SystemExit("hosted macOS required")

    children = []
    with tempfile.TemporaryDirectory(prefix="priority-owned-") as temporary:
        root = Path(temporary)
        home = root / "home"
        config = home / ".config"
        mockbin = root / "mockbin"
        config.mkdir(parents=True)
        mockbin.mkdir()
        for name in ("taskpolicy", "renice"):
            tool = mockbin / name
            tool.write_text('#!/bin/bash\nprintf "%s %s\\n" "${0##*/}" "$*" >> "$ACTION_LOG"\n')
            tool.chmod(0o755)
        action_log = root / "actions"
        env = {"HOME": str(home), "XDG_CONFIG_HOME": str(config),
               "XDG_STATE_HOME": str(home / "state"), "LC_ALL": "C",
               "PATH": str(mockbin) + ":/usr/bin:/bin:/usr/sbin:/sbin",
               "DOTFILES_STATS_LOG": "0", "ACTION_LOG": str(action_log)}
        cases = [("Slack", "slack"), ("claude", "claude"), ("codex", "codex"),
                 ("bats", "bats"), ("node", "minsky"), ("node", "node_modules/vitest")]
        try:
            for name, marker in cases:
                child = subprocess.Popen([name, "--child", marker], executable=str(args.child),
                                         stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                         stderr=subprocess.DEVNULL, env=env)
                children.append(child)
                if child.stdout.read(1) != b"R":
                    raise RuntimeError("owned child did not start")
            ids = [child.pid for child in children]
            expected = (
                f"taskpolicy -B -t 0 -l 0 -p {ids[0]}\n"
                f"taskpolicy -b -p {ids[1]}\nrenice 10 -p {ids[1]}\n"
                f"taskpolicy -b -p {ids[2]}\nrenice 10 -p {ids[2]}\n"
                f"taskpolicy -b -p {ids[4]}\nrenice 10 -p {ids[4]}\n"
                f"taskpolicy -b -p {ids[3]}\nrenice 10 -p {ids[3]}\n"
                f"renice 10 -p {ids[5]}\n").encode()
            times = {"base": [], "candidate": []}
            for pair in range(30):
                order = ("base", "candidate") if pair % 2 == 0 else ("candidate", "base")
                for label in order:
                    action_log.write_bytes(b"")
                    tree = args.base if label == "base" else args.candidate
                    start = time.perf_counter_ns()
                    result = subprocess.run(["/bin/bash", str(tree / "bin/app-priority")],
                                            env=env, stdout=subprocess.PIPE,
                                            stderr=subprocess.PIPE, check=False)
                    times[label].append((time.perf_counter_ns() - start) / 1_000_000)
                    if result.returncode != 0 or result.stdout or result.stderr:
                        raise RuntimeError("command or output mismatch")
                    if action_log.read_bytes() != expected:
                        raise RuntimeError("ordered actions or target ownership differ")
            base = statistics.median(times["base"])
            candidate = statistics.median(times["candidate"])
            ratio = candidate / base
        finally:
            for child in children:
                if child.stdin:
                    child.stdin.close()
            for child in children:
                if child.wait(timeout=10) != 0:
                    raise RuntimeError("owned child cleanup failed")
        print(json.dumps({"pairs": 30, "actions_per_pair": 10,
                          "base_ms": times["base"], "candidate_ms": times["candidate"],
                          "base_median_ms": base, "candidate_median_ms": candidate,
                          "ratio": ratio}))
        if ratio > 0.40 or candidate > 400:
            raise SystemExit("timing threshold missed")


if __name__ == "__main__":
    main()
