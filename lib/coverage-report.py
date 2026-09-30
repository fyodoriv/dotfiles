"""Aggregate bash xtrace logs into a kcov-compatible coverage.json.

Reads `trace.*.log` files written by `lib/coverage-trap.sh`, extracts
`COV@<source>@<lineno>@...` markers, and produces JSON shaped like kcov's
output so the rest of the pipeline (`.github/scripts/check-shell-coverage.sh`,
`.github/workflows/ci.yml` extraction, README badge) works unchanged.

Total-line counting uses a heuristic: any line that is not blank, not a
shebang, and not a pure comment is "executable". This over-counts compared
to bash's real grammar (e.g., heredoc bodies, `then` keywords) but is stable
and gives a meaningful percentage for the floor regression check. The
ratchet semantics matter more than the absolute number.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

# Match `COV@<file>@<lineno>@...`. Bash's xtrace output occasionally
# concatenates writes from concurrent subshells (e.g., `CCOV@...`); the
# leading `.*?` plus the explicit `COV@` anchor lets us salvage those lines
# instead of dropping them. An empty file slot (`COV@@1@...`) means the
# command came from `bash -c` without a script source — skip those.
COV_RE = re.compile(r"COV@([^@]+)@(\d+)@")


def is_executable_line(line: str) -> bool:
    """Heuristic: is this shell-source line a coverable line?

    Counts as coverable: any non-blank line whose first non-whitespace
    character is not `#`. Excludes the shebang as a special case so
    `#!/usr/bin/env bash` doesn't pad every file's total.
    """
    stripped = line.lstrip()
    if not stripped:
        return False
    if stripped.startswith("#!"):
        return False
    if stripped.startswith("#"):
        return False
    return True


def count_executable_lines(path: Path) -> int:
    try:
        with path.open("r", encoding="utf-8", errors="replace") as fh:
            return sum(1 for line in fh if is_executable_line(line))
    except OSError:
        return 0


def relativize(path: str, repo_root: Path) -> str | None:
    """Convert an absolute or relative trace path to repo-relative form.

    Returns None if the path falls outside the repo root (e.g., bats's own
    libexec scripts), so the include-prefix filter has a stable surface to
    match against.
    """
    p = Path(path)
    if not p.is_absolute():
        # Trace paths from `bin/cheat` are recorded as `bin/cheat` when the
        # script was invoked with a relative path. Resolve against repo
        # root so we can collapse them.
        candidate = (repo_root / p).resolve()
    else:
        candidate = p.resolve()

    try:
        rel = candidate.relative_to(repo_root.resolve())
    except ValueError:
        return None
    return str(rel)


def collect_covered_lines(trace_dir: Path, repo_root: Path) -> dict[str, set[int]]:
    """Walk every `trace.*.log` and return {repo-relative-path: {linenos}}."""
    covered: dict[str, set[int]] = {}
    if not trace_dir.is_dir():
        return covered

    for entry in trace_dir.iterdir():
        if not entry.is_file() or not entry.name.startswith("trace."):
            continue
        try:
            with entry.open("r", encoding="utf-8", errors="replace") as fh:
                for raw_line in fh:
                    match = COV_RE.search(raw_line)
                    if not match:
                        continue
                    src, lineno = match.group(1), int(match.group(2))
                    if not src:
                        # `bash -c` lines — not attributable to a source file.
                        continue
                    rel = relativize(src, repo_root)
                    if rel is None:
                        continue
                    covered.setdefault(rel, set()).add(lineno)
        except OSError:
            continue
    return covered


def filter_includes(rel_path: str, prefixes: list[str]) -> bool:
    return any(rel_path == p or rel_path.startswith(p) for p in prefixes)


def _qualifies_as_shell(entry: Path) -> bool:
    """True if `entry` is a shell-like file (`.sh` extension or bash shebang).

    Chezmoi templates (`*.sh.tmpl`) are intentionally excluded so the
    coverage denominator matches `make lint`'s `$(wildcard
    .chezmoiscripts/*.sh)` glob — neither tool covers the template
    sources, since chezmoi renders them into temp files at apply time and
    the runtime path is the rendered content, not the source.
    """
    if entry.suffix == ".tmpl":
        return False
    if entry.suffix == ".sh":
        return True
    # Extension-less scripts (bin/, git-hooks/): probe shebang.
    try:
        with entry.open("rb") as fh:
            head = fh.read(64)
    except OSError:
        return False
    return head.startswith(b"#!") and b"bash" in head.split(b"\n", 1)[0]


def discover_source_files(repo_root: Path, prefixes: list[str]) -> list[str]:
    """Find every shell-like file under the include prefixes.

    A prefix can be either a directory (recurse and pick up shell-like
    files) or a single file path (the file itself, if it qualifies as
    shell-like). Single-file prefixes let callers cover root-level scripts
    like `macos.sh` without sweeping up sibling `.sh.tmpl` chezmoi
    templates that aren't lint-checked or executed directly.

    A file is "shell-like" if its name matches `*.sh`, it lives under
    `modules/<x>/doctor.sh`, or its first line contains `bash` (catches
    extension-less scripts in `bin/`, `git-hooks/`, etc.). We discover
    files even if they weren't executed so the report's denominator stays
    stable across runs.
    """
    found: list[str] = []
    for prefix in prefixes:
        base = repo_root / prefix
        if base.is_file():
            if _qualifies_as_shell(base):
                found.append(base.relative_to(repo_root).as_posix())
            continue
        if not base.is_dir():
            continue
        for entry in sorted(base.rglob("*")):
            if not entry.is_file():
                continue
            if _qualifies_as_shell(entry):
                found.append(entry.relative_to(repo_root).as_posix())
    return sorted(set(found))


def build_report(
    trace_dir: Path,
    repo_root: Path,
    include_prefixes: list[str],
) -> dict:
    covered = collect_covered_lines(trace_dir, repo_root)
    sources = discover_source_files(repo_root, include_prefixes)

    files: list[dict] = []
    grand_covered = 0
    grand_total = 0
    for rel in sources:
        if not filter_includes(rel, include_prefixes):
            continue
        path = repo_root / rel
        total = count_executable_lines(path)
        if total == 0:
            continue
        hit_set = covered.get(rel, set())
        # Only count covered hits that are within the file's actual line
        # range — bats can record a lineno of 1000 in a sourced trap that
        # doesn't exist in the source (e.g., concatenation issues).
        try:
            with path.open("r", encoding="utf-8", errors="replace") as fh:
                file_lines = fh.readlines()
            hit = sum(
                1 for ln in hit_set if 1 <= ln <= len(file_lines) and is_executable_line(file_lines[ln - 1])
            )
        except OSError:
            hit = 0
        pct = (hit / total * 100.0) if total else 0.0
        files.append(
            {
                "file": rel,
                "percent_covered": f"{pct:.2f}",
                "covered_lines": str(hit),
                "total_lines": str(total),
            }
        )
        grand_covered += hit
        grand_total += total

    grand_pct = (grand_covered / grand_total * 100.0) if grand_total else 0.0

    return {
        "files": files,
        "percent_covered": f"{grand_pct:.2f}",
        "covered_lines": grand_covered,
        "total_lines": grand_total,
        "percent_low": 25,
        "percent_high": 75,
        "command": "dotfiles-coverage",
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trace-dir", required=True, type=Path)
    parser.add_argument("--repo-root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--include", nargs="+", required=True)
    args = parser.parse_args(argv)

    report = build_report(args.trace_dir, args.repo_root, args.include)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)
        fh.write("\n")

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
