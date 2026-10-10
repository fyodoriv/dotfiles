"""Remember what the last tooling checkup saw, and show what changed since.

Subcommands:
  snapshot   print the current state as JSON (tool versions, repo heads, macOS)
  diff       compare the current state with the last recorded run
  record     save the current state as the last run (run at the end of a checkup)

State file: $TOOLING_CHECKUP_STATE_DIR/last-run.json
(default ~/.local/state/tooling-checkup/last-run.json). It holds versions and
commit ids only, never file contents or credentials.

Usage: python3 checkup_state.py {snapshot|diff|record} [--verdict TEXT] [--metric NAME=VALUE ...]

`record --metric` stores numbers measured during the checkup (for example the
echo latency), so the next `diff` can print them next to their last value.
"""

import argparse
import concurrent.futures
import datetime as dt
import json
import os
import pathlib
import shutil
import subprocess
import sys

TOOLS = {
    "claude": ["claude", "--version"],
    "node": ["node", "--version"],
    "npm": ["npm", "--version"],
    "pnpm": ["pnpm", "--version"],
    "brew": ["brew", "--version"],
    "git": ["git", "--version"],
    "gh": ["gh", "--version"],
    "python3": ["python3", "--version"],
    "uv": ["uv", "--version"],
    "pipx": ["pipx", "--version"],
    "mise": ["mise", "--version"],
    "chezmoi": ["chezmoi", "--version"],
    "topgrade": ["topgrade", "--version"],
    "ghostty": ["ghostty", "--version"],
    "macos": ["sw_vers", "-productVersion"],
}
GHOSTTY_APP = "/Applications/Ghostty.app/Contents/MacOS/ghostty"


def state_path() -> pathlib.Path:
    base = os.environ.get("TOOLING_CHECKUP_STATE_DIR") or os.path.expanduser("~/.local/state/tooling-checkup")
    return pathlib.Path(base) / "last-run.json"


def first_line(command) -> str:
    if command[0] == "ghostty" and not shutil.which("ghostty") and os.path.exists(GHOSTTY_APP):
        command = [GHOSTTY_APP] + command[1:]
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=20, stdin=subprocess.DEVNULL)
    except FileNotFoundError:
        return "missing"
    except subprocess.TimeoutExpired:
        return "timeout"
    for line in (result.stdout + result.stderr).splitlines():
        if line.strip():
            return line.strip()
    return f"exit {result.returncode}"


def repo_heads() -> dict:
    root = pathlib.Path(os.environ.get("TOOLING_ROOT") or os.path.expanduser("~/apps/tooling"))
    heads = {}
    if not root.is_dir():
        return heads
    for repo in sorted(root.iterdir()):
        if not (repo / ".git").is_dir():
            continue
        try:
            out = subprocess.run(
                ["git", "-C", str(repo), "log", "-1", "--format=%h %cs"],
                capture_output=True, text=True, timeout=20,
            ).stdout.strip()
            branch = subprocess.run(
                ["git", "-C", str(repo), "branch", "--show-current"],
                capture_output=True, text=True, timeout=20,
            ).stdout.strip()
        except subprocess.TimeoutExpired:
            out, branch = "timeout", ""
        heads[repo.name] = f"{out} [{branch or 'detached'}]"
    return heads


def snapshot() -> dict:
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        futures = {name: pool.submit(first_line, cmd) for name, cmd in TOOLS.items()}
        versions = {name: future.result() for name, future in futures.items()}
    return {
        "time": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "versions": versions,
        "repos": repo_heads(),
    }


def age(since_iso: str) -> str:
    try:
        then = dt.datetime.fromisoformat(since_iso)
    except ValueError:
        return "unknown age"
    hours = (dt.datetime.now(dt.timezone.utc) - then).total_seconds() / 3600
    return f"{hours:.0f} hour(s) ago" if hours < 48 else f"{hours / 24:.1f} day(s) ago"


def diff(current: dict) -> int:
    path = state_path()
    if not path.exists():
        print(f"checkup-state: first run (no {path})")
        for section in ("versions", "repos"):
            for name, value in current[section].items():
                print(f"  {section[:-1]} {name}: {value}")
        return 0
    try:
        last = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        print(f"checkup-state: cannot read {path}: {error}; treating this as a first run")
        return 0
    print(f"checkup-state: last run {last.get('time', '?')} ({age(last.get('time', ''))})")
    if last.get("verdict"):
        print(f"  last verdict: {last['verdict']}")
    for name, value in sorted(last.get("metrics", {}).items()):
        print(f"  last metric {name}: {value}")
    changes = 0
    for section in ("versions", "repos"):
        before, after = last.get(section, {}), current[section]
        for name in sorted(set(before) | set(after)):
            old, new = before.get(name, "absent"), after.get(name, "absent")
            if "timeout" in (old, new):
                print(f"  unknown {section[:-1]} {name}: {old} -> {new} (a command timed out)")
                continue
            if old != new:
                changes += 1
                print(f"  changed {section[:-1]} {name}: {old} -> {new}")
    if changes == 0:
        print("  no version or repo changes since the last run")
    return 0


def record(current: dict, verdict: str, metrics) -> int:
    path = state_path()
    # Keep the last known value when a version command timed out this time.
    try:
        last = json.loads(path.read_text()) if path.exists() else {}
    except (OSError, json.JSONDecodeError):
        last = {}
    for section in ("versions", "repos"):
        for name, value in current[section].items():
            if value == "timeout" and last.get(section, {}).get(name):
                current[section][name] = last[section][name]
    path.parent.mkdir(parents=True, exist_ok=True)
    if verdict:
        current["verdict"] = verdict
    current["metrics"] = dict(last.get("metrics", {}))
    for item in metrics:
        name, _, value = item.partition("=")
        if not name or not value:
            print(f"checkup-state: ignored metric '{item}' (use NAME=VALUE)", file=sys.stderr)
            continue
        current["metrics"][name] = value
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(current, indent=2, sort_keys=True) + "\n")
    tmp.replace(path)
    print(f"checkup-state: recorded {current['time']} in {path}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("action", choices=["snapshot", "diff", "record"])
    parser.add_argument("--verdict", default="", help="one-line verdict to store with `record`")
    parser.add_argument("--metric", action="append", default=[], help="NAME=VALUE to store with `record`")
    args = parser.parse_args()
    current = snapshot()
    if args.action == "snapshot":
        print(json.dumps(current, indent=2, sort_keys=True))
        return 0
    if args.action == "diff":
        return diff(current)
    return record(current, args.verdict, args.metric)


if __name__ == "__main__":
    sys.exit(main())
