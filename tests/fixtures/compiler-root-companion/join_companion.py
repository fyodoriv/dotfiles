"""Fixture-only join. Callers supply hashes from separate registrations."""

import hashlib
import json


class Refusal(ValueError):
    """A fixed intake result safe to report without showing fixture data."""


def unique_fields(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise Refusal("duplicate_key")
        result[key] = value
    return result


def invalid_constant(_):
    raise Refusal("invalid_json")


def decode(packet, fields, version):
    try:
        value = json.loads(
            packet.decode("utf-8"),
            object_pairs_hook=unique_fields,
            parse_constant=invalid_constant,
        )
    except Refusal:
        raise
    except (ValueError, RecursionError):
        raise Refusal("invalid_json") from None
    if (
        not isinstance(value, dict)
        or value.keys() != fields
        or type(value["version"]) is not int
        or value["version"] != version
    ):
        raise Refusal("invalid_packet")
    return value


def index(records, fields):
    if not isinstance(records, list) or not records:
        raise Refusal("invalid_records")
    entries = {}
    for record in records:
        if not isinstance(record, dict) or record.keys() != fields:
            raise Refusal("invalid_records")
        case_id = record["id"]
        if not isinstance(case_id, str) or not case_id:
            raise Refusal("invalid_case_id")
        if case_id in entries:
            raise Refusal("duplicate_case_id")
        entries[case_id] = record
    return entries


def validate_root(root):
    if root is None:
        return
    if (
        not isinstance(root, dict)
        or root.keys() != {"boot", "view", "pid", "birth", "covers_queue"}
        or any(not isinstance(root[key], str) or not root[key] for key in ("boot", "view"))
        or type(root["pid"]) is not int
        or root["pid"] < 1
        or type(root["birth"]) is not int
        or root["birth"] < 1
        or type(root["covers_queue"]) is not bool
    ):
        raise Refusal("invalid_root")


def join_companion(observation_bytes, companion_bytes, *, observation_hash, companion_hash):
    """Return harness-only lookup; no candidate receives this mapping."""
    if hashlib.sha256(observation_bytes).hexdigest() != observation_hash:
        raise Refusal("observation_hash")
    if hashlib.sha256(companion_bytes).hexdigest() != companion_hash:
        raise Refusal("companion_hash")

    observation_packet = decode(observation_bytes, {"version", "cases"}, 2)
    companion_packet = decode(companion_bytes, {"version", "observation_sha256", "entries"}, 1)
    if companion_packet["observation_sha256"] != observation_hash:
        raise Refusal("source_binding")

    observations = index(observation_packet["cases"], {"id", "observation"})
    companions = index(companion_packet["entries"], {"id", "root_before", "root_after"})
    if observations.keys() != companions.keys():
        raise Refusal("case_set")

    joined = {}
    for case_id, case in observations.items():
        observation = case["observation"]
        if not isinstance(observation, dict):
            raise Refusal("invalid_observation")
        if observation.keys() & {"id", "expected", "verdict", "root_before", "root_after"}:
            raise Refusal("observation_conflict")
        entry = companions[case_id]
        validate_root(entry["root_before"])
        validate_root(entry["root_after"])
        joined[case_id] = {
            **observation,
            "root_before": entry["root_before"],
            "root_after": entry["root_after"],
        }
    return joined
