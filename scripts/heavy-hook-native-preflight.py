"""Compare the installed experimental heavy hook on hosted macOS only."""
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
GUARD = ROOT / "agent-hooks/require-heavy-run.sh"


def main():
    if not (os.environ.get("GITHUB_ACTIONS") == "true"
            and os.environ.get("RUNNER_ENVIRONMENT") == "github-hosted"
            and os.environ.get("RUNNER_OS") == "macOS"):
        raise SystemExit("hosted macOS required")
    payloads = [
        b'{"tool_input":{"command":"git status"},"cwd":"/tmp"}',
        b'{"tool_input":{"command":"git status --short"}}',
        b'{"tool_input":{"command":"git status -s -b"}}',
        b'{"tool_input":{"command":"git status --porcelain=v1"}}',
        b'{"tool_input":{"command":"git status; echo safe"}}',
        b'{"tool_input":{"command":"cargo test"}}',
        b'{"tool_input":{"command":"git status","command":"cargo test"}}',
        b'{}', b'not-json',
    ]
    with tempfile.TemporaryDirectory(prefix="heavy-hook-preflight-") as home:
        def invoke(baseline, payload, fail_perl=False, memory=False):
            env = os.environ.copy()
            env["HOME"] = home
            env.pop("HEAVY_RUN_HOOK", None)
            env.pop("PERL5OPT", None)
            if baseline:
                env["DOTFILES_NATIVE_HEAVY_BYPASS"] = "1"
            else:
                env.pop("DOTFILES_NATIVE_HEAVY_BYPASS", None)
            if fail_perl:
                env["PERL5OPT"] = "-MDotfilesMissingPerlFixture"
            argv = ["/bin/bash", str(GUARD)]
            if memory:
                argv = ["/usr/bin/time", "-l", *argv]
            return subprocess.run(argv, input=payload, env=env, capture_output=True, check=False)

        for index, payload in enumerate(payloads):
            expected, actual = invoke(True, payload), invoke(False, payload)
            if (expected.returncode, expected.stdout, expected.stderr) != (actual.returncode, actual.stdout, actual.stderr):
                raise SystemExit(f"parity mismatch case {index}: expected status {expected.returncode}, received {actual.returncode}")
        expected, actual = invoke(True, payloads[0], True), invoke(False, payloads[0], True)
        if (expected.returncode, expected.stdout, expected.stderr) != (actual.returncode, actual.stdout, actual.stderr):
            raise SystemExit(f"Perl failure mismatch: expected status {expected.returncode}, received {actual.returncode}")
        times = {}
        for index in range(4):
            samples = {"base": [], "candidate": []}
            for pair in range(30):
                for name in (("base", "candidate") if pair % 2 == 0 else ("candidate", "base")):
                    start = time.monotonic_ns()
                    result = invoke(name == "base", payloads[index])
                    samples[name].append((time.monotonic_ns() - start) / 1_000_000)
                    if result.returncode != 0 or result.stdout or result.stderr:
                        raise SystemExit("invalid timing sample")
            times[index] = samples
        memory = {"base_first": [], "base_second": [], "candidate": []}
        for name, samples in memory.items():
            for _ in range(15):
                result = invoke(name != "candidate", payloads[0], memory=True)
                match = re.search(rb"^\s*(\d+)\s+maximum resident set size\s*$", result.stderr, re.MULTILINE)
                if result.returncode != 0 or result.stdout or match is None:
                    raise SystemExit("invalid memory sample")
                samples.append(int(match.group(1)))
        ratios = {index: statistics.median(value["candidate"]) / statistics.median(value["base"])
                  for index, value in times.items()}
        first, second = (statistics.median(memory[k]) for k in ("base_first", "base_second"))
        baseline_memory = second / first
        candidate_memory = statistics.median(memory["candidate"]) / min(first, second)
        print(json.dumps({"preflight_only": True, "time_ms": times, "ratios": ratios,
                          "memory": memory, "baseline_memory_ratio": baseline_memory,
                          "candidate_memory_ratio": candidate_memory}), flush=True)
        if ratios[0] > 0.50 or any(ratios[i] > 0.80 for i in (1, 2, 3)) or not 0.95 <= baseline_memory <= 1.05 or candidate_memory > 1.10:
            raise SystemExit("preflight threshold missed; unchanged performance gate not measured")


if __name__ == "__main__":
    main()
