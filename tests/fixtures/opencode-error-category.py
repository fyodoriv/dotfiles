#!/usr/bin/python3
"""Emit only a fixed category for an isolated OpenCode command's output."""
import sys


def classify(output: str) -> str:
    text = output.lower()
    if "http 401" in text or "http 403" in text or "unauthorized" in text:
        return "http-auth"
    if "http 500" in text or "http 503" in text:
        return "http-server"
    if "permission denied" in text or "operation not permitted" in text:
        return "permission"
    if "connection refused" in text or "econnrefused" in text or "timed out" in text:
        return "connection"
    return "unknown"


if __name__ == "__main__":
    print(classify(sys.stdin.read(65536)))
