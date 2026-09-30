"""Pick the highest-priority unblocked task from TASKS.md and run it
through bin/local-ai-agent. Loop until the queue is empty or the
deadline is reached.

This is intentionally narrower than minsky:
  - Designed for the local-ai-agent backend only (Ollama / qwen3-coder).
  - Reads TASKS.md per the tasks.md spec used in this repo (P0/P1/P2/P3
    sections, `- [ ] ` checkboxes with indented **ID** / **Tags** /
    **Details** / **Files** / **Acceptance** metadata).
  - Skips tasks tagged with `secrets`, `machine`, `manual`, or
    `interactive` since local-AI can't supply those.
  - After each successful run, the agent is expected to remove the
    task block from TASKS.md (per the policy in this repo's AGENTS.md).
    The loop verifies the block disappeared; if not, it skips the task
    on the next pass to avoid infinite re-runs.

Usage:
  python3 lib/local-ai-loop.py [--deadline 8h | --max-tasks 10]
    [--dry-run]   plan-only; print which tasks would run, no agent invoked
    [--cwd DIR]   defaults to the repo root
    [--model M]   forwarded to local-ai-agent (default qwen3-coder:30b)

Exit codes:
  0  loop completed (deadline reached or queue exhausted)
  1  fatal error (TASKS.md missing, bin/local-ai-agent missing, etc.)
  2  the agent exited non-zero on a task; loop continues for remaining
     tasks but the final exit code is non-zero
"""
import argparse
import os
import re
import subprocess
import sys
import time


TASK_HEADER = re.compile(r"^- \[ \]\s+(?P<title>.+)$")
TASK_META = re.compile(r"^\s+-\s+\*\*(?P<key>[A-Za-z]+)\*\*:\s*(?P<val>.+)$")
SECTION = re.compile(r"^##\s+(?P<name>P[0-3])\s*$")

# Tags that exclude a task from local-AI auto-runs. These need human
# secrets, interactive browser flows, or knowledge the model can't have.
EXCLUDE_TAGS = {"secrets", "machine", "manual", "interactive", "auth"}


def parse_duration(s: str) -> int:
    """Parse `8h`, `30m`, `45s`, `3600` into seconds."""
    s = s.strip()
    if not s:
        raise ValueError("empty duration")
    if s.isdigit():
        return int(s)
    unit = s[-1].lower()
    n = int(s[:-1])
    return {"s": n, "m": n * 60, "h": n * 3600, "d": n * 86400}[unit]


def read_tasks(path: str):
    """Parse TASKS.md into a list of task dicts in queue order.

    Yields tasks from P0 → P1 → P2 → P3, each with keys: priority,
    title, id, tags (set), details, files, acceptance, start_line, end_line.
    Skips comment-only / metadata-only sections.
    """
    if not os.path.exists(path):
        return []
    with open(path) as f:
        lines = f.readlines()

    tasks = []
    priority = None
    i = 0
    while i < len(lines):
        sec = SECTION.match(lines[i])
        if sec:
            priority = sec["name"]
            i += 1
            continue
        m = TASK_HEADER.match(lines[i])
        if m and priority:
            start = i
            title = m["title"].strip()
            meta = {"id": "", "tags": set(), "details": "", "files": "", "acceptance": ""}
            i += 1
            while i < len(lines):
                # task body continues until next `- [ ]` or `##` or blank-line-then-blank
                if TASK_HEADER.match(lines[i]) or SECTION.match(lines[i]):
                    break
                mm = TASK_META.match(lines[i])
                if mm:
                    key = mm["key"].lower()
                    val = mm["val"].strip()
                    # Concatenate continuation lines — any subsequent
                    # line that's indented MORE than the `- **Key**:`
                    # bullet and is NOT itself a new meta bullet belongs
                    # to this field. Task descriptions in TASKS.md span
                    # many lines; a single-line parser drops the
                    # crucial sentence (observed in P0 attempts 1-8,
                    # where "3 `@test` cases" lived on line 3 of the
                    # Details field and the critic never saw it).
                    j = i + 1
                    while j < len(lines):
                        next_line = lines[j]
                        stripped = next_line.lstrip()
                        if not stripped:  # blank line ends the field
                            break
                        if TASK_HEADER.match(next_line) or SECTION.match(next_line):
                            break
                        if TASK_META.match(next_line):
                            break
                        # Require continuation lines to be indented MORE
                        # than the meta line (typical pattern is 4-space
                        # continuation under a 2-space bullet).
                        leading = len(next_line) - len(stripped)
                        if leading < 4:
                            break
                        val = val + " " + stripped.strip()
                        j += 1
                    if key == "tags":
                        meta["tags"] = {t.strip() for t in val.split(",")}
                    elif key in meta:
                        meta[key] = val
                    i = j
                    continue
                i += 1
            end = i
            if meta["id"]:
                tasks.append({
                    "priority": priority,
                    "title": title,
                    **meta,
                    "start_line": start,
                    "end_line": end,
                })
            continue
        i += 1
    return tasks


