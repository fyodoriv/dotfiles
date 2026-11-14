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
    if os.environ.get("HOOK_STATUS_INSTALLED") != "1":
        raise SystemExit("scratch entry point required")
    original = guard.with_name("block-dangerous-git-legacy.sh").read_bytes()
    modified = guard.read_bytes()
    command = ["/bin/bash", str(guard)]

    def invoke(label, payload, env, *, memory=False):
        guard.write_bytes(original if label == "base" else modified)
        argv = ["/usr/bin/time", "-l", *command] if memory else command
        return subprocess.run(argv, input=payload, env=env, capture_output=True, check=False)
    inputs = [b'{"tool_input":{"command":"git status"},"cwd":"/tmp"}',
              b'{"tool_input":{"command":"git status --short"}}',
              b'{"tool_input":{"command":"git status; echo safe"}}',
              b'{"tool_input":{"command":"git status","command":"echo safe"}}',
              b'{"tool_input":{"comm\\u0061nd":"git status"}}', b'{}', b'not-json']
    with tempfile.TemporaryDirectory(prefix="hook-status-fixture-") as home:
        env = os.environ.copy()
        env["HOME"] = home
        for index, payload in enumerate(inputs):
            expected = invoke("base", payload, env)
            actual = invoke("candidate", payload, env)
            if (expected.returncode, expected.stdout, expected.stderr) != (actual.returncode, actual.stdout, actual.stderr):
                raise SystemExit(f"guard parity mismatch case {index}: status_equal={expected.returncode == actual.returncode} stdout_equal={expected.stdout == actual.stdout} stderr_equal={expected.stderr == actual.stderr}")
        times = {"base": [], "candidate": []}
        for pair in range(15):
            for label in (("base", "candidate") if pair % 2 == 0 else ("candidate", "base")):
                guard.write_bytes(original if label == "base" else modified)
                start = time.monotonic_ns()
                result = subprocess.run(command, input=inputs[0], env=env, capture_output=True, check=False)
                times[label].append((time.monotonic_ns() - start) / 1_000_000)
                if result.returncode != 0 or result.stdout or result.stderr:
                    raise SystemExit("timing sample failed")
        memory = {"base_first": [], "base_second": [], "candidate": []}
        for label in memory:
            for _ in range(15):
                result = invoke(label, inputs[0], env, memory=True)
                sample = re.search(rb"^\s*(\d+)\s+maximum resident set size\s*$", result.stderr, re.MULTILINE)
                if result.returncode != 0 or result.stdout or sample is None:
                    raise SystemExit("memory sample failed")
                memory[label].append(int(sample.group(1)))
        time_ratio = statistics.median(times["candidate"]) / statistics.median(times["base"])
        first, second = (statistics.median(memory[k]) for k in ("base_first", "base_second"))
        baseline_ratio = second / first
        memory_ratio = statistics.median(memory["candidate"]) / min(first, second)
        guard.write_bytes(modified)
        print(json.dumps({"time_ms": times, "time_ratio": time_ratio, "memory": memory,
                          "baseline_memory_ratio": baseline_ratio, "candidate_memory_ratio": memory_ratio}))
        if time_ratio > 0.50 or not 0.95 <= baseline_ratio <= 1.05 or memory_ratio > 1.10:
            raise SystemExit("fixture threshold missed")


if __name__ == "__main__":
    main()
