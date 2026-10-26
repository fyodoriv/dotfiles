"""Write the tooling health dashboard datasets from local state files.

Read-only on its inputs. Writes one JSON row array per dataset plus
manifest.json into the output folder (default
~/.local/state/tooling-checkup/dashboard/). Phase 10 of the checkup uploads
these files to the one tooling health dashboard.

Datasets:
  runs    one row per checkup: time, verdict, status, key metrics
  latest  one row: the newest checkup and all its numeric metrics
  gate    dotfiles `make check` per day: runs, failures, median total seconds
  doctor  dotfiles doctor per day: the last pass, fail, warn and skip counts
  load    machine load per hour, last 7 days (dotfiles-load-sampler)
  agent_time  agent tool hours per day and tooling project, last 14 days
              (agentbrew perf log; other projects grouped as "other")

Privacy: rows hold tooling metrics only, and the exporter fails closed. Text
values lose home folders ("~"), emails ("[email]") and secrets ("[redacted]").
The private pattern is loaded by sourcing the local oss-readiness env file and
applied with grep -iE, as the leak gates do; matches become "[private]". A
missing env file, an empty pattern, or any output line that still matches
makes it exit 2 and write nothing.

Usage: python3 dashboard_export.py [--out DIR] [--state-dir DIR]
       [--gate-timings FILE] [--doctor-stats FILE] [--load-samples FILE]
       [--perf-dir DIR] [--pattern-env FILE]
"""

