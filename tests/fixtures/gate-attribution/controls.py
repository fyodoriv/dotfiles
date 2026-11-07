import contextlib
import copy
import io
import json
import sys

from join import join

STEPS = ("lint", "lint-tasks", "test", "plugins-bash32", "e2e", "total")
MARKERS = ("FIXTURE_PRIVATE_COMMAND", "FIXTURE_PRIVATE_PATH", "FIXTURE_PRIVATE_PROJECT", "FIXTURE_PRIVATE_PROMPT")


def invocation(name, session="session-a", failed=False):
    steps = ("lint", "total") if failed else STEPS
    status = 2 if failed else 0
    return {"session": session, "invocation": name, "steps": [{"step": step, "status": status} for step in steps]}


def completion(tool, name, session="session-a"):
    return {"session": session, "tool": tool, "receipt": name}


def matched(tool, inv, steps=STEPS):
    return {"outcome": "match", "reason": "matched", "tool": tool, "invocation": inv, "steps": sorted(steps)}


def unknown(reason):
    return {"outcome": "unknown", "reason": reason}


def control(name):
    primary = invocation("inv-a")
    packet = {"invocations": [primary], "completions": [completion("tool-a", "inv-a")], "events": ["begin:tool-a", "end:tool-a"], "private": list(MARKERS)}
    results = [matched("tool-a", "inv-a")]
    accounted = ["linked"]
    if name == "valid_failure":
        packet["invocations"][0] = invocation("inv-a", failed=True)
        results = [matched("tool-a", "inv-a", ("lint", "total"))]
    elif name in ("valid_overlap_a", "valid_overlap_b"):
        packet["invocations"].append(invocation("inv-b"))
        packet["completions"].append(completion("tool-b", "inv-b"))
        packet["events"] = ["begin:tool-a", "begin:tool-b", "end:tool-a", "end:tool-b"]
        results.append(matched("tool-b", "inv-b"))
        accounted.append("linked")
        if name == "valid_overlap_b":
            packet["invocations"].reverse()
            packet["completions"].reverse()
            results.reverse()
            accounted.reverse()
    elif name == "valid_reordered":
        primary["steps"].reverse()
    elif name == "valid_nested":
        packet["completions"].append({"session": "session-a", "tool": "nested", "receipt": None, "parent": "tool-a"})
        packet["events"] = ["begin:tool-a", "begin:nested", "end:nested", "end:tool-a"]
        results.append(unknown("missing"))
    elif name == "unknown_missing":
        packet["completions"][0]["receipt"] = None
    elif name == "unknown_truncated":
        packet["completions"][0]["truncated"] = True
    elif name == "unknown_duplicate_completion":
        packet["completions"].append(copy.deepcopy(packet["completions"][0]))
    elif name == "unknown_duplicate_invocation":
        packet["invocations"].append(copy.deepcopy(primary))
    elif name == "unknown_missing_step":
        primary["steps"].pop(1)
    elif name == "unknown_status":
        primary["steps"][0]["status"] = 2
    elif name == "unknown_replay":
        packet["completions"][0]["session"] = "session-b"
    elif name == "unknown_malformed":
        packet["completions"][0]["receipt"] = ["inv-a"]
    elif name != "valid_success":
        raise ValueError("unknown control")
    if name.startswith("unknown_"):
        reason = name.removeprefix("unknown_")
        results = [unknown(reason) for _ in packet["completions"]]
        accounted = ["unpaired" for _ in packet["invocations"]]
    return packet, {"completions": results, "invocations": accounted}


def main():
    packet, expected = control(sys.argv[1])
    original = copy.deepcopy(packet)
    captured = io.StringIO()
    try:
        with contextlib.redirect_stdout(captured), contextlib.redirect_stderr(captured):
            actual = join(packet)
    except Exception:
        print("synthetic join rejected: exception")
        return 1
    if captured.getvalue():
        print("synthetic join rejected: unexpected output")
        return 1
    if actual == {"outcome": "unknown", "reason": "unimplemented"}:
        print("synthetic join rejected: unimplemented")
        return 1
    if packet != original or actual != expected:
        print("synthetic join rejected: outcome")
        return 1
    encoded = json.dumps(actual)
    if any(marker in encoded for marker in MARKERS):
        print("synthetic join rejected: disclosure")
        return 1
    print("synthetic control passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
