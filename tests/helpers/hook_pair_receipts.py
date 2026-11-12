"""Private, bounded attempt records for a future trusted timing launcher."""
import os
from pathlib import Path
import re
import stat

from hook_status_pairs import CASES
from hook_trusted_launch import read_private, strict_json, write_private_json


def private_dir(path):
    try:
        info = path.lstat()
        return (path.is_absolute() and stat.S_ISDIR(info.st_mode) and info.st_uid == os.geteuid()
                and stat.S_IMODE(info.st_mode) == 0o700)
    except OSError:
        return False


def attempt_valid(value, ordinal, require_success=False):
    if type(value) is not dict or set(value) != {"case", "index", "side", "order", "elapsed_ns", "outcome"}:
        return False
    case_index, within = divmod(ordinal, 30)
    if case_index >= len(CASES):
        return False
    index, side_index = divmod(within, 2)
    first = "old" if (index + case_index) % 2 == 0 else "new"
    side = first if side_index == 0 else ("new" if first == "old" else "old")
    if (value["case"] != CASES[case_index] or type(value["index"]) is not int or value["index"] != index or
            value["side"] != side or value["order"] != first + "-first" or
            value["outcome"] not in ("ok", "invalid", "exception", "interrupted")):
        return False
    elapsed = value["elapsed_ns"]
    if elapsed is not None and (type(elapsed) is not int or not 0 < elapsed < 2**63):
        return False
    if value["outcome"] == "ok" and elapsed is None:
        return False
    return not require_success or value["outcome"] == "ok"


def read_attempts(root, run_id):
    """Reread a complete private sequence without relying on the writer."""
    root = Path(root)
    directory = root / "attempts"
    try:
        if (not private_dir(root) or not private_dir(directory) or type(run_id) is not str or
                not re.fullmatch(r"[0-9a-f]{32}", run_id)):
            return None
        if {p.name for p in directory.iterdir()} != {f"{n:03}.json" for n in range(120)}:
            return None
        attempts = []
        for ordinal in range(120):
            record = strict_json(read_private(directory / f"{ordinal:03}.json", 4096))
            if (type(record) is not dict or set(record) != {"format", "run_id", "ordinal", "attempt"} or
                    type(record["format"]) is not int or record["format"] != 1 or
                    record["run_id"] != run_id or type(record["ordinal"]) is not int or
                    record["ordinal"] != ordinal or
                    not attempt_valid(record["attempt"], ordinal, require_success=True)):
                return None
            attempts.append(record["attempt"])
        return attempts
    except (OSError, ValueError, TypeError, UnicodeError):
        return None


class AttemptSink:
    def __init__(self, root, run_id):
        self.root = Path(root)
        if not private_dir(self.root) or type(run_id) is not str or not re.fullmatch(r"[0-9a-f]{32}", run_id):
            raise ValueError("private run required")
        self.run_id = run_id
        self.directory = self.root / "attempts"
        self.directory.mkdir(mode=0o700)
        if not private_dir(self.directory):
            raise ValueError("private attempt directory required")
        self.ordinal = 0

    def record(self, attempt):
        if not private_dir(self.root) or not private_dir(self.directory) or not attempt_valid(attempt, self.ordinal):
            return False
        record = {"format": 1, "run_id": self.run_id, "ordinal": self.ordinal, "attempt": attempt}
        write_private_json(self.directory / f"{self.ordinal:03}.json", record)
        self.ordinal += 1
        return True

    def verify(self, expected):
        if (type(expected) is not list or len(expected) != 120 or self.ordinal != 120 or
                not all(attempt_valid(row, i, require_success=True) for i, row in enumerate(expected))):
            return False
        return read_attempts(self.root, self.run_id) == expected
