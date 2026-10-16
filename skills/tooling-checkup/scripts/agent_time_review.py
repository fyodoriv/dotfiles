"""Summarize where agent tool time went, and list speedup tasks to file.

Reads `agent-perf.mjs report --json` (agentbrew per-step timing) for all
projects and for each project, plus the session-report analyzer for tokens
and hours. Prints the top recurring slow steps, a known fix for each step that
matches a safe fix pattern, speedup task candidates, and the metrics to store
with `checkup_state.py record`.

Usage: python3 agent_time_review.py [--days N] [--json]

Inputs (environment overrides, used by tests):
  AGENT_PERF_SCRIPT      default ~/.config/agentbrew/scripts/agent-perf.mjs
  SESSION_REPORT_SCRIPT  default: the installed session-report analyze-sessions.mjs
  AGENT_PERF_DIR         default ${XDG_STATE_HOME:-~/.local/state}/agentbrew/perf
  TOOLING_ROOT           default ~/apps/tooling

It never prints prompts, commands beyond the redacted step key, or file paths.
"""

import argparse
import datetime as dt
import glob
import json
import os
import pathlib
import re
import shlex
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from checkup_state import state_path  # noqa: E402

RECURRING_MIN_CALLS = 2
# A step must recur across sessions before it becomes a speedup task. A step
# that repeats inside one session (for example under a one-off load spike)
# is not a recurring cost.
RECURRING_MIN_SESSIONS = 2
TASK_MIN_MS_PER_DAY = 60_000

# Known safe fix patterns, matched on the redacted step key.
FIX_PATTERNS = [
    (re.compile(r"^(until|while|sleep|watch)\b"),
     "polling loop: wait on the event instead (`gh pr checks --watch`, `wait <pid>`, "
     "a Monitor until-condition), or raise the poll interval"),
    (re.compile(r"^(npm (ci|install)|pnpm install|yarn install|bun install|pip install|uv sync)\b"),
     "repeated full install: skip it when the lockfile is unchanged, "
     "or use `npm ci --prefer-offline --no-audit --no-fund`"),
    (re.compile(r"^(make (test-all|test|check)|npm (test|run (test|verify|check))|pnpm (test|run)|"
                r"bats|npx vitest|vitest|jest|pytest)\b"),
     "full gate or test run: use affected-test selection in the inner loop "
     "(`bin/bats-affected`, `vitest --changed`, `pytest --lf`) and run the full gate once; "
     "if `ps -o pri,comm` shows PRI 4, the runner is on background QoS (see `bin/cursor-priority`)"),
    (re.compile(r"^git (fetch|clone|pull)\b"),
     "network git: fetch once per session, clone with `--filter=blob:none`"),
    (re.compile(r"^agent:"),
     "subagent: give it a narrower prompt, or run it in the background while you work"),
]


def fmt_ms(ms) -> str:
    ms = float(ms or 0)
    if ms < 1000:
        return f"{ms:.0f}ms"
    secs = ms / 1000
    if secs < 60:
        return f"{secs:.1f}s"
    if secs < 3600:
        return f"{int(secs // 60)}m{int(secs % 60):02d}s"
    return f"{secs / 3600:.1f}h"


def fix_hint(key: str) -> str:
    for pattern, hint in FIX_PATTERNS:
        if pattern.search(key):
            return hint
    return ""


def slug(key: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", key.lower()).strip("-")[:48]


def perf_script() -> str:
    return os.environ.get("AGENT_PERF_SCRIPT") or os.path.expanduser("~/.config/agentbrew/scripts/agent-perf.mjs")


def session_report_script() -> str:
    if os.environ.get("SESSION_REPORT_SCRIPT"):
        return os.environ["SESSION_REPORT_SCRIPT"]
    patterns = [
        "~/.claude/skills/session-report/analyze-sessions.mjs",
        "~/.claude/plugins/marketplaces/*/plugins/session-report/skills/session-report/analyze-sessions.mjs",
    ]
    for pattern in patterns:
        hits = sorted(glob.glob(os.path.expanduser(pattern)))
        if hits:
            return hits[0]
    return ""


def run_json(command, timeout=60):
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=timeout, stdin=subprocess.DEVNULL)
    except (FileNotFoundError, subprocess.TimeoutExpired) as error:
        return None, str(error)
    if result.returncode != 0:
        return None, (result.stderr.strip().splitlines() or [f"exit {result.returncode}"])[-1]
    try:
        return json.loads(result.stdout), ""
    except json.JSONDecodeError as error:
        return None, f"bad JSON: {error}"


def perf_report(days: int, project: str = ""):
    scope = ["--project", project] if project else ["--all"]
    return run_json(["node", perf_script(), "report", *scope, "--days", str(days), "--json"])


