#!/usr/bin/env python3
"""Validate bounded, order-balanced status timing observations."""
import json
import statistics

CASES = ("plain", "short", "short_branch", "porcelain_v1")
FLAGS = ("admission", "source", "tools", "output", "load")
COMMANDS = {"plain": "git status", "short": "git status --short", "short_branch": "git status -s -b",
            "porcelain_v1": "git status --porcelain=v1"}


def payload(case):
    if type(case) is not str or case not in COMMANDS:
        raise ValueError("unknown status case")
    return json.dumps({"tool_input": {"command": COMMANDS[case]}, "cwd": "/tmp"},
                      separators=(",", ":")).encode("ascii")


def summarize(cases, flags):
    result = {"valid": False, "passed": False, "median_ratios": {}}
    if type(cases) is not dict or set(cases) != set(CASES):
        return result
    if type(flags) is not dict or set(flags) != set(FLAGS) or not all(flags[k] is True for k in FLAGS):
        return result
    medians = {}
    for case_index, name in enumerate(CASES):
        rows = cases[name]
        if type(rows) is not list or len(rows) != 15:
            return result
        ratios = []
        for index, row in enumerate(rows):
            if type(row) is not dict or set(row) != {"order", "old_ns", "new_ns"}:
                return result
            if row["order"] != ("old-first" if (index + case_index) % 2 == 0 else "new-first"):
                return result
            old, new = row["old_ns"], row["new_ns"]
            if any(type(value) is not int or not 0 < value < 2**63 for value in (old, new)):
                return result
            ratios.append(new / old)
        medians[name] = statistics.median(ratios)
    result["valid"] = True
    result["median_ratios"] = medians
    result["passed"] = all(value <= 0.80 for value in medians.values())
    return result


def capture(run_one, preflight, postflight, record_attempt=None):
    """Collect bounded samples; callers must establish the supplied checks.

    Interruptions propagate after postflight and do not return partial data.
    A trusted launcher must supply a durable sink and manage owned children.
    """
    samples = {name: [] for name in CASES}
    attempts = []
    result = {"valid": False, "passed": False, "median_ratios": {}, "samples": samples,
              "attempts": attempts, "failure": {"phase": "preflight"}, "postflight_ok": None}
    if not callable(record_attempt):
        result["failure"] = {"phase": "persistence"}
        return result
    try:
        if preflight() is not True:
            return result
    except Exception:
        return result
    failure = None
    try:
        for case_index, name in enumerate(CASES):
            for index in range(15):
                order = ("old", "new") if (index + case_index) % 2 == 0 else ("new", "old")
                elapsed = {}
                for side in order:
                    attempt = {"case": name, "index": index, "side": side,
                               "order": order[0] + "-first", "elapsed_ns": None, "outcome": "exception"}
                    attempts.append(attempt)
                    persistence_failed = False
                    try:
                        observation = run_one(name, side)
                        if type(observation) is tuple and len(observation) == 4:
                            duration, status, stdout, stderr = observation
                            if type(duration) is int and 0 < duration < 2**63:
                                attempt["elapsed_ns"] = duration
                            if (attempt["elapsed_ns"] is not None and type(status) is int and status == 0 and
                                    type(stdout) is bytes and stdout == b"" and type(stderr) is bytes and stderr == b""):
                                attempt["outcome"] = "ok"
                                elapsed[side] = duration
                            else:
                                attempt["outcome"] = "invalid"
                        else:
                            attempt["outcome"] = "invalid"
                    except Exception:
                        pass
                    except BaseException:
                        attempt["outcome"] = "interrupted"
                        raise
                    finally:
                        try:
                            persistence_failed = record_attempt(dict(attempt)) is not True
                        except Exception:
                            persistence_failed = True
                    if persistence_failed:
                        failure = {"phase": "persistence", "case": name, "index": index, "side": side}
                        break
                    if attempt["outcome"] != "ok":
                        failure = {"phase": "sample", "case": name, "index": index, "side": side}
                        break
                if failure:
                    break
                samples[name].append({"order": order[0] + "-first", "old_ns": elapsed["old"],
                                      "new_ns": elapsed["new"]})
            if failure:
                break
    finally:
        try:
            result["postflight_ok"] = postflight() is True
        except Exception:
            result["postflight_ok"] = False
    if failure is None and not result["postflight_ok"]:
        failure = {"phase": "postflight"}
    if failure is not None:
        result["failure"] = failure
        return result
    summary = summarize(samples, dict.fromkeys(FLAGS, True))
    result.update(summary)
    result["failure"] = None if summary["valid"] else {"phase": "summary"}
    return result
