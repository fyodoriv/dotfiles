"""Compare affected-test selector outputs and timing in an owned scratch repo."""
import json
import os
from pathlib import Path
import shutil
import statistics
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def run(args, cwd, **kwargs):
    return subprocess.run(args, cwd=cwd, check=True, **kwargs)


def main():
    base = os.environ["SELECTOR_BASE_SHA"]
    if len(base) != 40 or any(c not in "0123456789abcdef" for c in base):
        raise ValueError("expected full base commit")
    old = subprocess.check_output(["git", "show", f"{base}:bin/bats-affected"], cwd=ROOT)
    paths = sorted((ROOT / "rust/vendor").rglob("*.rs"))[:20]
    if len(paths) != 20:
        raise ValueError("expected 20 vendored source paths")
    with tempfile.TemporaryDirectory(prefix="bats-selection-") as temporary:
        repo = Path(temporary)
        (repo / "bin").mkdir()
        (repo / "tests").mkdir()
        for test in (ROOT / "tests").glob("*.bats"):
            shutil.copy2(test, repo / "tests" / test.name)
        nested = paths[0].relative_to(ROOT / "rust/vendor/libc")
        (repo / "tests/reads-vendor.bats").write_text(
            'REPO_ROOT="$BATS_TEST_DIRNAME/.."\n'
            'VENDOR="$REPO_ROOT/rust/vendor/libc"\n'
            f'@test "vendor" {{ cat "$VENDOR/{nested}"; }}\n'
        )
        shutil.copy2(ROOT / "tests/verify-counts-doc-paths.sh", repo / "tests")
        (repo / "bin/old-selector").write_bytes(old)
        shutil.copy2(ROOT / "bin/bats-affected", repo / "bin/new-selector")
        run(["git", "init", "-q"], repo)
        run(["git", "config", "user.name", "Fixture"], repo)
        run(["git", "config", "user.email", "fixture@example.com"], repo)
        run(["git", "add", "bin", "tests"], repo)
        run(["git", "-c", "core.hooksPath=/dev/null", "commit", "-qm", "fixture"], repo)
        for source in paths:
            destination = repo / source.relative_to(ROOT)
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text("fixture\n")
        run(["git", "add", "rust"], repo)
        times = {"old": [], "new": []}
        for mode in ([], ["--pairs"]):
            reference = None
            for pair in range(3):
                for name in (("old", "new") if pair % 2 == 0 else ("new", "old")):
                    start = time.monotonic()
                    result = subprocess.check_output(["bash", f"bin/{name}-selector", *mode, "HEAD"], cwd=repo)
                    times[name].append(time.monotonic() - start)
                    if b"reads-vendor.bats" not in result:
                        raise SystemExit("planted derived-root dependency was missed")
                    if reference is None:
                        reference = result
                    elif result != reference:
                        raise SystemExit("selector outputs differ")
        before = statistics.median(times["old"])
        after = statistics.median(times["new"])
        print(json.dumps({"vendor_paths": 20, "samples_per_selector": 6,
                          "old_median_seconds": before, "new_median_seconds": after,
                          "ratio": after / before}))
        if after > 30 or after / before > 0.5:
            raise SystemExit("selection speed threshold missed")


if __name__ == "__main__":
    main()
