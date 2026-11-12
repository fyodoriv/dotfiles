#!/usr/bin/env python3
"""Validate bounded, order-balanced status timing observations."""
import statistics

CASES = ("plain", "short", "short_branch", "porcelain_v1")
FLAGS = ("admission", "source", "tools", "output", "load")


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
