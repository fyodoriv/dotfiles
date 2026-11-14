"""Compare reviewed app-priority trees on a hosted synthetic process table."""

import argparse
import json
import os
from pathlib import Path
import statistics
import subprocess
import tempfile
import time


MOCKS = {
    "pgrep": r'''#!/bin/bash
case "$*" in
  "-l -x Slack|Google Chrome|Microsoft Outlook|ghostty|WebStorm|claude|codex|ollama|bats|shellcheck|parallel")
    printf "101 claude\\n201 codex\\n301 Slack\\n401 bats\\n" ;;
  "-x Slack") printf "301\n" ;;
  "-x claude") printf "101\n" ;;
  "-x codex") printf "201\n" ;;
  "-x bats") printf "401\n" ;;
  "-f node.*minsky") printf "501\n" ;;
  "-f node_modules/vitest") printf "601\n" ;;
  *) exit 1 ;;
esac
''',
    "ps": r'''#!/bin/bash
case "$*" in
  "-p 101 -o comm=") printf "/Applications/Terminal.app/Contents/MacOS/Terminal\n" ;;
  "-p 201 -o comm=") printf "/usr/bin/codex\n" ;;
  "-p 201 -o ppid=") printf "1\n" ;;
  *) exit 1 ;;
esac
''',
    "taskpolicy": r'''#!/bin/bash
printf 'taskpolicy %s\n' "$*" >> "$ACTION_LOG"
''',
    "renice": r'''#!/bin/bash
printf 'renice %s\n' "$*" >> "$ACTION_LOG"
''',
}


EXPECTED_ACTIONS = (
    b"taskpolicy -B -t 0 -l 0 -p 301\n"
    b"taskpolicy -B -t 0 -l 0 -p 101\n"
    b"renice 0 -p 101\n"
    b"taskpolicy -b -p 201\n"
    b"renice 10 -p 201\n"
    b"taskpolicy -b -p 501\n"
    b"renice 10 -p 501\n"
    b"taskpolicy -b -p 401\n"
    b"renice 10 -p 401\n"
    b"renice 10 -p 601\n"
)


def hosted():
    return (os.environ.get("GITHUB_ACTIONS") == "true"
            and os.environ.get("RUNNER_OS") == "macOS"
            and os.environ.get("RUNNER_ENVIRONMENT") == "github-hosted")


def prepare(root):
    home = root / "home"
    config = home / ".config"
    mockbin = root / "mockbin"
    config.mkdir(parents=True)
    mockbin.mkdir()
    for name, source in MOCKS.items():
        path = mockbin / name
        path.write_text(source)
        path.chmod(0o755)
    return home, config, mockbin


def sample(tree, root, home, config, mockbin):
    action_log = root / "actions"
    action_log.write_text("")
    env = {"HOME": str(home), "XDG_CONFIG_HOME": str(config),
           "XDG_STATE_HOME": str(home / "state"),
           "PATH": str(mockbin) + ":/usr/bin:/bin", "LC_ALL": "C",
           "DOTFILES_STATS_LOG": "0", "ACTION_LOG": str(action_log)}
    command = tree / "bin" / "app-priority"
    started = time.perf_counter_ns()
    result = subprocess.run(["/bin/bash", str(command)], env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            check=False)
    elapsed_ms = (time.perf_counter_ns() - started) / 1_000_000
    if result.returncode != 0:
        raise RuntimeError("fixture command failed")
    return elapsed_ms, action_log.read_bytes(), result.stdout, result.stderr


def compare(base, candidate):
    if base[0] != EXPECTED_ACTIONS or base != candidate:
        raise RuntimeError("fixture actions or output differ")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--pairs", type=int, required=True)
    args = parser.parse_args()
    if not hosted():
        parser.error("run only on a GitHub-hosted macOS runner")
    if not 1 <= args.pairs <= 30:
        parser.error("pairs must be between 1 and 30")
    trees = {"base": args.base.resolve(strict=True),
             "candidate": args.candidate.resolve(strict=True)}
    for tree in trees.values():
        if not (tree / "bin" / "app-priority").is_file():
            parser.error("each tree must contain bin/app-priority")
    values = {"base": [], "candidate": []}
    with tempfile.TemporaryDirectory(prefix="app-priority-fixture-") as temporary:
        root = Path(temporary)
        home, config, mockbin = prepare(root)
        for index in range(args.pairs):
            order = ("base", "candidate") if index % 2 == 0 else ("candidate", "base")
            observations = {}
            for name in order:
                duration, actions, stdout, stderr = sample(
                    trees[name], root, home, config, mockbin
                )
                values[name].append(duration)
                observations[name] = (actions, stdout, stderr)
            compare(observations["base"], observations["candidate"])
    base = statistics.median(values["base"])
    candidate = statistics.median(values["candidate"])
    print(json.dumps({"pairs": args.pairs, "base_ms": values["base"],
                      "candidate_ms": values["candidate"],
                      "base_median_ms": base, "candidate_median_ms": candidate,
                      "ratio": candidate / base}))


if __name__ == "__main__":
    main()