def read_queue_dir(queue_dir: str):
    """Parse a tasks-queue/ directory of one-task-per-file specs.

    Overnight-grind queue mode: each `*.md` file holds one task block in
    the repo's TASKS.md format (a `## P*` section header is optional —
    headerless specs parse via a `## P0` prefix fallback, since queue
    files are operator-curated P0 work by definition). Files are read in
    lexical filename order; each parsed task carries `_queue_file` (the
    spec's absolute path) so the close path can consume the file. A
    missing or empty directory yields [] — not an error.
    """
    if not queue_dir or not os.path.isdir(queue_dir):
        return []
    tasks = []
    for name in sorted(os.listdir(queue_dir)):
        if not name.endswith(".md"):
            continue
        path = os.path.abspath(os.path.join(queue_dir, name))
        parsed = read_tasks(path)
        if not parsed:
            # Headerless spec: re-parse with an injected P0 section.
            try:
                with open(path) as f:
                    content = f.read()
            except OSError:
                continue
            import tempfile
            with tempfile.NamedTemporaryFile(
                "w", suffix=".md", delete=False
            ) as tf:
                tf.write("## P0\n\n" + content)
                tmp_path = tf.name
            try:
                parsed = read_tasks(tmp_path)
            finally:
                os.unlink(tmp_path)
        for t in parsed:
            t["_queue_file"] = path
            tasks.append(t)
    return tasks


def close_queue_task(task) -> None:
    """Consume a successfully closed queue task's spec file.

    The queue-dir analogue of removing a TASKS.md block. Callers invoke
    this ONLY after the full close gates (make check + pre-merge
    reviewer) pass — failures leave the spec in place for the next run.
    """
    path = task.get("_queue_file")
    if not path:
        return
    try:
        os.remove(path)
        print(f"loop: consumed queue spec {path}", flush=True)
    except OSError as e:
        print(f"loop: ⚠ couldn't remove queue spec {path}: {e}", flush=True)


RUNS_CSV_RELPATH = os.path.join("docs", "audits", "local-ai-loop-runs.csv")
RUNS_CSV_HEADER = ["timestamp_utc", "task_id", "source", "outcome",
                   "wall_seconds", "turn_budget"]


