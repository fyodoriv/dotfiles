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
PREFILTER_BASE = "1a96d12a8bf0b42df0fba340bf933d4c79ecd2d2"


def run(args, cwd, **kwargs):
    return subprocess.run(args, cwd=cwd, check=True, **kwargs)


def main():
    base = os.environ["SELECTOR_BASE_SHA"]
    if len(base) != 40 or any(c not in "0123456789abcdef" for c in base):
        raise ValueError("expected full base commit")
    base_selector = subprocess.check_output(["git", "show", f"{base}:bin/bats-affected"], cwd=ROOT)
    old = subprocess.check_output(["git", "show", f"{PREFILTER_BASE}:bin/bats-affected"], cwd=ROOT)
    vendor = ROOT / "rust/vendor"
    derived_root = vendor / "libc"
    planted = next(iter(sorted(derived_root.rglob("*.rs"))), None)
    if planted is None:
        raise ValueError("expected a vendored source under the derived root")
    paths = [planted, *[path for path in sorted(vendor.rglob("*.rs")) if path != planted][:19]]
    if len(paths) != 20:
        raise ValueError("expected 20 vendored source paths")
    with tempfile.TemporaryDirectory(prefix="bats-selection-") as temporary:
        repo = Path(temporary)
        (repo / "bin").mkdir()
        (repo / "tests").mkdir()
        for test in (ROOT / "tests").glob("*.bats"):
            shutil.copy2(test, repo / "tests" / test.name)
        nested = planted.relative_to(derived_root)
        (repo / "tests/reads-vendor.bats").write_text(
            'REPO_ROOT="$BATS_TEST_DIRNAME/.."\n'
            'VENDOR="$REPO_ROOT/rust/vendor/libc"\n'
            f'@test "vendor" {{ cat "$VENDOR/{nested}"; }}\n'
        )
        shutil.copy2(ROOT / "tests/verify-counts-doc-paths.sh", repo / "tests")
        (repo / "bin/base-selector").write_bytes(base_selector)
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
            reference = subprocess.check_output(["bash", "bin/base-selector", *mode, "HEAD"], cwd=repo)
            if b"reads-vendor.bats" not in reference:
                raise SystemExit("base selector missed the planted derived-root dependency")
            for pair in range(3):
                for name in (("old", "new") if pair % 2 == 0 else ("new", "old")):
                    start = time.monotonic()
                    result = subprocess.check_output(["bash", f"bin/{name}-selector", *mode, "HEAD"], cwd=repo)
                    times[name].append(time.monotonic() - start)
                    if b"reads-vendor.bats" not in result:
                        raise SystemExit("planted derived-root dependency was missed")
                    if result != reference:
                        raise SystemExit(f"{name} selector output differs from the PR base")
        before = statistics.median(times["old"])
        after = statistics.median(times["new"])
        print(json.dumps({"vendor_paths": 20, "samples_per_selector": 6,
                          "timing_base": PREFILTER_BASE, "parity_base": base,
                          "old_median_seconds": before, "new_median_seconds": after,
                          "ratio": after / before}))
        if after > 30 or after / before > 0.5:
            raise SystemExit("selection speed threshold missed")


if __name__ == "__main__":
    main()