import argparse
import json
import os
import re
import statistics
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()
STALE_AFTER_HOURS = 72
# Metrics that get their own column in `runs`, in this order.
RUN_METRICS = (
    "machine_peak_load1_24h",
    "machine_overload_rows_24h",
    "agent_tool_hours_7d",
    "agent_active_hours_7d",
    "claude_echo_p95_ms",
    "slowest_step_p95_s",
    "upgrade_failed_steps",
    "upgrade_secs",
    "dotfiles_apply_secs",
    "ai_research_new",
)
TOKEN_RE = re.compile(
    r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}"
    r"|xox[abprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,})"
    r"|[A-Fa-f0-9]{32,}|[A-Za-z0-9+/_=-]{32,}"
)
KEY_VALUE_RE = re.compile(
    r"\b((?:api[_-]?)?key|token|secret|password|passwd|auth|credential)s?(\s*[=:]\s*)[^\s,;]+"
    r"|\b(Bearer|Basic)\s+[^\s,;]+",
    re.IGNORECASE,
)
EMAIL_RE = re.compile(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+")
HOME_DIR_RE = re.compile(r"/(?:Users|home)/[^/\s]+")
REDACTED = "[redacted]"
PRIVATE = "[private]"


class PrivatePatternMissing(Exception):
    pass


def load_private_pattern(env_file: Path) -> str:
    """Load the pattern the way the leak gates do: source the env file.

    Fails closed: a missing file or an empty pattern raises, so the exporter
    writes nothing.
    """
    if not env_file.is_file():
        raise PrivatePatternMissing(f"missing {env_file}")
    result = subprocess.run(
        ["bash", "-c", 'source "$1" >/dev/null 2>&1; printf %s "${OSS_READINESS_INTERNAL_PATTERN:-}"', "_", str(env_file)],
        capture_output=True,
        text=True,
    )
    if not result.stdout:
        raise PrivatePatternMissing(f"no OSS_READINESS_INTERNAL_PATTERN in {env_file}")
    return result.stdout


def grep_matches(pattern: str, lines: list) -> set:
    """Substrings that `grep -oiE` finds (POSIX ERE, as the leak gates use)."""
    if not lines:
        return set()
    result = subprocess.run(["grep", "-oiE", "--", pattern], input="\n".join(lines) + "\n", capture_output=True, text=True)
    if result.returncode > 1:
        raise PrivatePatternMissing(f"grep rejected the pattern: {result.stderr.strip()}")
    return {match for match in result.stdout.splitlines() if match}


def grep_count(pattern: str, text: str) -> int:
    result = subprocess.run(["grep", "-icE", "--", pattern], input=text, capture_output=True, text=True)
    if result.returncode > 1:
        raise PrivatePatternMissing(f"grep rejected the pattern: {result.stderr.strip()}")
    return int(result.stdout.strip() or 0)


class Scrubber:
    """Scrubs text values; the private pattern is applied after, in one grep."""

    def text(self, value) -> str:
        value = " ".join(str(value).split())
        value = value.replace(str(HOME), "~")
        value = HOME_DIR_RE.sub("~", value)
        value = KEY_VALUE_RE.sub(
            lambda m: (m.group(1) + m.group(2) if m.group(1) else m.group(3) + " ") + REDACTED, value
        )
        value = EMAIL_RE.sub("[email]", value)
        return TOKEN_RE.sub(REDACTED, value)


def apply_private(data: dict, pattern: str) -> None:
    """Replace private-pattern matches in every string value, in place."""
    strings = [v for rows in data.values() for row in rows for v in row.values() if isinstance(v, str)]
    hits = sorted(grep_matches(pattern, strings), key=len, reverse=True)
    if not hits:
        return
    for rows in data.values():
        for row in rows:
            for key, value in row.items():
                if isinstance(value, str):
                    for hit in hits:
                        value = re.sub(re.escape(hit), PRIVATE, value, flags=re.IGNORECASE)
                    row[key] = value


def number(value):
    try:
        result = float(value)
    except (TypeError, ValueError):
        return None
    return int(result) if result.is_integer() else round(result, 2)


def read_jsonl(path: Path) -> list:
    rows = []
    if not path.is_file():
        return rows
    for line in path.read_text(errors="replace").splitlines():
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(row, dict):
            rows.append(row)
    return rows


def status_of(verdict: str) -> str:
    lowered = verdict.lower()
    if lowered.startswith("broken"):
        return "broken"
    if lowered.startswith("healthy with gaps"):
        return "gaps"
    if lowered.startswith("healthy"):
        return "healthy"
    return "unknown"


def history(state_dir: Path) -> list:
    rows = read_jsonl(state_dir / "history.jsonl")
    if not rows:
        # Before the first `record` with history support: use last-run.json.
        try:
            last = json.loads((state_dir / "last-run.json").read_text())
        except (OSError, json.JSONDecodeError):
            last = {}
        if last.get("time"):
            rows = [{"time": last["time"], "verdict": last.get("verdict", ""), "metrics": last.get("metrics", {})}]
    return sorted(rows, key=lambda row: str(row.get("time", "")))


def runs_rows(runs: list, scrub: Scrubber) -> list:
    out = []
    for run in runs:
        verdict = scrub.text(run.get("verdict", ""))
        row = {"time": scrub.text(run.get("time", "")), "status": status_of(verdict), "verdict": verdict}
        metrics = run.get("metrics") or {}
        for name in RUN_METRICS:
            row[name] = number(metrics.get(name))
        out.append(row)
    return out


def latest_rows(runs: list, scrub: Scrubber) -> list:
    if not runs:
        return []
    run = runs[-1]
    verdict = scrub.text(run.get("verdict", ""))
    row = {"time": scrub.text(run.get("time", "")), "status": status_of(verdict), "verdict": verdict}
    for name, value in sorted((run.get("metrics") or {}).items()):
        if re.fullmatch(r"[a-z0-9_]{1,64}", name) and number(value) is not None:
            row[name] = number(value)
    return [row]


def gate_rows(path: Path) -> list:
    days = {}
    for row in read_jsonl(path):
        if row.get("step") != "total" or number(row.get("seconds")) is None:
            continue
        day = str(row.get("ts", ""))[:10]
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", day):
            continue
        entry = days.setdefault(day, {"seconds": [], "failed": 0})
        entry["seconds"].append(number(row["seconds"]))
        if row.get("status") not in (0, "0"):
            entry["failed"] += 1
    return [
        {
            "day": day,
            "runs": len(entry["seconds"]),
            "failed_runs": entry["failed"],
            "median_total_s": number(statistics.median(entry["seconds"])),
        }
        for day, entry in sorted(days.items())
    ]


def doctor_rows(path: Path) -> list:
    days = {}
    for row in read_jsonl(path):
        if row.get("task") != "doctor":
            continue
        stamp = str(row.get("timestamp", ""))
        day = stamp[:10]
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", day):
            continue
        if day not in days or stamp >= days[day][0]:
            days[day] = (stamp, row)
    out = []
    for day, (_, row) in sorted(days.items()):
        out.append({"day": day, **{key: number(row.get(key)) or 0 for key in ("pass", "fail", "warn", "skip")}})
    return out


LOAD_HOURS = 7 * 24
AGENT_DAYS = 14
# Agent projects shown by name; every other project becomes "other", so the
# dashboard never names private repos.
TOOLING_PROJECTS = ("agentbrew", "dotfiles", "minsky", "taskgrind", "tasks.md", "tooling")


def load_rows(path: Path, now: float) -> list:
    """One row per hour from dotfiles-load-sampler: peak and mean load1,
    lowest free memory %, peak swap MB and overload samples (load1 > 2 x CPUs)."""
    hours = {}
    if not path.is_file():
        return []
    since = now - LOAD_HOURS * 3600
    for line in path.read_text(errors="replace").splitlines():
        cols = line.split("\t")
        if len(cols) < 9:
            continue
        epoch, load1, cpus, free, swap = (number(cols[i]) for i in (0, 2, 5, 6, 7))
        if None in (epoch, load1, cpus) or epoch < since or not re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}", cols[1][:13]):
            continue
        h = hours.setdefault(cols[1][:13], {"load": [], "free": [], "swap": [], "over": 0})
        h["load"].append(load1)
        if free is not None:
            h["free"].append(free)
        if swap is not None:
            h["swap"].append(swap)
        if load1 > 2 * cpus:
            h["over"] += 1
    return [
        {
            "hour": hour + ":00",
            "samples": len(h["load"]),
            "peak_load1": number(max(h["load"])),
            "mean_load1": number(sum(h["load"]) / len(h["load"])),
            "min_free_mem_pct": number(min(h["free"])) if h["free"] else None,
            "max_swap_mb": number(max(h["swap"])) if h["swap"] else None,
            "overload_samples": h["over"],
        }
        for hour, h in sorted(hours.items())
    ]


