"""Synthetic receipt join. This is not an installed gate or agent hook."""

import re

SUCCESS = frozenset(("lint", "lint-tasks", "test", "plugins-bash32", "e2e", "total"))
FAILURE = frozenset(("lint", "total"))
TOKEN = re.compile(r"[A-Za-z0-9_-]{1,64}\Z")


def token(value):
    return isinstance(value, str) and TOKEN.fullmatch(value) is not None


def refused(reason):
    return {"outcome": "unknown", "reason": reason}


def join(packet):
    invocations = packet["invocations"]
    completions = packet["completions"]
    results = []
    linked = set()
    for completion in completions:
        session = completion.get("session")
        tool = completion.get("tool")
        receipt = completion.get("receipt")
        if completion.get("truncated") is True:
            results.append(refused("truncated"))
            continue
        if receipt is None:
            results.append(refused("missing"))
            continue
        if not all(token(v) for v in (session, tool, receipt)):
            results.append(refused("malformed"))
            continue
        same_completion = [c for c in completions if c.get("session") == session and
                           (c.get("tool") == tool or c.get("receipt") == receipt)]
        if len(same_completion) != 1:
            results.append(refused("duplicate_completion"))
            continue
        candidates = [(index, inv) for index, inv in enumerate(invocations)
                      if inv.get("session") == session and inv.get("invocation") == receipt]
        if not candidates:
            results.append(refused("replay"))
            continue
        if len(candidates) != 1:
            results.append(refused("duplicate_invocation"))
            continue
        index, inv = candidates[0]
        rows = inv.get("steps")
        if not isinstance(rows, list) or any(not isinstance(row, dict) for row in rows):
            results.append(refused("missing_step"))
            continue
        steps = [row.get("step") for row in rows]
        if (any(not isinstance(step, str) for step in steps) or
                len(set(steps)) != len(steps) or
                frozenset(steps) not in (SUCCESS, FAILURE)):
            results.append(refused("missing_step"))
            continue
        expected_status = 0 if frozenset(steps) == SUCCESS else 2
        if any(type(row.get("status")) is not int or row["status"] != expected_status for row in rows):
            results.append(refused("status"))
            continue
        results.append({"outcome": "match", "reason": "matched", "tool": tool,
                        "invocation": receipt, "steps": sorted(steps)})
        linked.add(index)
    return {"completions": results,
            "invocations": ["linked" if index in linked else "unpaired" for index in range(len(invocations))]}
