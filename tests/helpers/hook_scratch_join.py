"""Scratch-only correlation of a selection receipt and helper snapshots."""
import base64
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).parent))
import hook_effective_helper as effective


def main():
    action, root_arg, expected_arg, state_arg, receipt_arg = sys.argv[1:]
    root = Path(root_arg)
    state = Path(state_arg)
    if action == "before":
        info = root.stat()
        identity = (info.st_dev, info.st_ino)
        expected = Path(expected_arg).read_bytes()
        before = effective.snapshot(root, identity, {"DOTFILES_DIR": str(root)}, expected)
        if before is None:
            raise ValueError("invalid initial fixture")
        state.write_text(json.dumps({
            "identity": identity,
            "expected": base64.b64encode(expected).decode("ascii"),
            "before": before,
        }))
        return
    if action != "after":
        raise ValueError("unknown action")
    data = json.loads(state.read_text())
    identity = tuple(data["identity"])
    expected = base64.b64decode(data["expected"], validate=True)
    after = effective.snapshot(root, identity, {"DOTFILES_DIR": str(root)}, expected)
    receipt = Path(receipt_arg).read_bytes()
    print("accepted" if receipt == b"configured\n" and after is not None and
          json.loads(json.dumps(after)) == data["before"] else "inconclusive")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, TypeError, KeyError, UnicodeError):
        print("inconclusive")
        if len(sys.argv) < 2 or sys.argv[1] == "before":
            sys.exit(1)