def record_run_row(repo: str, task, outcome: str, wall_seconds: float,
                   turns: int) -> None:
    """Append one per-task outcome row to the loop's run ledger.

    Loop-owned CSV at docs/audits/local-ai-loop-runs.csv — separate from
    the agent's 14-column telemetry file (local-ai-runs.csv); the two
    schemas are incompatible, so each writer owns its own file. Both are
    protected by PERSIST_PATHS (never auto-committed, never reverted).
    Never raises: losing a ledger row must not fail an overnight run.
    """
    import csv
    from datetime import datetime, timezone
    path = os.path.join(repo, RUNS_CSV_RELPATH)
    source = "queue" if "_queue_file" in task else "tasks-md"
    row = [
        datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        task.get("id", ""),
        source,
        outcome,
        str(round(wall_seconds)),
        str(turns),
    ]
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        write_header = not os.path.exists(path) or os.path.getsize(path) == 0
        with open(path, "a", newline="") as f:
            w = csv.writer(f, lineterminator="\n")
            if write_header:
                w.writerow(RUNS_CSV_HEADER)
            w.writerow(row)
    except OSError as e:
        print(f"loop: ⚠ couldn't append run row to {path}: {e}", flush=True)


def pickable(task) -> bool:
    """Whether this task is safe for the local-AI loop to attempt."""
    if not task["id"]:
        return False
    if task["tags"] & EXCLUDE_TAGS:
        return False
    return True


def build_prompt(task, cwd: str | None = None) -> str:
    """Compose a focused agent prompt from a parsed task.

    Pre-loads the contents of files named in the task's `**Files**:`
    metadata (if any) — surfaced in run-5 that the agent spent turns
    1-5 on `ls` / `cat` to discover files it had already been told
    about. With the preload, the agent starts with the full file
    contents in its context and can jump straight to editing.
    """
    parts = [
        f"Task ID: {task['id']} (priority {task['priority']})",
        f"Title: {task['title']}",
    ]
    if task["details"]:
        parts.append(f"Details: {task['details']}")
    if task["files"]:
        parts.append(f"Files to touch: {task['files']}")
    if task["acceptance"]:
        parts.append(f"Acceptance: {task['acceptance']}")

    # Preload file contents. Split the Files: metadata on commas, strip
    # whitespace, try to read each path relative to cwd. Cap the
    # total preload at ~32KB so we don't blow the context window.
    preloaded = _preload_files(task.get("files", ""), cwd)
    if preloaded:
        parts.append("Pre-loaded file contents (so you don't have to `cat` these):")
        parts.append(preloaded)

    parts.append(
        "When the task is complete:\n"
        "  1. Run `make check` and ensure it passes.\n"
        "  2. Stage the changed files (`git add <files>`); DO NOT commit "
        "or push — the loop driver handles that.\n"
        "  3. Call the `done` tool with a one-line summary.\n"
        "The loop driver will remove this task block from TASKS.md "
        "automatically after `make check` passes; you don't need to "
        "touch TASKS.md yourself.\n"
        "If you cannot complete the task in your turn budget, call `done` "
        "with a summary that begins with 'BLOCKED:' and a one-sentence reason."
    )
    return "\n\n".join(parts)


def _files_field_paths(files_field: str) -> list[str]:
    """Extract path-like tokens from a `Files:` metadata field.

    Shared by the prompt preloader and the pre-merge reviewer. Splits on
    commas, then keeps tokens that look like paths: containing a `/`, a
    glob char, or a `.ext`-style suffix. Prose words ("new", "optional")
    and annotations around the path are dropped. Order-preserving, deduped.
    Bare extension-less names without a slash (e.g. "Makefile") are NOT
    captured here — the reviewer prefers a false-pass over a false-fail
    for those (see the task's Pivot), and the preloader adds raw
    comma-chunks itself.
    """
    if not files_field:
        return []
    out: list[str] = []
    for chunk in files_field.split(","):
        for tok in re.findall(r"[A-Za-z0-9_.\-*/]+", chunk):
            if tok in out:
                continue
            if "/" in tok or "*" in tok or re.search(r"\.[A-Za-z0-9]+$", tok):
                out.append(tok)
    return out


