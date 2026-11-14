"""Compare a native shortcut with the existing guard on hosted macOS."""
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    if not (os.environ.get("GITHUB_ACTIONS") == "true"
            and os.environ.get("RUNNER_ENVIRONMENT") == "github-hosted"
            and os.environ.get("RUNNER_OS") == "macOS"):
        raise SystemExit("hosted macOS required")
    guard = ROOT / "agent-hooks/block-dangerous-git.sh"
    native = ROOT / "rust/hook-status/target/release/dotfiles-hook-status"
    baseline = ["/bin/bash", str(guard)]
    candidate = [str(native), str(guard)]
    inputs = [b'{"tool_input":{"command":"git status"},"cwd":"/tmp"}',
              b'{"tool_input":{"command":"git status --short"}}',
              b'{"tool_input":{"command":"git status; echo safe"}}',
              b'{"tool_input":{"command":"git status","command":"echo safe"}}',
              b'{"tool_input":{"comm\\u0061nd":"git status"}}', b'{}', b'not-json']
    with tempfile.TemporaryDirectory(prefix="hook-status-fixture-") as home:
        env = os.environ.copy()
        env["HOME"] = home
        for payload in inputs:
            expected = subprocess.run(baseline, input=payload, env=env, capture_output=True, check=False)
            actual = subprocess.run(candidate, input=payload, env=env, capture_output=True, check=False)
            if (expected.returncode, expected.stdout, expected.stderr) != (actual.returncode, actual.stdout, actual.stderr):
                raise SystemExit("guard parity mismatch")
        times = {"base": [], "candidate": []}
        for pair in range(15):
            for label in (("base", "candidate") if pair % 2 == 0 else ("candidate", "base")):
                start = time.monotonic_ns()
                result = subprocess.run(baseline if label == "base" else candidate, input=inputs[0], env=env, capture_output=True, check=False)
                times[label].append((time.monotonic_ns() - start) / 1_000_000)
                if result.returncode != 0 or result.stdout or result.stderr:
                    raise SystemExit("timing sample failed")
        memory = {"base_first": [], "base_second": [], "candidate": []}
        for label in memory:
            for _ in range(15):
                result = subprocess.run(["/usr/bin/time", "-l", *(candidate if label == "candidate" else baseline)],
                                        input=inputs[0], env=env, capture_output=True, check=False)
                sample = re.search(rb"^\s*(\d+)\s+maximum resident set size\s*$", result.stderr, re.MULTILINE)
                if result.returncode != 0 or result.stdout or sample is None:
                    raise SystemExit("memory sample failed")
                memory[label].append(int(sample.group(1)))
        time_ratio = statistics.median(times["candidate"]) / statistics.median(times["base"])
        first, second = (statistics.median(memory[k]) for k in ("base_first", "base_second"))
        baseline_ratio = second / first
        memory_ratio = statistics.median(memory["candidate"]) / min(first, second)
        print(json.dumps({"time_ms": times, "time_ratio": time_ratio, "memory": memory,
                          "baseline_memory_ratio": baseline_ratio, "candidate_memory_ratio": memory_ratio}))
        if time_ratio > 0.50 or not 0.95 <= baseline_ratio <= 1.05 or memory_ratio > 1.10:
            raise SystemExit("fixture threshold missed")


if __name__ == "__main__":
    main()