def agent_rows(perf_dir: Path, now: float) -> list:
    """One row per day and project from the agentbrew perf log: tool hours,
    finished tool calls and failed calls. Only rows with a duration count."""
    import datetime

    since = datetime.datetime.fromtimestamp(now - AGENT_DAYS * 86400, datetime.timezone.utc).strftime("%Y-%m-%d")
    days = {}
    for path in sorted(perf_dir.glob("*.jsonl")) if perf_dir.is_dir() else []:
        for row in read_jsonl(path):
            ms = number(row.get("ms"))
            day = str(row.get("ts", ""))[:10]
            if ms is None or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", day) or day < since:
                continue
            project = row.get("project") if row.get("project") in TOOLING_PROJECTS else "other"
            entry = days.setdefault((day, project), {"ms": 0, "calls": 0, "failed": 0})
            entry["ms"] += ms
            entry["calls"] += 1
            if row.get("ok") is False:
                entry["failed"] += 1
    return [
        {"day": day, "project": project, "tool_hours": number(e["ms"] / 3_600_000), "calls": e["calls"], "failed_calls": e["failed"]}
        for (day, project), e in sorted(days.items())
    ]


MANIFEST = (
    ("runs", "Checkup runs", "One row per tooling checkup: verdict, status and key metrics.", STALE_AFTER_HOURS),
    ("latest", "Latest checkup", "The newest tooling checkup with every numeric metric it recorded.", STALE_AFTER_HOURS),
    ("gate", "dotfiles gate per day", "dotfiles `make check` runs per day: count, failures and median total seconds.", None),
    ("doctor", "dotfiles doctor per day", "The last dotfiles doctor result of each day: pass, fail, warn and skip counts.", None),
    ("load", "Machine load per hour", "Last 7 days from dotfiles-load-sampler: peak and mean load1, lowest free memory %, peak swap MB, overload samples.", 24),
    ("agent_time", "Agent tool time per day", "Last 14 days from the agentbrew perf log: tool hours, calls and failed calls per day and tooling project (others grouped as other).", 48),
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    state_default = os.environ.get("TOOLING_CHECKUP_STATE_DIR") or str(HOME / ".local/state/tooling-checkup")
    parser.add_argument("--state-dir", default=state_default)
    parser.add_argument("--out", default="")
    parser.add_argument("--gate-timings", default=os.environ.get("DOTFILES_GATE_TIMINGS_FILE") or str(HOME / ".local/state/dotfiles/gate-timings.jsonl"))
    parser.add_argument("--doctor-stats", default=os.environ.get("DOTFILES_STATS_FILE") or str(HOME / ".dotfiles-stats.jsonl"))
    parser.add_argument("--load-samples", default=os.environ.get("DOTFILES_LOAD_SAMPLES") or str(HOME / ".local/state/dotfiles/load-samples.tsv"))
    parser.add_argument("--perf-dir", default=str(Path(os.environ.get("XDG_STATE_HOME") or HOME / ".local/state") / "agentbrew/perf"))
    parser.add_argument("--now", type=float, default=None, help=argparse.SUPPRESS)
    parser.add_argument("--pattern-env", default=os.environ.get("OSS_READINESS_ENV_FILE") or str(HOME / ".config/oss-readiness/oss-readiness.env"))
    args = parser.parse_args()

    state_dir = Path(args.state_dir)
    out = Path(args.out) if args.out else state_dir / "dashboard"
    scrub = Scrubber()
    now = args.now if args.now is not None else time.time()
    runs = history(state_dir)
    data = {
        "runs": runs_rows(runs, scrub),
        "latest": latest_rows(runs, scrub),
        "gate": gate_rows(Path(args.gate_timings)),
        "doctor": doctor_rows(Path(args.doctor_stats)),
        "load": load_rows(Path(args.load_samples), now),
        "agent_time": agent_rows(Path(args.perf_dir), now),
    }
    manifest = []
    files = {}
    for dataset_id, title, description, stale in MANIFEST:
        name = f"{dataset_id}.json"
        entry = {"id": dataset_id, "title": title, "description": description, "file": name}
        if stale:
            entry["staleAfterHours"] = stale
        manifest.append(entry)
    try:
        pattern = load_private_pattern(Path(args.pattern_env))
        apply_private(data, pattern)
        for entry in manifest:
            files[entry["file"]] = json.dumps(data[entry["id"]], indent=1, sort_keys=True) + "\n"
        files["manifest.json"] = json.dumps(manifest, indent=1) + "\n"
        leaks = grep_count(pattern, "".join(files.values()))
        if leaks:
            raise PrivatePatternMissing(f"{leaks} output line(s) still match the private pattern")
    except PrivatePatternMissing as error:
        print(f"dashboard-export: refusing to export, nothing written: {error}", file=sys.stderr)
        return 2
    out.mkdir(parents=True, exist_ok=True)
    for name, body in files.items():
        tmp = out / f".{name}.tmp"
        tmp.write_text(body)
        tmp.replace(out / name)
    for entry in manifest:
        print(f"dashboard-export: {entry['id']} {len(data[entry['id']])} row(s)")
    print(f"dashboard-export: wrote {str(out).replace(str(HOME), '~')}/manifest.json")
    return 0

if __name__ == "__main__":
    sys.exit(main())