def _preload_files(files_field: str, cwd: str | None) -> str:
    """Extract file paths from the `Files:` metadata and read them.

    Returns a concatenated "===== path =====\\ncontents\\n" block,
    capped at ~32KB total. Skips files that don't exist or are too
    large (over 8KB each — those can be read via `bash cat` on demand).
    """
    if not files_field or cwd is None:
        return ""
    # Split on commas. Each element may be "path/to/file.ext" with
    # surrounding whitespace.
    candidates = [p.strip() for p in files_field.split(",")]
    # Also pick up path-like tokens from the raw Files: string —
    # sometimes the metadata is unstructured prose.
    for tok in _files_field_paths(files_field):
        if tok not in candidates:
            candidates.append(tok)
    preloaded_parts: list[str] = []
    budget = 32 * 1024  # 32KB total
    per_file_cap = 8 * 1024
    for path in candidates:
        if not path or path.startswith("http"):
            continue
        abs_path = path if os.path.isabs(path) else os.path.join(cwd, path)
        try:
            if not os.path.isfile(abs_path):
                continue
            size = os.path.getsize(abs_path)
            if size > per_file_cap:
                preloaded_parts.append(
                    f"===== {path} ({size} bytes, truncated to {per_file_cap}) =====\n"
                )
                with open(abs_path, encoding="utf-8", errors="replace") as f:
                    preloaded_parts.append(f.read(per_file_cap))
                preloaded_parts.append("\n[... truncated — use `bash` to read more]\n")
            else:
                preloaded_parts.append(f"===== {path} ({size} bytes) =====\n")
                with open(abs_path, encoding="utf-8", errors="replace") as f:
                    preloaded_parts.append(f.read())
                preloaded_parts.append("\n")
            if sum(len(p) for p in preloaded_parts) > budget:
                preloaded_parts.append(
                    "\n[... preload budget exceeded — use `bash` for remaining files]\n"
                )
                break
        except Exception:
            continue
    return "".join(preloaded_parts)


def remove_task_block(tasks_md: str, task_id: str) -> bool:
    """Remove the task block whose `**ID**: <task_id>` line we find.

    Mirrors the same trimming behaviour we used by hand in earlier PRs:
    drop the `- [ ]` header line, all the indented metadata, and any
    blank line directly after the block. Returns True if the block was
    found + removed, False if no matching id was present.
    """
    with open(tasks_md) as f:
        lines = f.readlines()
    out = []
    i = 0
    removed = False
    while i < len(lines):
        if (
            i + 1 < len(lines)
            and lines[i].lstrip().startswith("- [ ]")
            and f"**ID**: {task_id}" in lines[i + 1]
        ):
            # Drop trailing blank lines from the previous block so we
            # don't end up with double-blanks.
            while out and out[-1].strip() == "":
                out.pop()
            out.append("\n")
            # Skip the task block itself: from this line until the next
            # `- [ ]` or `## ` or EOF, then skip any leading blank lines
            # of the next block.
            i += 1
            while i < len(lines) and not lines[i].startswith("- [ ]") and not lines[i].startswith("##"):
                i += 1
            removed = True
            continue
        out.append(lines[i])
        i += 1
    # Collapse trailing blanks.
    while len(out) >= 2 and out[-1] == "\n" and out[-2] == "\n":
        out.pop()
    if removed:
        with open(tasks_md, "w") as f:
            f.writelines(out)
    return removed


def make_check_passes(cwd: str) -> bool:
    """Run `make check` and report whether it passed."""
    r = subprocess.run(
        ["make", "check"],
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=300,
    )
    return r.returncode == 0


