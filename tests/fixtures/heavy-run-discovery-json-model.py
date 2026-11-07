#!/usr/bin/env python3
"""Test-only raw JSON decision model; never executes the input."""
import json
import sys


def pairs(items):
    result = {}
    for key, value in items:
        if key in result:
            raise ValueError("duplicate key")
        result[key] = value
    return result


def number(value):
    if len(value) > 128:
        raise ValueError("number too long")
    return value


def invalid_constant(_value):
    raise ValueError("non-standard constant")


def validate(value):
    if isinstance(value, str):
        if any(ord(char) == 0 or 0xD800 <= ord(char) <= 0xDFFF for char in value):
            raise ValueError("invalid string")
    elif isinstance(value, list):
        for item in value:
            validate(item)
    elif isinstance(value, dict):
        for key, item in value.items():
            validate(key)
            validate(item)


def decision():
    raw = sys.stdin.buffer.read(65537)
    if len(raw) > 65536:
        return "fallback"
    data = json.loads(raw.decode("utf-8"), object_pairs_hook=pairs,
                      parse_int=number, parse_float=number,
                      parse_constant=invalid_constant)
    validate(data)
    if not isinstance(data, dict) or not isinstance(data.get("tool_input"), dict):
        return "fallback"
    command = data["tool_input"].get("command")
    if isinstance(command, str) and command in (
        "command -v bats", "command -v bats\ncommand -v greadlink"
    ):
        return "allow"
    return "fallback"


try:
    print(decision())
except (ValueError, TypeError, UnicodeError, RecursionError, MemoryError, OverflowError, OSError):
    print("fallback")