def tool_rows_in_log(days: int):
    """Yield tool rows (rows with `ms`) in the perf log window."""
    base = os.environ.get("AGENT_PERF_DIR") or os.path.join(
        os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "agentbrew", "perf")
    since = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=days)
    for path in sorted(glob.glob(os.path.join(base, "*.jsonl")))[-2:]:
        try:
            lines = pathlib.Path(path).read_text(errors="replace").splitlines()
        except OSError:
            continue
        for line in lines:
            try:
                row = json.loads(line)
                ts = dt.datetime.fromisoformat(str(row.get("ts", "")).replace("Z", "+00:00"))
            except (json.JSONDecodeError, ValueError, AttributeError):
                continue
            if ts >= since and row.get("project") and "ms" in row:
                yield row


def projects_in_log(days: int) -> list:
    """Distinct project names in the perf log window (reads the project field only)."""
    return sorted({str(row["project"]) for row in tool_rows_in_log(days)})


def sessions_by_step(days: int) -> dict:
    """Map (project, step key) to its number of distinct sessions in the window.

    The step key matches agent-perf.mjs `summarize`: `key`, else `tool`.
    """
    sids = {}
    for row in tool_rows_in_log(days):
        key = row.get("key") or row.get("tool") or "unknown"
        sids.setdefault((str(row["project"]), key), set()).add(row.get("sid") or "")
    return {k: len(v - {""}) for k, v in sids.items()}


def tooling_repo(project: str) -> str:
    """Map a perf project name to a tooling repo name, or '' when it is not one."""
    root = pathlib.Path(os.environ.get("TOOLING_ROOT") or os.path.expanduser("~/apps/tooling"))
    if (root / project / ".git").is_dir():
        return project
    worktree = root / "wt" / project
    if (worktree / ".git").exists():
        try:
            common = subprocess.run(
                ["git", "-C", str(worktree), "rev-parse", "--path-format=absolute", "--git-common-dir"],
                capture_output=True, text=True, timeout=10,
            ).stdout.strip()
        except subprocess.TimeoutExpired:
            return ""
        main = pathlib.Path(common).parent
        if main.parent.resolve() == root.resolve():
            return main.name
    return ""


def top_steps(report: dict, limit: int = 3) -> list:
    keys = sorted(report.get("keys", []), key=lambda k: k.get("sumMs", 0), reverse=True)
    recurring = [k for k in keys if k.get("count", 0) >= RECURRING_MIN_CALLS]
    once = [dict(k, once=True) for k in keys if k.get("count", 0) < RECURRING_MIN_CALLS]
    return (recurring + once)[:limit]


def step_line(step: dict, days: int) -> str:
    per_day = step.get("sumMs", 0) / max(days, 1)
    tag = " (once)" if step.get("once") else ""
    line = (f"{step['key']}{tag}: {fmt_ms(step.get('sumMs'))} total, {step.get('count', 0)}x, "
            f"p95 {fmt_ms(step.get('p95Ms'))}, {fmt_ms(per_day)}/day")
    hint = fix_hint(step["key"])
    return line + (f"\n         fix: {hint}" if hint else "")


def slowest_line(report: dict) -> str:
    calls = report.get("slowest") or []
    if not calls:
        return ""
    top = calls[0]
    return f"slowest single call: {top.get('key')} {fmt_ms(top.get('ms'))}"


def task_candidates(per_project: dict, days: int, sessions: dict) -> list:
    root = pathlib.Path(os.environ.get("TOOLING_ROOT") or os.path.expanduser("~/apps/tooling"))
    out = []
    for project, report in per_project.items():
        repo = tooling_repo(project)
        for step in report.get("keys", []):
            per_day = step.get("sumMs", 0) / max(days, 1)
            if step.get("count", 0) < RECURRING_MIN_CALLS or per_day < TASK_MIN_MS_PER_DAY:
                continue
            key = step["key"]
            seen_in = sessions.get((project, key), 0)
            if seen_in < RECURRING_MIN_SESSIONS:
                continue
            item = {"project": project, "repo": repo, "key": key, "msPerDay": round(per_day),
                    "count": step.get("count", 0), "sessions": seen_in, "p95Ms": step.get("p95Ms", 0),
                    "taskId": f"speed-up-{slug(key)}", "fix": fix_hint(key)}
            if "<" in key:
                item["action"] = "inspect"  # redacted key: find the real step by session first
            elif not repo:
                item["action"] = "report"
            else:
                tasks = root / repo / "TASKS.md"
                text = tasks.read_text(errors="replace") if tasks.exists() else ""
                item["action"] = "filed" if item["taskId"] in text else "file"
            out.append(item)
    return sorted(out, key=lambda i: i["msPerDay"], reverse=True)