def revert_uncommitted(cwd: str, task_id: str) -> None:
    """Revert tracked changes + delete untracked files from a failed task.

    Surfaced in run-3 dogfood: task 1 wrote a broken bats test, exited
    rc=1, leaving the broken test in the repo. Task 2 then ran `make
    check` and failed not because of its own work but because of task 1's
    leftover garbage. Without this cleanup the loop's failure modes
    compound across tasks.

    Safe alternatives (per CLAUDE.md's git safety rules) — we DON'T use
    `git checkout .`, `git reset --hard`, or `git clean -fd` because
    other concurrent agents may have legitimate uncommitted work in the
    same checkout. Instead we use the porcelain output to identify
    just the files changed during this task's run and revert those.
    """
    # Snapshot HEAD state at task start would be ideal; for now we just
    # revert any modified + delete any untracked files in tests/ and
    # the agent's typical write paths. This is heuristic — the loop
    # doesn't track the agent's exact writes (yet).
    print(f"loop: reverting uncommitted changes from failed task {task_id}", flush=True)
    # Modified tracked files: restore to HEAD.
    r = subprocess.run(
        ["git", "diff", "--name-only"],
        cwd=cwd, capture_output=True, text=True,
    )
    for fn in (r.stdout or "").splitlines():
        if fn.strip():
            subprocess.run(
                ["git", "checkout", "HEAD", "--", fn.strip()],
                cwd=cwd, check=False,
            )
    # Untracked: delete only the ones in tests/, lib/, bin/, docs/, modules/
    # — never anywhere else (don't risk touching the user's scratch
    # files or other agents' uncommitted exploration).
    r = subprocess.run(
        ["git", "ls-files", "--others", "--exclude-standard"],
        cwd=cwd, capture_output=True, text=True,
    )
    SAFE_PREFIXES = ("tests/", "lib/", "bin/", "docs/", "modules/",
                     "agent-hooks/", ".chezmoiscripts/")
    # Telemetry / log files that accumulate across runs — DO NOT
    # delete these on revert. The CSV from bin/local-ai-agent
    # --telemetry sits in docs/audits/ and would be wiped here
    # otherwise (observed in run-4: the CSV got created during task 2
    # and then deleted when revert_uncommitted fired on task 3's
    # failure).
    PERSIST_PATHS = ("docs/audits/local-ai-runs.csv",
                     "docs/audits/local-ai-loop-runs.csv")
    for fn in (r.stdout or "").splitlines():
        fn = fn.strip()
        if not fn:
            continue
        if fn in PERSIST_PATHS:
            continue
        if any(fn.startswith(p) for p in SAFE_PREFIXES):
            try:
                os.remove(os.path.join(cwd, fn))
            except OSError:
                pass


def estimate_max_turns(task) -> int:
    """Turn budget based on task complexity.

    Simple tasks (single file, short details, narrow acceptance) do
    fine in 14 turns. Complex tasks (multiple files, long details,
    multi-part acceptance) often need more — observed in run-5 that
    cover-devin-three-layer needed 14 turns JUST to satisfy the
    critic, with 0 turns left for make check.

    Heuristic — base is 14, add:
      +4 if `Details:` is longer than 400 chars
      +4 if `Files:` names 3 or more entries (commas)
      +4 if `Acceptance:` is longer than 200 chars
    Capped at 28.
    """
    base = 14
    bonus = 0
    details = task.get("details", "") or ""
    files = task.get("files", "") or ""
    accept = task.get("acceptance", "") or ""
    if len(details) > 400:
        bonus += 4
    if files.count(",") >= 2:
        bonus += 4
    if len(accept) > 200:
        bonus += 4
    return min(base + bonus, 28)


def run_agent(prompt: str, agent_bin: str, cwd: str, model: str,
              max_turns: int = 14) -> int:
    """Invoke bin/local-ai-agent with the task prompt; return exit code."""
    cmd = [agent_bin, "--model", model, "--max-turns", str(max_turns), prompt]
    try:
        r = subprocess.run(cmd, cwd=cwd, timeout=1500)
        return r.returncode
    except subprocess.TimeoutExpired:
        return 124


