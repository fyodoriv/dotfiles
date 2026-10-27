"""One fast, read-only pass over the machine and tooling metrics on disk.

Reads only files that LaunchAgents and earlier runs already wrote, plus one
`ps` and one `df`. It runs in about a second, so the checkup can run it every
time. Each metric gets a verdict:

  ok    nothing to do
  warn  report it
  act   fix it now in the owning source repo, or file a task

The last lines say whether the Claude Code echo test (Phase 6) must run, and
which `record:` metrics to store.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import time
from collections import Counter
from pathlib import Path

HOME = Path.home()
DEFAULTS = {
    "samples": HOME / ".local/state/dotfiles/load-samples.tsv",
    "upgrade_log": HOME / ".local/share/dotfiles/logs/dotfiles-upgrade.log",
    "state": HOME / ".local/state/tooling-checkup/last-run.json",
    "claude_json": HOME / ".claude.json",
    "explained_file": HOME / ".config/dotfiles/explained-load",
}

# Known heavy foreground apps that explain overload on purpose (for example
# game streaming). An overload row with one of them in its top 3 processes is
# "explained": it is counted apart and never gets the `act` verdict.
# DOTFILES_EXPLAINED_LOAD (comma or space separated) replaces this default;
# ~/.config/dotfiles/explained-load (one name per line, # comments) adds to it;
# a space in a name there matches the sampler's "_" (Google Chrome = Google_Chrome).
# In DOTFILES_EXPLAINED_LOAD (split on spaces), write that space as "_".
EXPLAINED_LOAD_DEFAULT = ("GeForceNOW",)

# Thresholds. Overload means load1 above twice the core count.
OVERLOAD_FACTOR = 2
OVERLOAD_ACT_ROWS = 10  # 10 rows at 30 s each: 5 minutes of overload
FREE_MEM_WARN, FREE_MEM_ACT = 10, 5  # percent
SWAP_WARN_MB, SWAP_ACT_MB = 4096, 8192
DISK_WARN_GB, DISK_ACT_GB = 50, 20
SESSIONS_WARN = 4
CLAUDE_JSON_WARN_MB = 5
ECHO_P95_TRIGGER_MS = 50
BACKGROUND_PRI = 4  # darwin background band: timers fire late, keys lag


def verdict(value, warn, act, higher_is_worse=True):
    if value is None:
        return "unknown"
    if higher_is_worse:
        return "act" if value >= act else "warn" if value >= warn else "ok"
    return "act" if value <= act else "warn" if value <= warn else "ok"


def load_samples(path, hours, now):
    """Rows: epoch, time, load1, load5, load15, cpus, free %, swap MB, procs, top3, busy %, owners."""
    rows = []
    try:
        lines = Path(path).read_text().splitlines()
    except OSError:
        return rows
    cutoff = now - hours * 3600
    for line in lines:
        f = line.split("\t")
        if len(f) < 9:
            continue
        try:
            epoch = int(f[0])
            if epoch < cutoff:
                continue
            rows.append({
                "epoch": epoch,
                "time": f[1],
                "load1": float(f[2]),
                "cpus": int(f[5]),
                "free": float(f[6]),
                "swap": float(f[7]),
                "top": f[9] if len(f) > 9 else "",
                "owners": f[11] if len(f) > 11 else "",
            })
        except ValueError:
            continue
    return rows


def explained_leaders(path):
    env = os.environ.get("DOTFILES_EXPLAINED_LOAD")
    names = set(re.split(r"[,\s]+", env.strip())) - {""} if env is not None else set(EXPLAINED_LOAD_DEFAULT)
    try:
        for line in Path(path).read_text().splitlines():
            line = line.split("#", 1)[0].strip()
            if line:
                # The sampler writes a space in a process name as "_" (#308).
                names.add(line.replace(" ", "_"))
    except OSError:
        pass
    return names


def top_names(row):
    return [item.rsplit(":", 1)[0] for item in row["top"].split()]


INTERPRETERS = {"node", "python", "python3", "bash", "zsh", "sh", "ruby", "perl", "deno", "bun"}


def owner_label(name, owner):
    """`node (vitest, parent claude)` from a sampler owner item `pid/ppid/parent/command` (#358)."""
    parts = owner.split("/", 3)
    if len(parts) < 4:
        return name
    parent, cmd = parts[2], parts[3].split()
    hint = ""
    if cmd and cmd[0].rsplit("/", 1)[-1] in INTERPRETERS:
        hint = next((a.rsplit("/", 1)[-1] for a in cmd[1:] if not a.startswith("-")), "")
    label = ", ".join(x for x in (hint, f"parent {parent}" if parent else "") if x)
    return f"{name} ({label})" if label else name


def row_labels(row):
    names = top_names(row)
    owners = [o.strip() for o in row.get("owners", "").split(" | ")] if row.get("owners") else []
    return [owner_label(n, owners[i]) if i < len(owners) else n for i, n in enumerate(names)]


def offender_summary(rows):
    offenders = Counter(label for r in rows for label in row_labels(r))
    return ", ".join(f"{name} x{n}" for name, n in offenders.most_common(3)) or "none"


def sampler_metrics(rows, explained=frozenset()):
    out = []
    if not rows:
        out.append(("load_overload_rows", None, "unknown", "no load samples; is com.dotfiles.load-sampler loaded?"))
        return out, {}
    cpus = rows[-1]["cpus"] or 1
    peak = max(rows, key=lambda r: r["load1"])
    over = [r for r in rows if r["load1"] > OVERLOAD_FACTOR * cpus]
    known = [r for r in over if explained.intersection(top_names(r))]
    unknown = [r for r in over if not explained.intersection(top_names(r))]
    v = "act" if len(unknown) >= OVERLOAD_ACT_ROWS else "warn" if unknown else "ok"
    out.append(("load_overload_rows", len(unknown), v,
                f"load1 > {OVERLOAD_FACTOR * cpus}, not explained; peak {peak['load1']:.1f} at {peak['time']}; "
                f"top in overload: {offender_summary(unknown)}"))
    out.append(("load_overload_rows_explained", len(known), "warn" if known else "ok",
                f"overload with an explained app in the top 3 ({', '.join(sorted(explained)) or 'none listed'}); "
                f"top: {offender_summary(known)}"))
    min_free = min(r["free"] for r in rows)
    out.append(("free_mem_min_pct", min_free, verdict(min_free, FREE_MEM_WARN, FREE_MEM_ACT, False), "lowest free memory"))
    max_swap = max(r["swap"] for r in rows)
    out.append(("swap_max_mb", max_swap, verdict(max_swap, SWAP_WARN_MB, SWAP_ACT_MB), "highest swap used"))
    gaps = sum(1 for a, b in zip(rows, rows[1:]) if b["epoch"] - a["epoch"] > 300)
    out.append(("sampler_gaps", gaps, "warn" if gaps else "ok", "gaps over 5 min: sleep, a freeze, or a stopped sampler"))
    return out, {"peak_load1": peak["load1"]}


def disk_metric(path="/"):
    try:
        free_gb = shutil.disk_usage(path).free / 1e9
    except OSError:
        return ("disk_free_gb", None, "unknown", path)
    return ("disk_free_gb", round(free_gb, 1), verdict(free_gb, DISK_WARN_GB, DISK_ACT_GB, False), f"free on {path}")


def upgrade_metric(path):
    """Failed Topgrade steps from the last run in the upgrade log."""
    try:
        text = Path(path).read_text(errors="replace")
    except OSError:
        return ("upgrade_failed_steps", None, "unknown", f"no log at {path}")
    last = text.rsplit("── dotfiles-upgrade ", 1)[-1]
    failed = re.findall(r"^(.+?): FAILED\s*$", last, re.M)
    return ("upgrade_failed_steps", len(failed), "warn" if failed else "ok", ", ".join(failed) or "last upgrade run")


def claude_processes(ps_text):
    """Interactive Claude Code sessions: a `claude` command with a tty."""
    sessions = []
    for line in ps_text.splitlines()[1:]:
        f = line.split(None, 3)
        if len(f) < 4:
            continue
        pid, pri, tty, comm = f
        if os.path.basename(comm.split()[0]) != "claude" or tty in ("??", "-"):
            continue
        try:
            sessions.append((int(pid), int(pri)))
        except ValueError:
            continue
    return sessions


def claude_metrics(ps_text, claude_json, state):
    out, triggers = [], []
    sessions = claude_processes(ps_text)
    background = [pid for pid, pri in sessions if pri <= BACKGROUND_PRI]
    out.append(("claude_sessions", len(sessions), "warn" if len(sessions) > SESSIONS_WARN else "ok", "interactive sessions (with a tty)"))
    out.append(("claude_background_pri", len(background), "act" if background else "ok",
                "sessions in the PRI 4 band; fix bin/app-priority" + (f" (pids {', '.join(map(str, background))})" if background else "")))
    if background:
        triggers.append(f"{len(background)} session(s) at PRI {BACKGROUND_PRI}")
    if len(sessions) > SESSIONS_WARN:
        triggers.append(f"{len(sessions)} sessions")
    cj = Path(claude_json)
    size_mb = round(cj.stat().st_size / 1e6, 2) if cj.exists() else None
    out.append(("claude_json_mb", size_mb, verdict(size_mb, CLAUDE_JSON_WARN_MB, CLAUDE_JSON_WARN_MB * 4), str(cj)))
    if size_mb is not None and size_mb >= CLAUDE_JSON_WARN_MB:
        triggers.append(f"~/.claude.json {size_mb} MB")
    orphans = len(list(cj.parent.glob(cj.name + ".tmp.*")))
    out.append(("claude_json_tmp_orphans", orphans, "warn" if orphans else "ok", "move them aside (reference/input-latency.md)"))
    if orphans:
        triggers.append(f"{orphans} ~/.claude.json.tmp files")
    last_p95 = state.get("metrics", {}).get("claude_echo_p95_ms")
    try:
        if last_p95 is not None and float(last_p95) > ECHO_P95_TRIGGER_MS:
            triggers.append(f"last claude echo p95 {last_p95} ms")
    except ValueError:
        pass
    return out, triggers, len(sessions)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--hours", type=float, default=24, help="load-sampler window (default 24)")
    ap.add_argument("--samples", default=DEFAULTS["samples"])
    ap.add_argument("--upgrade-log", default=DEFAULTS["upgrade_log"])
    ap.add_argument("--state", default=DEFAULTS["state"])
    ap.add_argument("--claude-json", default=DEFAULTS["claude_json"])
    ap.add_argument("--explained-file", default=DEFAULTS["explained_file"],
                    help="extra explained-load process names, one per line")
    ap.add_argument("--ps-file", help="saved `ps -axo pid,pri,tty,comm` output (tests)")
    ap.add_argument("--now", type=int, help="epoch to use as now (tests)")
    ap.add_argument("--lag-reported", action="store_true", help="the user reported typing lag")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    now = args.now or int(time.time())
    try:
        state = json.loads(Path(args.state).read_text())
    except (OSError, ValueError):
        state = {}
    if args.ps_file:
        ps_text = Path(args.ps_file).read_text()
    else:
        ps_text = subprocess.run(["ps", "-axo", "pid,pri,tty,comm"], capture_output=True, text=True).stdout

    metrics, extra = sampler_metrics(load_samples(args.samples, args.hours, now),
                                     explained_leaders(args.explained_file))
    metrics.append(disk_metric())
    metrics.append(upgrade_metric(args.upgrade_log))
    cm, triggers, sessions = claude_metrics(ps_text, args.claude_json, state)
    metrics += cm
    if args.lag_reported:
        triggers.insert(0, "the user reported lag")

    record = {
        "machine_overload_rows_24h": next(m[1] for m in metrics if m[0] == "load_overload_rows"),
        "machine_overload_rows_explained_24h": next((m[1] for m in metrics if m[0] == "load_overload_rows_explained"), None),
        "machine_peak_load1_24h": extra.get("peak_load1"),
        "claude_sessions": sessions,
    }
    if args.json:
        print(json.dumps({
            "metrics": [dict(name=n, value=v, verdict=d, note=t) for n, v, d, t in metrics],
            "latency_check": {"run": bool(triggers), "triggers": triggers},
            "record": record,
        }, indent=2))
        return 0

    width = max(len(m[0]) for m in metrics)
    for name, value, v, note in metrics:
        shown = "?" if value is None else value
        print(f"  {v:<7} {name:<{width}} {shown}  ({note})")
    if triggers:
        print(f"latency-check: run ({'; '.join(triggers)})")
    else:
        print("latency-check: skip (no trigger)")
    print("record: " + " ".join(f"--metric {k}={v}" for k, v in record.items() if v is not None))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