def metrics(overall: dict, session: dict, days: int) -> dict:
    keys = overall.get("keys", [])
    recurring = [k for k in keys if k.get("count", 0) >= RECURRING_MIN_CALLS] or keys
    out = {
        f"agent_tool_hours_{days}d": round(overall.get("toolMs", 0) / 3_600_000, 2),
        f"agent_tool_calls_{days}d": overall.get("calls", 0),
        "slowest_step_p95_s": round(max((k.get("p95Ms", 0) for k in recurring), default=0) / 1000, 1),
    }
    top = top_steps(overall, 1)
    if top:
        out["top_step_key"] = top[0]["key"]
    if session:
        out[f"agent_active_hours_{days}d"] = session.get("hours", {}).get("active", 0)
        out[f"agent_output_mtokens_{days}d"] = round(session.get("output_tokens", 0) / 1e6, 2)
    return out


def last_metrics() -> dict:
    try:
        return json.loads(state_path().read_text()).get("metrics", {})
    except (OSError, json.JSONDecodeError):
        return {}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--days", type=int, default=7)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    days = args.days

    overall, error = perf_report(days)
    if overall is None:
        print(f"agent-time-review: no agent-perf data ({error}). Check `agentbrew status` for the perf-record hook.")
        return 1
    per_project = {}
    for project in projects_in_log(days):
        report, _ = perf_report(days, project)
        if report and report.get("calls", 0):
            per_project[project] = report
    session = {}
    script = session_report_script()
    if script:
        data, _ = run_json(["node", script, "--json", "--since", f"{days}d"], timeout=180)
        session = (data or {}).get("overall", {})  # never read top_prompts: it holds prompt text
    candidates = task_candidates(per_project, days, sessions_by_step(days))
    values = metrics(overall, session, days)
    previous = last_metrics()

    if args.json:
        print(json.dumps({"days": days, "overall": {k: overall.get(k) for k in ("toolMs", "calls", "failures", "previous")},
                          "top": top_steps(overall), "projects": {p: top_steps(r) for p, r in per_project.items()},
                          "tasks": candidates, "metrics": values, "lastMetrics": previous}, indent=2))
        return 0

    prev = overall.get("previous") or {}
    change = prev.get("toolMsChangePct")
    print(f"agent-time-review: last {days} day(s), all projects")
    print(f"  tool time {fmt_ms(overall.get('toolMs'))} over {overall.get('calls', 0)} calls "
          f"({overall.get('failures', 0)} failed); previous window {fmt_ms(prev.get('toolMs'))}"
          + (f" ({change:+.0f}%)" if isinstance(change, (int, float)) else ""))
    if session:
        tokens = session.get("input_tokens", {})
        print(f"  sessions {session.get('sessions', 0)}, active {session.get('hours', {}).get('active', 0)} h, "
              f"wall {session.get('hours', {}).get('wall_clock', 0)} h, input {tokens.get('total', 0) / 1e6:.0f}M tokens "
              f"({tokens.get('pct_cached', 0)}% cached), output {session.get('output_tokens', 0) / 1e6:.1f}M")
    else:
        print("  session-report analyzer not found: no token or hour numbers")
    print("  top steps overall (recurring = 2+ calls):")
    for i, step in enumerate(top_steps(overall), 1):
        print(f"    {i}. {step_line(step, days)}")
    if slowest_line(overall):
        print(f"    {slowest_line(overall)}")
    for project, report in per_project.items():
        print(f"  {project}: {fmt_ms(report.get('toolMs'))} over {report.get('calls', 0)} calls")
        for i, step in enumerate(top_steps(report), 1):
            print(f"    {i}. {step_line(step, days)}")
        if slowest_line(report):
            print(f"    {slowest_line(report)}")
    print(f"  speedup tasks (recurring in {RECURRING_MIN_SESSIONS}+ sessions, {TASK_MIN_MS_PER_DAY // 60000}+ min/day):")
    if not candidates:
        print(f"    none: no step in {RECURRING_MIN_SESSIONS}+ sessions costs 1 min/day or more")
    for item in candidates:
        where = item["repo"] or item["project"]
        print(f"    {item['action']:<7} {where} {item['taskId']}: {item['key']} costs "
              f"{fmt_ms(item['msPerDay'])}/day ({item['count']}x in {item['sessions']} sessions, p95 {fmt_ms(item['p95Ms'])})"
              + (f"; fix: {item['fix']}" if item["fix"] else ""))
    print("  vs last checkup:")
    for name, value in values.items():
        print(f"    {name}: {previous.get(name, 'none')} -> {value}")
    record = " ".join(f"--metric {shlex.quote(f'{k}={v}')}" for k, v in values.items())
    print(f"  record: {record}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