def commit_if_dirty(cwd: str, task_id: str) -> bool:
    """If the agent left work behind, stage it and commit with a fixed message.

    Surfaced after the 3 P0 reliability runs (PRs #24-#26): the agent
    is instructed to `git add` its changes, but qwen3-coder:30b doesn't
    follow that instruction reliably — observed in all 3 runs that the
    write_file output (the actual deliverable) stayed untracked while
    the loop's commit_if_dirty saw only the TASKS.md edit and committed
    just that. The squash-merged PR descriptions claimed the test files
    shipped; they didn't. Discovered when reviewing main after merging.

    Fix: the loop now stages ANY tracked-modified OR untracked file in
    safe prefixes (the same set used by revert_uncommitted), then
    commits if the index is non-empty. The agent's instruction to
    `git add` is still useful for explicit control but no longer
    load-bearing.
    """
    # Stage tracked-modified files (git add -u limited to safe prefixes).
    SAFE_PREFIXES = ("tests/", "lib/", "bin/", "docs/", "modules/",
                     "agent-hooks/", ".chezmoiscripts/", "home/",
                     "launchagents/", "Makefile", "TASKS.md", "AGENTS.md")
    # Tracked modified
    r = subprocess.run(
        ["git", "diff", "--name-only"],
        cwd=cwd, capture_output=True, text=True,
    )
    for fn in (r.stdout or "").splitlines():
        fn = fn.strip()
        if not fn:
            continue
        if any(fn.startswith(p) or fn == p for p in SAFE_PREFIXES):
            subprocess.run(["git", "add", "--", fn], cwd=cwd, check=False)
    # Untracked in safe prefixes
    r = subprocess.run(
        ["git", "ls-files", "--others", "--exclude-standard"],
        cwd=cwd, capture_output=True, text=True,
    )
    for fn in (r.stdout or "").splitlines():
        fn = fn.strip()
        if not fn:
            continue
        # Persist files are never committed by the loop (they're per-run
        # state, gitignored by convention; we just don't auto-add them).
        if fn in ("docs/audits/local-ai-runs.csv",
                  "docs/audits/local-ai-loop-runs.csv"):
            continue
        if any(fn.startswith(p) or fn == p for p in SAFE_PREFIXES):
            subprocess.run(["git", "add", "--", fn], cwd=cwd, check=False)
    # Now commit if anything is staged.
    diff = subprocess.run(["git", "diff", "--cached", "--quiet"], cwd=cwd)
    if diff.returncode == 0:
        return False  # nothing staged
    subprocess.run(
        ["git", "commit", "-m", f"chore(local-ai-loop): {task_id}"],
        cwd=cwd,
        check=False,
    )
    return True


def _reviewer_entry_satisfied(entry: str, changed: list[str]) -> bool:
    """One declared `Files:` entry vs the commit's path list.

    - glob entries match fnmatch-style WITHOUT crossing `/` (PurePosixPath
      .match: `tests/*.bats` matches `tests/new.bats`, not
      `tests/subdir/foo.bats`);
    - directory entries match one-way: declared `tests/` (or `tests`) is
      satisfied by any committed path under it, while a declared file is
      never satisfied by a sibling;
    - otherwise exact match.
    """
    if any(ch in entry for ch in "*?["):
        from pathlib import PurePosixPath
        return any(PurePosixPath(p).match(entry) for p in changed)
    prefix = entry if entry.endswith("/") else entry + "/"
    return any(p == entry or p.startswith(prefix) for p in changed)


def reviewer_missing_files(cwd: str, task, committed: bool) -> list[str]:
    """Pre-merge reviewer: declared `Files:` entries absent from the close.

    Surfaced in PRs #24-#26: the loop closed tasks whose commit didn't
    contain the declared deliverable, so PR descriptions claimed files
    shipped that never existed on main. This compares the close commit's
    paths (`git show --name-only --format= HEAD` — NOT `--stat`, which
    truncates long paths) against the task's `**Files**:` field and
    returns the unmatched entries. An empty declared set passes (tasks
    without path-like Files aren't gated). A declared `TASKS.md` is
    auto-satisfied — the loop always edits it. When nothing was
    committed, every declared entry is missing by definition.
    """
    declared = [
        d for d in _files_field_paths((task.get("files") or ""))
        if d != "TASKS.md"
    ]
    if not declared:
        return []
    changed: list[str] = []
    if committed:
        r = subprocess.run(
            ["git", "show", "--name-only", "--format=", "HEAD"],
            cwd=cwd, capture_output=True, text=True,
        )
        changed = [ln.strip() for ln in (r.stdout or "").splitlines() if ln.strip()]
    return [e for e in declared if not _reviewer_entry_satisfied(e, changed)]


