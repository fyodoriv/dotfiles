"""Public synthetic controls. Never read the sealed observation files."""

import hashlib
import json
import sys
from copy import deepcopy

from join_companion import Refusal, join_companion


def encode(packet):
    return json.dumps(packet, separators=(",", ":")).encode("utf-8")


def sha(packet):
    return hashlib.sha256(packet).hexdigest()


ROOT = {"boot": "control-boot", "view": "control-view", "pid": 1, "birth": 10, "covers_queue": True}
WALK = [{"process": [4, 40], "parent": [1, 10]}, {"process": [1, 10], "parent": None}]
RESERVATION = {"controller": [4, 40], "payload": [8, 80], "slot": "normal:1", "generation": 2}
OUTSIDE = {
    "host_qualified": True,
    "queue_descriptor": "canonical",
    "boot_identity": "control-boot",
    "view_complete": True,
    "ancestry_before": WALK,
    "ancestry_after": WALK,
    "reservations_before": [],
    "reservations_after": [],
    "epoch_before": 2,
    "epoch_after": 2,
    "chain_complete": True,
    "inherited_marker": False,
}
OWNED_WALK = [{"process": [8, 80], "parent": [4, 40]}, *WALK]
OWNED = {
    **OUTSIDE,
    "ancestry_before": OWNED_WALK,
    "ancestry_after": OWNED_WALK,
    "reservations_before": [RESERVATION],
    "reservations_after": [RESERVATION],
}
SYNTHETIC_CASES = [
    (OUTSIDE, ROOT, ROOT),
    (OWNED, ROOT, ROOT),
    (OUTSIDE, None, None),
    (OUTSIDE, ROOT, None),
    (OUTSIDE, ROOT, {**ROOT, "view": "other-view"}),
    ({**OUTSIDE, "ancestry_after": [{**WALK[0], "parent": [1, 11]}, {"process": [1, 11], "parent": None}]}, ROOT, ROOT),
    ({**OUTSIDE, "ancestry_after": WALK[:1]}, ROOT, ROOT),
    (
        {**OWNED, "reservations_after": [RESERVATION, {"slot": "normal:2", "controller": [4, 41], "payload": [9, 90], "generation": 3}]},
        ROOT,
        ROOT,
    ),
    ({**OWNED, "reservations_after": [{**RESERVATION, "payload": [8, 81]}]}, ROOT, ROOT),
    (
        {
            **OWNED,
            "ancestry_after": [{"process": [8, 81], "parent": [4, 40]}, *WALK],
            "reservations_after": [{**RESERVATION, "payload": [8, 81]}],
        },
        ROOT,
        ROOT,
    ),
    (OUTSIDE, ROOT, {**ROOT, "covers_queue": False}),
    ({**OUTSIDE, "epoch_after": 3}, ROOT, ROOT),
]


def packets(specimens):
    cases = []
    entries = []
    for index, (observation, before, after) in enumerate(specimens):
        case_id = f"R{index + 1:02d}"
        cases.append({"id": case_id, "observation": observation})
        entries.append({"id": case_id, "root_before": before, "root_after": after})
    source = {"version": 2, "cases": cases}
    return source, {"version": 1, "observation_sha256": sha(encode(source)), "entries": entries[::-1]}


def check_projections():
    source, companion = packets(SYNTHETIC_CASES)
    source_bytes, companion_bytes = encode(source), encode(companion)
    joined = join_companion(
        source_bytes, companion_bytes, observation_hash=sha(source_bytes), companion_hash=sha(companion_bytes)
    )
    for index, (observation, before, after) in enumerate(SYNTHETIC_CASES):
        expected = {**observation, "root_before": before, "root_after": after}
        if joined.get(f"R{index + 1:02d}") != expected:
            raise Refusal("synthetic_projection")
    if len(joined) != 12:
        raise Refusal("synthetic_count")
    print("synthetic projections: 12/12")


def invalid_pair(control):
    source, companion = deepcopy(packets(SYNTHETIC_CASES[:2]))
    if control == "J03":
        companion["observation_sha256"] = "0" * 64
    elif control == "J04":
        source["cases"].append(source["cases"][0])
    elif control == "J05":
        companion["entries"].append(companion["entries"][0])
    elif control == "J06":
        companion["entries"].pop()
    elif control == "J07":
        companion["entries"].append({**companion["entries"][0], "id": "PRIVATE_MARKER_UNKNOWN"})
    elif control == "J08":
        entry = companion["entries"][0]
        entry["root_before"] = {**entry["root_before"], "pid": True}
    elif control == "J09":
        source["cases"][0]["observation"]["root_before"] = "PRIVATE_MARKER_CONFLICT"

    source_bytes = encode(source)
    if control != "J03":
        companion["observation_sha256"] = sha(source_bytes)
    companion_bytes = encode(companion)
    if control == "J10":
        companion_bytes = companion_bytes.replace(b'"version":1', b'"version":1,"version":1', 1)

    observation_hash, companion_hash = sha(source_bytes), sha(companion_bytes)
    if control == "J01":
        source_bytes = b"\xff" + source_bytes
    if control == "J02":
        companion_bytes = b"\xff" + companion_bytes
        source_bytes = b"\xff" + source_bytes
        observation_hash = sha(source_bytes)
    return source_bytes, companion_bytes, observation_hash, companion_hash


REFUSALS = {
    "J01": "observation_hash",
    "J02": "companion_hash",
    "J03": "source_binding",
    "J04": "duplicate_case_id",
    "J05": "duplicate_case_id",
    "J06": "case_set",
    "J07": "case_set",
    "J08": "invalid_root",
    "J09": "observation_conflict",
    "J10": "duplicate_key",
}


def check_refusals():
    for control, expected in REFUSALS.items():
        source, companion, observation_hash, companion_hash = invalid_pair(control)
        try:
            join_companion(source, companion, observation_hash=observation_hash, companion_hash=companion_hash)
        except Refusal as error:
            if str(error) != expected:
                raise Refusal("wrong_refusal") from None
        else:
            raise Refusal("missing_refusal")
    print("invalid controls refused: 10/10")


if __name__ == "__main__":
    try:
        check_projections()
        check_refusals()
    except Refusal:
        sys.exit("compiler root companion control failed")
