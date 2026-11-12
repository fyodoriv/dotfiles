"""Parse and compare source receipts without JSON type coercion."""
import json
import math


def strict_json(data):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("duplicate JSON field")
            result[key] = value
        return result

    def invalid_constant(_value):
        raise ValueError("invalid JSON number")

    def finite_float(value):
        result = float(value)
        if not math.isfinite(result):
            raise ValueError("invalid JSON number")
        return result

    return json.loads(data, object_pairs_hook=unique, parse_constant=invalid_constant, parse_float=finite_float)


def same_json(left, right):
    return json.dumps(left, sort_keys=True, allow_nan=False) == json.dumps(right, sort_keys=True, allow_nan=False)