def reviewer_reject_close(cwd: str, task_id: str, committed: bool) -> None:
    """Roll back a close the reviewer refused.

    When the close was committed, rewind ONLY that just-created,
    never-pushed commit (`reset --soft` — worktree untouched), then
    unstage so `revert_uncommitted` sees the changes as plain
    modifications. Multi-agent-safe by construction: no `reset --hard`,
    no `checkout .`, no `clean -fd`; file-level cleanup goes through the
    same prefix-scoped `revert_uncommitted` used by every other failure
    branch (which also restores the TASKS.md block via checkout from the
    rewound HEAD).
    """
    print(
        f"loop: reviewer rejecting close of {task_id} (committed={committed})",
        flush=True,
    )
    if committed:
        subprocess.run(["git", "reset", "--soft", "HEAD~1"], cwd=cwd, check=False)
        subprocess.run(["git", "restore", "--staged", "--", "."], cwd=cwd, check=False)
    else:
        # main() stages TASKS.md before commit_if_dirty; if nothing got
        # committed that staged edit may still be sitting in the index.
        subprocess.run(
            ["git", "restore", "--staged", "--", "TASKS.md"], cwd=cwd, check=False,
        )
    revert_uncommitted(cwd, task_id)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--deadline", default="8h", help="e.g. 8h, 30m, 3600")
    ap.add_argument("--max-tasks", type=int, default=20)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--cwd", default=os.getcwd())
    ap.add_argument("--model", default="qwen3-coder:30b")
    ap.add_argument("--queue", default="",
                    help="directory of one-task-per-file specs — overrides "
                         "TASKS.md as the task source (overnight grind mode)")
    args = ap.parse_args()

    repo = os.path.abspath(args.cwd)
    tasks_md = os.path.join(repo, "TASKS.md")
    agent_bin = os.path.join(repo, "bin", "local-ai-agent")
    queue_dir = os.path.abspath(args.queue) if args.queue else ""

    if queue_dir:
        if not os.path.isdir(queue_dir):
            print(f"FATAL: --queue {queue_dir} is not a directory", file=sys.stderr)
            return 1
    elif not os.path.exists(tasks_md):
        print(f"FATAL: {tasks_md} not found", file=sys.stderr)
        return 1
    if not args.dry_run and not os.access(agent_bin, os.X_OK):
        print(f"FATAL: {agent_bin} not executable", file=sys.stderr)
        return 1

    try:
        deadline = parse_duration(args.deadline)
    except Exception as e:
        print(f"FATAL: bad --deadline {args.deadline}: {e}", file=sys.stderr)
        return 1

    started = time.time()
    fail = 0
    completed = 0
    skipped_ids: set[str] = set()
    seen_ids: set[str] = set()

    while completed + fail < args.max_tasks:
        elapsed = time.time() - started
        remaining = deadline - elapsed
        if remaining <= 0:
            print(f"\nloop: deadline reached ({args.deadline}); stopping.")
            break

        tasks = read_queue_dir(queue_dir) if queue_dir else read_tasks(tasks_md)
        candidates = [t for t in tasks if pickable(t) and t["id"] not in skipped_ids]
        if not candidates:
            source = queue_dir if queue_dir else "TASKS.md"
            print(f"loop: no pickable tasks in {source}; stopping.")
            break

        task = candidates[0]
        print()
        print("─" * 60)
        print(f"loop: picked {task['priority']} {task['id']} "
              f"(elapsed {elapsed/60:.1f}m / {deadline/60:.1f}m)")
        print(f"      title: {task['title']}")

        if args.dry_run:
            print("loop: --dry-run; not invoking the agent.")
            seen_ids.add(task["id"])
            skipped_ids.add(task["id"])  # don't loop
            continue

        prompt = build_prompt(task, cwd=repo)
        max_turns = estimate_max_turns(task)
        print(f"loop:   budget={max_turns} turns "
              f"(base 14 + {max_turns - 14} bonus from complexity signals)",
              flush=True)
        task_started = time.time()
        rc = run_agent(prompt, agent_bin, repo, args.model, max_turns=max_turns)

        if rc != 0:
            print(f"loop: ✗ agent rc={rc}; skipping {task['id']} "
                  "for the rest of this run.")
            revert_uncommitted(repo, task["id"])
            record_run_row(repo, task, "agent-failed",
                           time.time() - task_started, max_turns)
            skipped_ids.add(task["id"])
            fail += 1
            seen_ids.add(task["id"])
            continue

        # Agent says it's done. Gate the close on `make check` so we
        # don't commit broken work.
        if not make_check_passes(repo):
            print(f"loop: ✗ agent rc=0 but `make check` fails; skipping "
                  f"{task['id']} for the rest of this run.")
            revert_uncommitted(repo, task["id"])
            record_run_row(repo, task, "check-failed",
                           time.time() - task_started, max_turns)
            skipped_ids.add(task["id"])
            fail += 1
            seen_ids.add(task["id"])
            continue

        # Loop owns the task-source consumption — the agent doesn't have
        # to remember (and historically the agent forgot in 50% of runs).
        # Queue mode: the spec file is run-state, not repo content, so
        # there's no TASKS.md edit to make or stage; the spec is consumed
        # AFTER every close gate (incl. the reviewer) passes, below.
        removed = False
        if "_queue_file" not in task:
            removed = remove_task_block(tasks_md, task["id"])
            if not removed:
                print(f"loop: ⚠ couldn't find {task['id']} in TASKS.md to "
                      "remove — agent may have already done it.")
            # Stage the TASKS.md edit (if any) alongside whatever the agent
            # staged.
            subprocess.run(["git", "add", "TASKS.md"], cwd=repo, check=False)
        committed = commit_if_dirty(repo, task["id"])

        # Pre-merge reviewer: the close commit must contain every path
        # the task declared in `**Files**:` — otherwise this is the
        # PRs-#24-#26 false-closure mode (PR claims a deliverable that
        # never shipped). Dump the commit stat as the audit trail, then
        # refuse + roll back when a declared path is missing.
        if committed:
            r = subprocess.run(
                ["git", "show", "--stat", "HEAD"],
                cwd=repo, capture_output=True, text=True,
            )
            print((r.stdout or "").rstrip(), flush=True)
        missing = reviewer_missing_files(repo, task, committed)
        if missing:
            print(f"loop: ✗ reviewer: declared Files missing from the "
                  f"close commit: {', '.join(missing)}; failing "
                  f"{task['id']} and reverting.")
            reviewer_reject_close(repo, task["id"], committed)
            record_run_row(repo, task, "reviewer-failed",
                           time.time() - task_started, max_turns)
            skipped_ids.add(task["id"])
            fail += 1
            seen_ids.add(task["id"])
            continue

        # Every gate passed — consume the queue spec (queue mode only).
        if "_queue_file" in task:
            close_queue_task(task)
            removed = True
        record_run_row(repo, task, "completed",
                       time.time() - task_started, max_turns)

        print(f"loop: ✓ task closed (agent rc=0, make check ✓, reviewer ✓, "
              f"block removed={removed}, committed={committed})")
        completed += 1

        seen_ids.add(task["id"])

    print()
    print("─" * 60)
    print(f"loop: done — completed={completed} failed={fail} "
          f"elapsed={ (time.time()-started)/60:.1f}m")
    return 0 if fail == 0 else 2


if __name__ == "__main__":
    sys.exit(main())
