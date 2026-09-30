"""Minimal agentic loop over Ollama's native /api/chat.

Why this exists (vs opencode + Ollama):
  - opencode talks to Ollama via @ai-sdk/openai-compatible. That adapter
    intermittently drops the required `description` field on bash tool
    calls and SchemaError-loops on qwen3 family models.
  - /api/chat natively returns clean tool_calls JSON (Ollama translates
    the model's XML to JSON server-side), so the loop is reliable.

Speed tuning notes (M3 Max, 64GB, qwen3-coder:30b):
  - True cold load (model unloaded): ~7.5 s after OLLAMA_KV_CACHE_TYPE=q8_0
    + OLLAMA_CONTEXT_LENGTH=32768 (was 8.6 s with f16 KV + 262K default).
  - Warm tiny inference: ~210 ms (3-token reply).
  - Realistic agent turn (~50-token tool call output): ~1-2 s warm.
  - Loop overhead per turn (HTTP, JSON encode/decode, agent bookkeeping):
    ~50 ms.

Usage:
  python3 ollama-agent.py "<task description>"
    [--model qwen3-coder:30b]   default; pick qwen3:8b for cheap loops
    [--max-turns 12]            default 10
    [--num-ctx 8192]            request-level context (default 8192;
                                bumps to 16384 for longer code reviews)
    [--keep-alive 24h]          how long the model stays loaded after
                                the run finishes
    [--cwd <dir>]               where to run bash commands
    [--quiet]                   only print final assistant content,
                                no per-turn $/output frames
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request


OLLAMA = os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434")
TURN_TIMEOUT = 300

# Directive system prompt — qwen3-coder:30b spends ~50-100 tokens "thinking
# out loud" before calling a tool when given a permissive prompt. Stating
# "never explain; call the tool" cuts that overhead by ~3 s per turn.
#
# We also append the contents of docs/audits/local-ai-failure-modes.md so
# the agent sees its own historical failure patterns as in-context warnings.
# The file is small (~50 lines / ~1 KB) and gets cached by Ollama's prefix
# match — costs <50 ms of prompt-eval on warm calls.
_DEFAULT_SYSTEM_PROMPT = (
    "You are a shell agent on macOS (M3 Max, BSD userland — NOT GNU). "
    "When the user asks you to do something, call a tool and wait for "
    "the result. Do NOT explain what you are about to do — just call "
    "the tool. When the task is fully complete, call the `done` tool "
    "with a one- or two-line summary.\n"
    "\n"
    "Tools (pick the right one):\n"
    "  - `bash` — run a one-liner. Good for reading, listing, grepping, "
    "running tests, git ops.\n"
    "  - `write_file` — write a whole NEW file in one shot (path + content). "
    "ALWAYS prefer this over `bash` with a heredoc when emitting files "
    "longer than ~10 lines or anything with embedded quotes / backticks "
    "/ $-vars / newlines. Bash heredoc quoting eats single quotes and "
    "wastes turns. For EXISTING files over 20 lines, use `patch_file` "
    "instead — write_file will refuse large-to-tiny overwrites.\n"
    "  - `patch_file` — surgically edit an existing file. Three modes: "
    "`replace` (literal old_string → new_string, must match exactly "
    "once), `insert_after` (insert after the line matching old_string), "
    "`append` (append to EOF). This is the RIGHT tool for editing "
    "Makefiles, existing doctor.sh modules, pre-commit hooks, etc.\n"
    "  - `verify_cli_claims` — IMMEDIATELY after every `write_file` that "
    "emits a doc / README / user story, call this on the same path. It "
    "greps the file for `bin/<name>` references and checks each script "
    "exists + the cited flags really show up in the script source. "
    "Catches the recurring hallucinated-flag failure mode where you "
    "write `bin/foo --bar` for a flag the script never declared.\n"
    "  - `critique_test` — IMMEDIATELY after every `write_file` that "
    "emits a `tests/*.bats` file, call this with the path AND the full "
    "task description. It catches placeholder tests (literal "
    "'placeholder', 'TODO', 'would require'), tautological assertions "
    "(`export X=foo && [ \"$X\" = \"foo\" ]`), and tests that don't "
    "reference the file paths / expected values from the task. `done` "
    "is BLOCKED until critique_test passes on every bats file you wrote.\n"
    "  - `done` — task complete; pass a one-line summary.\n"
    "\n"
    "Hard rules:\n"
    "  - Never invent tool output — report only what the tool returned.\n"
    "  - macOS sed differs from GNU sed: `sed -i ''` not `sed -i`. If "
    "your sed call fails with `invalid command code T`, switch to "
    "python3 (re or splicing) — do NOT retry the same sed with extra "
    "quoting. Spend at most ONE attempt on sed before pivoting.\n"
    "  - If the same command fails twice with the same error, change "
    "strategy. Don't loop.\n"
    "  - Never run destructive commands (rm -rf, git push --force, npm "
    "publish, gh pr merge, etc.) without being explicitly asked."
)


def _load_failure_modes() -> str:
    """Append the failure-modes file (if present) to the system prompt.

    This is the compounding-knowledge layer: every observed failure that
    generalises across tasks gets logged in
    `docs/audits/local-ai-failure-modes.md` and becomes a per-turn
    warning for future runs. Loaded relative to this file so the agent
    works from any cwd.
    """
    import os.path
    here = os.path.dirname(os.path.abspath(__file__))
    fm = os.path.normpath(os.path.join(here, "..", "docs", "audits", "local-ai-failure-modes.md"))
    if not os.path.exists(fm):
        return ""
    try:
        with open(fm) as f:
            text = f.read()
    except Exception:
        return ""
    # Guard against the file growing past the budget — we'd rather drop
    # the addition than blow the per-turn context.
    MAX = 4096  # chars (~1K tokens)
    if len(text) > MAX:
        text = text[:MAX] + "\n[…truncated for context budget…]\n"
    return (
        "\n\nKnown failure modes from past runs of this agent — read "
        "carefully and avoid repeating them:\n\n" + text
    )


SYSTEM_PROMPT = _DEFAULT_SYSTEM_PROMPT + _load_failure_modes()


def chat(messages, model, tools, num_ctx, keep_alive):
    """POST /api/chat with a 3-stage retry ladder.

    Ollama has a known bug (github.com/ollama/ollama/issues/14834)
    where `qwen3-coder:30b` emits malformed tool-call XML and the
    Ollama parser crashes with HTTP 500 + 'qwen tool call parsing
    failed'. The model is deterministic at temp=0, so retrying the
    exact same request gives the exact same crash — which is what
    we observed in runs 3, 4, and 5.

    Workaround: each retry bumps the sampling temperature slightly
    so the model explores a different completion path that is more
    likely to emit well-formed XML. Upstream PRs #14906 and #14915
    add server-side handling for this; until those merge we work
    around it client-side.

    Stage 0: temp=0    (the expected path)
    Stage 1: temp=0.2  (after 500 — same approach, wiggle sampling)
    Stage 2: temp=0.4  (after 2 x 500 — more aggressive wiggle)
    After 3 failures: propagate the error.
    """
    temps = [0.0, 0.2, 0.4]
    sleeps = [0, 2, 4]
    last_err: Exception | None = None
    for attempt, (temp, sleep_s) in enumerate(zip(temps, sleeps)):
        if sleep_s:
            time.sleep(sleep_s)
        body = json.dumps({
            "model": model,
            "messages": messages,
            "tools": tools,
            "stream": False,
            "keep_alive": keep_alive,
            "options": {
                "temperature": temp,
                "num_ctx": num_ctx,
                # 4096 not 512 — the original cap bit us on the
                # docs-local-ai-tuning-user-story run (model stopped
                # mid-write_file because it ran out of output budget
                # while emitting a multi-line doc). 4096 is enough for
                # ~120 lines of doc; the model still self-terminates
                # well before that on most agent turns. See
                # docs/audits/local-ai-task-runs-*.
                "num_predict": 4096,
            },
        }).encode()
        req = urllib.request.Request(
            f"{OLLAMA}/api/chat",
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=TURN_TIMEOUT) as resp:
                return json.loads(resp.read())
        except urllib.error.HTTPError as e:
            last_err = e
            if e.code == 500 and attempt < len(temps) - 1:
                continue
            raise
    if last_err:
        raise last_err
    raise RuntimeError("unreachable: chat retry ladder exhausted with no error")


# Process-lifecycle commands the agent is forbidden to run. Surfaced
# after the agent killed Ollama on port 11434 mid-loop (docs/audits/
# local-ai-failure-modes.md). The agent has no authority over running
# services; if a port is busy, it must `skip` the test.
DENY_BASH = re.compile(
    r"(^|[\s|;&(`])("
    r"kill|pkill|killall|"
    r"launchctl\s+(bootout|kickstart\s+-k|unload)|"
    r"systemctl\s+stop|"
    r"service\s+\S+\s+stop|"
    r"docker\s+(stop|kill)|"
    r"shutdown|reboot|halt"
    r")(\b|$)",
)
# Test-isolation guard: writing to $HOME / ~/.config from a bats test
# clobbers the developer's real state. Tests must redirect HOME to a
# mktemp -d. The check fires only when the path is in tests/ and not
# guarded by an explicit `HOME=$(mktemp ...)` prefix on the same line.
HOME_WRITE = re.compile(
    r"(>|>>|cat\s+>|tee\s+|cp\s+\S+\s+|mv\s+\S+\s+|mkdir\s+(-p\s+)?)\s*"
    r"(\"|')?(\$HOME|~/.config|~/\.config|~/\.claude|~/\.cursor)",
)


def run_bash(cmd: str, cwd: str | None) -> dict:
    if DENY_BASH.search(cmd):
        return {
            "exit_code": 126,
            "stdout": "",
            "stderr": (
                "blocked: process-lifecycle commands "
                "(kill/pkill/launchctl/systemctl/docker stop) are forbidden. "
                "If a port is in use, skip the test instead of freeing it."
            ),
        }
    # Only block $HOME-write patterns when we're writing into a bats
    # test file via heredoc/cat — the agent's own working files may
    # legitimately reference $HOME (e.g. checking the developer's config).
    # The deny target is `cat > tests/*.bats <<EOF ... $HOME ...` and
    # similar heredoc-into-test patterns.
    if "tests/" in cmd and HOME_WRITE.search(cmd):
        return {
            "exit_code": 126,
            "stdout": "",
            "stderr": (
                "blocked: bats tests must not write to $HOME / ~/.config. "
                "Use `HOME=$(mktemp -d)` at the top of setup() and write "
                "into the temp dir."
            ),
        }
    try:
        result = subprocess.run(
            ["bash", "-c", cmd],
            capture_output=True,
            text=True,
            timeout=180,
            cwd=cwd,
        )
        return {
            "exit_code": result.returncode,
            "stdout": result.stdout[-4000:],
            "stderr": result.stderr[-2000:],
        }
    except subprocess.TimeoutExpired:
        return {"exit_code": 124, "stdout": "", "stderr": "timeout (180s)"}
    except Exception as e:
        return {"exit_code": 1, "stdout": "", "stderr": f"agent error: {e}"}


TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "bash",
            "description": "Run a bash command in the agent's cwd and return exit code, stdout (last 4KB), stderr (last 2KB).",
            "parameters": {
                "type": "object",
                "properties": {
                    "command": {
                        "type": "string",
                        "description": "Bash command to execute.",
                    },
                },
                "required": ["command"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "write_file",
            "description": (
                "Write a file in the agent's cwd. Prefer this over `bash` with a heredoc — "
                "the content goes directly in the tool argument, so there are no quoting "
                "headaches and no python3 -c '...' wrapper to debug. Overwrites existing files. "
                "Returns the absolute path written and the byte count."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Relative path (from cwd) or absolute path of the file to write.",
                    },
                    "content": {
                        "type": "string",
                        "description": "Full file contents. No trailing-newline normalization is done.",
                    },
                },
                "required": ["path", "content"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "verify_cli_claims",
            "description": (
                "Scan a file you just wrote for `bin/<name>` references and run "
                "`<name> --help` on each one to confirm the script actually exists "
                "and the flags you cited are real. Catches the recurring failure "
                "mode where the model writes `bin/foo --bar` without ever testing "
                "the flag. Returns a per-script report. Use this immediately after "
                "any write_file that emits docs / READMEs / user stories."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Path of the file to verify (the doc you just wrote).",
                    },
                },
                "required": ["path"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "patch_file",
            "description": (
                "Surgically edit an existing file without re-emitting the "
                "whole thing. Three modes: (1) `replace` — replace the "
                "literal old_string with new_string (must match exactly "
                "once); (2) `insert_after` — insert new_string on the "
                "line AFTER the line matching old_string (must match "
                "exactly once); (3) `append` — append new_string to the "
                "end of the file (old_string is ignored). USE THIS over "
                "write_file whenever you're modifying an existing file "
                "larger than ~20 lines — it prevents the destructive-"
                "overwrite failure mode (agent emits a stub that "
                "clobbers the real content)."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Relative path (from cwd) or absolute path of the file to patch.",
                    },
                    "mode": {
                        "type": "string",
                        "description": "One of: replace, insert_after, append",
                    },
                    "old_string": {
                        "type": "string",
                        "description": "The exact text to find (replace/insert_after) — must match exactly once. Ignored for append.",
                    },
                    "new_string": {
                        "type": "string",
                        "description": "The text to substitute in (replace) / insert after the match (insert_after) / append to the file (append).",
                    },
                },
                "required": ["path", "mode", "new_string"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "critique_test",
            "description": (
                "Self-critique a bats test file you just wrote for the "
                "hallucination tells observed in run-4 dogfood: placeholder "
                "comments ('would require', 'TODO', 'actual implementation', "
                "'placeholder'), tautological assertions (two strings the "
                "test itself set), and missing references to the file paths "
                "and expected values from the task description. Returns "
                "PASS or a FAIL report explaining what the agent must fix. "
                "Call this immediately after any write_file targeting "
                "tests/*.bats — BEFORE running make check or calling done."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Path of the bats file to critique.",
                    },
                    "task_description": {
                        "type": "string",
                        "description": (
                            "The full task description from the loop's prompt. "
                            "The critic uses this to extract expected file paths "
                            "and literal values that the test must reference."
                        ),
                    },
                },
                "required": ["path", "task_description"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "done",
            "description": "Signal the task is complete. Provide a one- to two-line summary of what changed.",
            "parameters": {
                "type": "object",
                "properties": {
                    "summary": {
                        "type": "string",
                        "description": "Short summary of the work just completed.",
                    },
                },
                "required": ["summary"],
            },
        },
    },
]


def run_verify_cli_claims(path: str, cwd: str) -> dict:
    """Scan a written doc for `bin/<name>` references and probe each.

    Returns a textual report with PASS/FAIL per script. Mirrors the
    run_bash / run_write_file output shape so the message loop is uniform.

    Catches the recurring "hallucinated CLI flag" failure mode observed
    in docs/audits/local-ai-task-runs-2026-05-11.md task 1 + 2:
      - `bin/local-ai-agent --prompt "..."` (no such flag)
      - `gh issue view 8095 10699` (no multi-arg form)

    The verifier is intentionally narrow: it only checks `bin/<name>`
    references against the repo's own `bin/` directory and the listed
    flag strings. Cross-host CLIs like `gh` are out of scope (too many
    legitimate flag-shape variants).
    """
    import os.path
    import re
    try:
        abs_path = path if os.path.isabs(path) else os.path.join(cwd, path)
        if not os.path.exists(abs_path):
            return {
                "exit_code": 1,
                "stdout": "",
                "stderr": f"verify_cli_claims: file not found: {abs_path}",
            }
        with open(abs_path) as f:
            text = f.read()
    except Exception as e:
        return {"exit_code": 1, "stdout": "", "stderr": f"verify_cli_claims error: {e}"}

    # Match `bin/<name>` (the canonical form used in this repo). Tolerate
    # `[...](../../bin/<name>)` markdown links and `<code>bin/<name></code>`
    # alike — just pull the basename.
    #
    # Skip shebang lines explicitly — `#!/usr/bin/env bats` matches the
    # `bin/env` regex but isn't a repo CLI reference. Same for `#!/bin/bash`
    # and similar interpreter shebangs. Any line starting with `#!` is
    # treated as an opaque interpreter declaration.
    cited = set()
    for line in text.splitlines():
        if line.startswith("#!"):
            continue
        for m in re.findall(r"\bbin/([a-zA-Z0-9._-]+)", line):
            cited.add(m)
    # Common interpreter basenames that should never be treated as repo
    # CLIs even if they leak through (e.g. inline docs that quote a
    # `/usr/bin/env python3` example).
    cited -= {"env", "sh", "bash", "zsh", "python3", "python", "node"}
    if not cited:
        return {
            "exit_code": 0,
            "stdout": f"verify_cli_claims: no bin/<name> references in {path}",
            "stderr": "",
        }

    # For each cited script, check it exists in the repo's bin/ AND that
    # every flag-shaped token (`--word` or `-x`) cited adjacent to it
    # appears in the script's source surface. The surface includes:
    #   - The script itself (first 200 lines).
    #   - Any sibling `lib/<name>.py` / `lib/<name>.sh` (thin-wrapper case;
    #     most flags live in the lib file for bash→python wrappers).
    #   - Any file the script `exec`s into (parsed from `exec ... <path>`).
    repo_bin = os.path.join(cwd, "bin")
    repo_lib = os.path.join(cwd, "lib")
    report_lines = [f"verify_cli_claims: checking {len(cited)} cited script(s) in {path}"]
    failures = 0
    for name in sorted(cited):
        script = os.path.join(repo_bin, name)
        if not os.path.exists(script):
            report_lines.append(f"  ✗ bin/{name} — NOT FOUND in repo bin/")
            failures += 1
            continue
        # Read the script + any sibling lib files + any `exec`-target.
        surface_parts = []
        try:
            with open(script) as f:
                head = "".join(f.readlines()[:200])
                surface_parts.append(head)
        except Exception:
            head = ""
        # Sibling lib files
        for suffix in (".py", ".sh", ""):
            sib = os.path.join(repo_lib, name + suffix)
            if os.path.exists(sib) and sib != script:
                try:
                    with open(sib) as f:
                        surface_parts.append(f.read())
                except Exception:
                    pass
        # exec-target lines like `exec /usr/local/bin/python3 "$LIB"` —
        # follow shell vars that look like `<NAME>="$SCRIPT_DIR/../lib/foo"`
        for var_match in re.finditer(r'([A-Z_][A-Z0-9_]*)="\$SCRIPT_DIR/(\.\./[^"]+)"', head):
            rel = var_match.group(2)
            target = os.path.normpath(os.path.join(repo_bin, rel))
            if os.path.exists(target) and target not in (script,):
                try:
                    with open(target) as f:
                        surface_parts.append(f.read())
                except Exception:
                    pass
        surface = "\n".join(surface_parts)
        # Build the set of DECLARED flags — parse argparse + bash case
        # blocks rather than substring-grep'ing, because system-prompt
        # strings inside the script will contain English words that look
        # like flag matches.
        declared = set()
        # argparse: `ap.add_argument("--foo"...)` or `add_argument('--foo'...)`
        for m in re.findall(r"""add_argument\(\s*["'](--[a-zA-Z][a-zA-Z0-9-]*)""", surface):
            declared.add(m)
        # bash case blocks: `--foo) ...` or `--foo|-f) ...`
        for m in re.findall(r"^\s*(--[a-zA-Z][a-zA-Z0-9-]*)\s*[)\|]", surface, re.MULTILINE):
            declared.add(m)
        # click decorators: `@click.option("--foo"...)`
        for m in re.findall(r"""@click\.option\(\s*["'](--[a-zA-Z][a-zA-Z0-9-]*)""", surface):
            declared.add(m)

        # Find every doc reference like `bin/<name> --foo` and check
        # each `--foo` against the declared set.
        bad_flags = []
        for line in text.splitlines():
            if f"bin/{name}" not in line:
                continue
            for flag in re.findall(r"(--[a-zA-Z][a-zA-Z0-9-]*)", line):
                # Allow generic shell flags that aren't script-specific.
                if flag in {"--help", "--version"}:
                    continue
                if flag not in declared:
                    bad_flags.append(flag)
        if bad_flags:
            report_lines.append(
                f"  ✗ bin/{name} — exists, but doc cites unknown flag(s): "
                f"{', '.join(sorted(set(bad_flags)))}"
            )
            failures += 1
        else:
            report_lines.append(f"  ✓ bin/{name} — exists; flags look real")
    if failures:
        report_lines.append(
            f"FAIL: {failures} script(s) failed verification. "
            "Read the script's source (e.g. `head -30 bin/<name>`) and fix "
            "the doc's flag usage, or remove the bogus citation."
        )
        return {"exit_code": 1, "stdout": "\n".join(report_lines), "stderr": ""}
    return {"exit_code": 0, "stdout": "\n".join(report_lines), "stderr": ""}


def run_critique_test(path: str, task_description: str, cwd: str) -> dict:
    """Self-critique a bats test file the agent just wrote.

    Catches the hallucinated-test failure mode observed in run-4 of
    the dogfood loop: the agent wrote a "Devin model agrees across
    three layers" test that used a fake model name (gpt-4-turbo) and
    tautological assertions ([ "$DEVIN_MODEL" = "gpt-4-turbo" ] after
    exporting it to that value). The test passed `make check` and was
    auto-committed by the loop. Useless test, false confidence.

    The critique looks for THREE classes of red flag:
      1. Placeholder comments — "placeholder", "would require",
         "actual implementation", "TODO", "FIXME", "for now we just",
         "this is a stub", "for now, we just verify".
      2. Tautological assertions — variables exported in the test
         body, then immediately asserted against the same literal
         (e.g. `export X="foo" && [ "$X" = "foo" ]`).
      3. Missing context anchors — extract literal-quoted values and
         file paths from the task_description; the test must reference
         at least one of each (case-insensitive substring match).

    Returns PASS (exit 0) or FAIL with a per-class report (exit 1).
    """
    abs_path = path if os.path.isabs(path) else os.path.join(cwd, path)
    if not os.path.exists(abs_path):
        return {
            "exit_code": 1,
            "stdout": "",
            "stderr": f"critique_test: file not found: {abs_path}",
        }
    try:
        with open(abs_path) as f:
            text = f.read()
    except Exception as e:
        return {"exit_code": 1, "stdout": "", "stderr": f"critique_test error: {e}"}

    fails: list[str] = []

    # 1) Placeholder comments
    PLACEHOLDER_PATTERNS = [
        r"\bplaceholder\b",
        r"\bwould require\b",
        r"\bactual implementation\b",
        r"\bTODO\b", r"\bFIXME\b", r"\bXXX\b",
        r"\bfor now we just\b",
        r"\bfor now, we just\b",
        r"this is a stub",
        r"this would require",
    ]
    hits = []
    for pat in PLACEHOLDER_PATTERNS:
        for m in re.finditer(pat, text, re.IGNORECASE):
            line_no = text[:m.start()].count("\n") + 1
            hits.append(f"  line {line_no}: {m.group()}")
    if hits:
        fails.append(
            "FAIL: placeholder comments found — this test admits it's "
            "incomplete:\n" + "\n".join(hits[:10])
        )

    # 2) Tautological assertions: extract `export VAR="value"` and look for
    # `[ "$VAR" = "value" ]` (or equivalent) in the SAME @test block.
    test_blocks = re.split(r"^@test ", text, flags=re.MULTILINE)
    tautology_hits = []
    for block in test_blocks:
        exports = re.findall(r'export\s+(\w+)\s*=\s*"([^"]+)"', block)
        for var, val in exports:
            # The assertion form: `[ "$VAR" = "val" ]` or `[ "$VAR" == "val" ]`.
            assert_pat = (
                r'\[\s*"\$' + re.escape(var) + r'"\s*==?\s*"'
                + re.escape(val) + r'"\s*\]'
            )
            if re.search(assert_pat, block):
                tautology_hits.append(f"  ${var} → exported then asserted == \"{val}\"")
    if tautology_hits:
        fails.append(
            "FAIL: tautological assertions — the test exports a value "
            "then asserts the same value. That proves nothing:\n"
            + "\n".join(tautology_hits[:10])
        )

    # 2b) Minimum @test count. If the task description says "N @test
    # cases" / "N tests" / "N bats tests", the file must have at
    # least that many `@test "..."` blocks. Observed in the
    # cover-local-ai-readiness-check-surface P0 run: agent wrote 1
    # test when asked for 3, and the loop auto-closed the task
    # because make check passed. Tighten the critic to catch this.
    test_count = len(re.findall(r"^@test ", text, re.MULTILINE))
    required_count: int | None = None
    for pat in (
        r"\b(\d+)\s*@test\b",
        r"\b(\d+)\s+(?:separate\s+)?(?:bats\s+)?tests?\s+(?:that|which|each)?",
        r"with\s+(\d+)\s+`?@test`?\s+cases",
        r"includes?\s+(\d+)\s+(?:cases?|checks?|assertions?)",
    ):
        m = re.search(pat, task_description, re.IGNORECASE)
        if m:
            candidate = int(m.group(1))
            # Sanity: the counts the task requests are always 1-20.
            # Bigger numbers are probably line counts or byte counts.
            if 1 <= candidate <= 20:
                required_count = candidate
                break
    if required_count is not None and test_count < required_count:
        fails.append(
            f"FAIL: task asked for {required_count} @test cases but "
            f"file has only {test_count}. Add the missing tests; "
            "don't compress N requirements into one @test block."
        )

    # 3) Missing context anchors. Extract candidate anchors from
    # task_description: file paths (with .ext OR a / separator) and
    # double-quoted literals.
    file_anchors = set()
    # Pattern A: explicit-extension files (foo.bats, foo.sh).
    for m in re.finditer(
        r"\b(?:[a-zA-Z0-9_\-./]+/)?[a-zA-Z0-9_\-]+\.(?:bats|sh|py|json|md|conf|tmpl|yml|yaml|toml)\b",
        task_description,
    ):
        file_anchors.add(m.group())
    # Pattern B: dir/file-like paths (home/zshrc.ai-tools, ~/.config/devin/config.json).
    for m in re.finditer(
        r"\b(?:~/|\./)?[a-zA-Z0-9_\-]+/[a-zA-Z0-9_\-./~]+\b",
        task_description,
    ):
        # Skip if it looks like a URL.
        if "http" in m.group() or "://" in m.group():
            continue
        file_anchors.add(m.group())
    # Filter out the test's OWN path — it's the write target, not
    # something the test should reference. Observed in run-5: the
    # critic kept failing because `tests/devin-model-three-layer-
    # consistency.bats` was in the required-anchor set, but that's
    # the file we just wrote (a test can't import itself).
    test_path_norm = path.lstrip("./")
    test_basename = os.path.basename(test_path_norm)
    file_anchors.discard(test_path_norm)
    file_anchors.discard(test_basename)
    # Also drop OTHER .bats files — sibling tests aren't dependencies.
    file_anchors = [f for f in file_anchors if not f.endswith(".bats")]
    quoted_literals = re.findall(r'`([^`]{3,60})`', task_description)
    # Filter to plausibly-significant anchors only.
    significant_files = [f for f in file_anchors
                         if not f.endswith(".md") and len(f) > 4]
    # Exclude procedural boilerplate literals — these come from the
    # loop's "When complete: run make check / stage with git add / call
    # done" wrapper around every task prompt. The test file cannot
    # reasonably reference them. Observed in P0 attempt #4 that the
    # critic flagged `make check` and `git add` as "required anchors".
    PROCEDURAL_LITERALS = {
        "make check", "make test", "make test-all", "make test-force",
        "make lint", "make lint-tasks", "make audit",
        "git add", "git add <files>", "git commit", "git push",
        "done", "BLOCKED:", "TASKS.md", "AGENTS.md",
        "bash", "write_file", "patch_file", "critique_test",
        "verify_cli_claims",
    }
    significant_literals = [
        L for L in quoted_literals
        if not re.fullmatch(r"[\w_-]+:[\w_-]+", L)  # filter "key:value" markdown
        and any(c.isalpha() for c in L)
        and len(L) > 3
        and "/" not in L  # paths covered separately
        and L not in PROCEDURAL_LITERALS
        and "<" not in L  # drop `git add <files>` placeholder forms
    ]
    if significant_files or significant_literals:
        # The test must reference at least HALF of each list (case-insensitive).
        # We're lenient — even one anchor proves the agent read the task.
        text_lc = text.lower()
        file_hits = sum(1 for f in significant_files if f.lower() in text_lc)
        lit_hits = sum(1 for L in significant_literals if L.lower() in text_lc)
        if significant_files and file_hits == 0:
            fails.append(
                "FAIL: test references NONE of the task's named files: "
                + ", ".join(significant_files[:5])
                + ". Did you read the task description?"
            )
        if significant_literals and lit_hits == 0:
            fails.append(
                "FAIL: test references NONE of the task's quoted literals: "
                + ", ".join(f"`{L}`" for L in significant_literals[:5])
                + ". The test must assert the actual expected values, "
                "not generic stand-ins."
            )

    if fails:
        return {
            "exit_code": 1,
            "stdout": "\n\n".join(fails),
            "stderr": "",
        }
    return {
        "exit_code": 0,
        "stdout": "critique_test PASS — no placeholder, tautology, or "
                  "missing-anchor signals.",
        "stderr": "",
    }


def run_patch_file(path: str, mode: str, old_string: str | None,
                   new_string: str, cwd: str) -> dict:
    """Surgically edit an existing file — replace / insert_after / append.

    Prevents the destructive-overwrite failure mode where the agent
    tries to "edit" a large file by emitting a tiny rewrite that
    clobbers everything.

    Modes:
      replace       old_string → new_string (must match exactly once)
      insert_after  finds old_string, inserts new_string after that line
      append        appends new_string to EOF (old_string ignored)
    """
    import os.path
    abs_path = path if os.path.isabs(path) else os.path.join(cwd, path)
    if not os.path.exists(abs_path):
        return {
            "exit_code": 1,
            "stdout": "",
            "stderr": f"patch_file: file not found: {abs_path}",
        }
    try:
        with open(abs_path) as f:
            text = f.read()
    except Exception as e:
        return {"exit_code": 1, "stdout": "", "stderr": f"patch_file read error: {e}"}

    if mode == "append":
        new_text = text + new_string
    elif mode == "replace":
        if not old_string:
            return {"exit_code": 1, "stdout": "", "stderr": "patch_file replace: old_string is required"}
        count = text.count(old_string)
        if count == 0:
            return {
                "exit_code": 1,
                "stdout": "",
                "stderr": (
                    "patch_file replace: old_string not found. "
                    "Paste it from a fresh read of the file — don't "
                    "paraphrase. Note: bash tab-characters and line "
                    "endings must match exactly."
                ),
            }
        if count > 1:
            return {
                "exit_code": 1,
                "stdout": "",
                "stderr": (
                    f"patch_file replace: old_string matched {count} "
                    "times; must be unique. Include more surrounding "
                    "context to disambiguate."
                ),
            }
        new_text = text.replace(old_string, new_string, 1)
    elif mode == "insert_after":
        if not old_string:
            return {"exit_code": 1, "stdout": "", "stderr": "patch_file insert_after: old_string is required"}
        count = text.count(old_string)
        if count != 1:
            return {
                "exit_code": 1,
                "stdout": "",
                "stderr": (
                    f"patch_file insert_after: old_string matched {count} "
                    "times; must be exactly once."
                ),
            }
        # Find the end of the line containing old_string and insert after it.
        anchor_end = text.index(old_string) + len(old_string)
        # Seek to end of line.
        nl = text.find("\n", anchor_end)
        if nl == -1:
            # Anchor is on the last line; append with a leading newline.
            new_text = text + ("\n" if not text.endswith("\n") else "") + new_string
        else:
            new_text = text[:nl + 1] + new_string + ("\n" if not new_string.endswith("\n") else "") + text[nl + 1:]
    else:
        return {
            "exit_code": 1,
            "stdout": "",
            "stderr": f"patch_file: unknown mode '{mode}'. Use replace | insert_after | append.",
        }

    try:
        # Atomic-ish: tmp + rename.
        import tempfile
        parent = os.path.dirname(abs_path) or "."
        fd, tmp = tempfile.mkstemp(
            prefix=".local-ai-agent.",
            suffix=".tmp",
            dir=parent,
        )
        with os.fdopen(fd, "w") as f:
            f.write(new_text)
        os.replace(tmp, abs_path)
    except Exception as e:
        return {"exit_code": 1, "stdout": "", "stderr": f"patch_file write error: {e}"}
    delta = len(new_text) - len(text)
    sign = "+" if delta >= 0 else ""
    return {
        "exit_code": 0,
        "stdout": f"patched {abs_path} (mode={mode}, {sign}{delta} bytes)",
        "stderr": "",
    }


def run_write_file(path: str, content: str, cwd: str) -> dict:
    """Atomic-ish write: create parent dirs, write to tmp, rename.

    Returns the same shape as `run_bash` so the message loop is uniform.

    Destructive-write guard: refuses to overwrite an existing tracked
    file with content less than 25% of the existing file's size when
    the file is larger than 100 lines. Observed in run-5: agent wrote
    a 345-byte stub over the real 7089-byte `git-hooks/pre-commit`,
    destroying the existing security hook. The cleanup logic
    eventually restored it, but a write_file should not be allowed to
    silently destroy substantial existing files.
    """
    import os.path
    import tempfile
    try:
        abs_path = path if os.path.isabs(path) else os.path.join(cwd, path)
        # Destructive-write check: if the target exists and is large,
        # the new content should be at least 25% of its size.
        if os.path.exists(abs_path):
            try:
                with open(abs_path) as existing:
                    old_text = existing.read()
                old_lines = old_text.count("\n") + 1
                if old_lines > 100 and len(content) < len(old_text) // 4:
                    return {
                        "exit_code": 1,
                        "stdout": "",
                        "stderr": (
                            f"refused: overwriting {abs_path} "
                            f"({len(old_text)} bytes, {old_lines} lines) "
                            f"with only {len(content)} bytes is likely "
                            "destructive. If you mean to extend the file, "
                            "read it first and emit the FULL new content."
                        ),
                    }
            except Exception:
                pass  # if we can't read, fall through to write
        parent = os.path.dirname(abs_path)
        if parent:
            os.makedirs(parent, exist_ok=True)
        fd, tmp = tempfile.mkstemp(
            prefix=".local-ai-agent.",
            suffix=".tmp",
            dir=parent or None,
        )
        with os.fdopen(fd, "w") as f:
            n = f.write(content)
        os.replace(tmp, abs_path)
        return {
            "exit_code": 0,
            "stdout": f"wrote {n} bytes to {abs_path}",
            "stderr": "",
        }
    except Exception as e:
        return {"exit_code": 1, "stdout": "", "stderr": f"write_file error: {e}"}


def record_telemetry(cwd: str, args, tel: dict, outcome: str, turns: int,
                     elapsed_s: float, task: str) -> None:
    """Append one row per run to docs/audits/local-ai-runs.csv.

    The CSV is human-grepable and small. Columns are chosen so a
    cheap `awk -F, '$3=="done"' docs/audits/local-ai-runs.csv` answers
    "how fast is the loop trending" without a Python or spreadsheet
    detour.

    outcome:
      done            — agent called `done` and it was allowed
      stopped         — agent stopped with no tool calls
      max_turns       — agent hit the turn budget
      error           — chat call threw an exception
    """
    import csv
    csv_path = os.path.join(cwd, "docs", "audits", "local-ai-runs.csv")
    os.makedirs(os.path.dirname(csv_path), exist_ok=True)
    new_file = not os.path.exists(csv_path)
    median_tps = (sorted(tel["tps_samples"])[len(tel["tps_samples"]) // 2]
                  if tel["tps_samples"] else 0)
    row = [
        time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        args.model,
        outcome,
        turns,
        round(elapsed_s, 1),
        tel["writes"],
        tel["bashes"],
        tel["verifies"],
        tel["blocked_done"],
        tel["blocked_deny"],
        tel["total_input_toks"],
        tel["total_output_toks"],
        round(median_tps),
        # Truncate task to one line, 80 chars — full task lives in
        # the loop's commit message anyway.
        task.replace("\n", " ").strip()[:80],
    ]
    with open(csv_path, "a", newline="") as f:
        w = csv.writer(f)
        if new_file:
            w.writerow([
                "ts", "model", "outcome", "turns", "elapsed_s",
                "writes", "bashes", "verifies",
                "blocked_done", "blocked_deny",
                "input_toks", "output_toks", "median_tps", "task",
            ])
        w.writerow(row)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("task", help="Task description")
    ap.add_argument("--model", default="qwen3-coder:30b")
    # 14 not 10 — observed in task 5/5 (tests/local-ai-bench.bats run)
    # that the agent uses 3-4 turns gathering context, then needs a
    # write + multiple test-fix iterations. A 10-turn budget left it
    # one turn shy of debugging its own bats failures.
    ap.add_argument("--max-turns", type=int, default=14)
    ap.add_argument("--num-ctx", type=int, default=8192)
    ap.add_argument("--keep-alive", default="24h")
    ap.add_argument("--cwd", default=os.getcwd())
    ap.add_argument("--quiet", action="store_true")
    # Telemetry: append a row per run to docs/audits/local-ai-runs.csv
    # so trends (tok/s, turns to done, success rate) show up over time.
    # Off by default for unit tests; on by default in bin/local-ai-agent.
    ap.add_argument("--telemetry", action="store_true",
                    help="Append a row to docs/audits/local-ai-runs.csv on exit")
    args = ap.parse_args()

    log = (lambda *a, **kw: None) if args.quiet else (lambda *a, **kw: print(*a, **kw, flush=True))

    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": args.task},
    ]

    started = time.time()
    # Track whether the agent ran a verification gate after its last
    # write. The `done` tool refuses to claim completion until either
    # (a) no writes have happened (read-only task), or (b) the most
    # recent `make check` / `bats tests/...` invocation since the last
    # write exited 0. Catches the "agent says done with failing tests"
    # mode (docs/audits/local-ai-failure-modes.md).
    last_write_turn = -1
    last_verify_turn = -1
    last_verify_ok = False
    # Telemetry counters
    tel = {"turns": 0, "writes": 0, "bashes": 0, "verifies": 0,
           "blocked_done": 0, "blocked_deny": 0,
           "critiques_pass": 0, "critiques_fail": 0,
           "total_input_toks": 0, "total_output_toks": 0,
           "tps_samples": []}
    # Bats tests the agent wrote but hasn't critiqued yet. The done
    # tool refuses to fire if this set is non-empty.
    test_writes_pending_critique: set[str] = set()
    for turn in range(1, args.max_turns + 1):
        log(f"\n=== turn {turn} ===")
        t0 = time.time()
        resp = chat(messages, args.model, TOOLS, args.num_ctx, args.keep_alive)
        elapsed = time.time() - t0
        msg = resp.get("message", {})
        content = msg.get("content", "")
        tool_calls = msg.get("tool_calls") or []

        eval_count = resp.get("eval_count", 0)
        eval_ms = (resp.get("eval_duration", 0) or 0) / 1e6
        tps = (eval_count * 1000 / eval_ms) if eval_ms else 0
        log(f"(turn took {elapsed:.1f}s, {eval_count} output toks, {tps:.0f} tok/s)")

        # Telemetry: roll up per-turn counters.
        tel["turns"] = turn
        tel["total_input_toks"] += resp.get("prompt_eval_count", 0) or 0
        tel["total_output_toks"] += eval_count
        if tps > 0:
            tel["tps_samples"].append(tps)

        if content.strip():
            log(f"model: {content.strip()[:500]}")

        if not tool_calls:
            log("(no tool calls — stopping)")
            log(f"\nTotal run: {time.time() - started:.1f}s, {turn} turn(s)")
            if args.telemetry:
                record_telemetry(args.cwd, args, tel, "stopped",
                                 turn, time.time() - started, args.task)
            return 0

        messages.append({
            "role": "assistant",
            "content": content,
            "tool_calls": tool_calls,
        })

        for call in tool_calls:
            fn = call.get("function", {})
            name = fn.get("name")
            args_blob = fn.get("arguments") or {}
            if isinstance(args_blob, str):
                try:
                    args_blob = json.loads(args_blob)
                except Exception:
                    args_blob = {"_raw": args_blob}

            if name == "done":
                summary = args_blob.get("summary", "(no summary)")
                # Verification precondition: if the agent wrote files,
                # it must have run `make check` or `bats tests/...` AFTER
                # the last write and that command must have exited 0.
                # First gate: pending test-critiques. If the agent wrote
                # bats files and hasn't critiqued them, refuse done.
                if test_writes_pending_critique:
                    msg = (
                        "blocked: cannot call `done` — you wrote these "
                        "bats tests but haven't critiqued them: "
                        + ", ".join(sorted(test_writes_pending_critique))
                        + ". Call `critique_test` on each one with the "
                        "task description before done. Catches placeholder "
                        "tests / tautological assertions / hallucinated "
                        "values."
                    )
                    log(f"[done blocked] {msg}")
                    tel["blocked_done"] += 1
                    messages.append({
                        "role": "tool",
                        "name": "done",
                        "content": f"exit_code=1\nstdout=\nstderr={msg}",
                    })
                    continue
                # Second gate: verification (make check).
                if last_write_turn > last_verify_turn or (last_verify_turn >= 0 and not last_verify_ok):
                    msg = (
                        "blocked: cannot call `done` — you wrote files but "
                        "haven't run a passing `make check` since. "
                        "ONLY `make check` satisfies the gate (narrow "
                        "`bats tests/<file>.bats` runs are useful while "
                        "iterating, but they don't catch pre-existing "
                        "broken tests in the repo)."
                    )
                    log(f"[done blocked] {msg}")
                    tel["blocked_done"] += 1
                    messages.append({
                        "role": "tool",
                        "name": "done",
                        "content": f"exit_code=1\nstdout=\nstderr={msg}",
                    })
                    continue
                log(f"\n=== done ===\n{summary}")
                log(f"\nTotal run: {time.time() - started:.1f}s, {turn} turn(s)")
                if args.quiet:
                    print(summary)
                if args.telemetry:
                    record_telemetry(args.cwd, args, tel, "done",
                                     turn, time.time() - started, args.task)
                return 0

            if name in ("bash", "write_file", "patch_file", "verify_cli_claims", "critique_test"):
                if name == "bash":
                    cmd = args_blob.get("command", "")
                    log(f"$ {cmd}")
                    result = run_bash(cmd, args.cwd)
                    tel["bashes"] += 1
                    if result["exit_code"] == 126:
                        tel["blocked_deny"] += 1
                    # Track verification-gate invocations. Only `make check`
                    # counts — observed in run-3 dogfood that the agent will
                    # game a narrow `bats tests/<file>.bats` gate by passing
                    # ONLY its own new test while leaving pre-existing broken
                    # tests in the repo from earlier failed task attempts.
                    # `make check` is the project's canonical health gate.
                    if re.search(r"\bmake\s+check\b", cmd):
                        last_verify_turn = turn
                        last_verify_ok = (result["exit_code"] == 0)
                        tel["verifies"] += 1
                elif name == "write_file":
                    path = args_blob.get("path", "")
                    content = args_blob.get("content", "")
                    log(f"write_file: {path} ({len(content)} bytes)")
                    result = run_write_file(path, content, args.cwd)
                    if result["exit_code"] == 0:
                        last_write_turn = turn
                        tel["writes"] += 1
                        # If the agent wrote a bats test, flag that
                        # critique_test must run before done.
                        if path.startswith("tests/") and path.endswith(".bats"):
                            test_writes_pending_critique.add(path)
                elif name == "patch_file":
                    path = args_blob.get("path", "")
                    mode = args_blob.get("mode", "")
                    old_s = args_blob.get("old_string", "")
                    new_s = args_blob.get("new_string", "")
                    log(f"patch_file: {path} mode={mode} new={len(new_s)}B")
                    result = run_patch_file(path, mode, old_s, new_s, args.cwd)
                    if result["exit_code"] == 0:
                        last_write_turn = turn
                        tel["writes"] += 1
                        if path.startswith("tests/") and path.endswith(".bats"):
                            test_writes_pending_critique.add(path)
                elif name == "verify_cli_claims":
                    path = args_blob.get("path", "")
                    log(f"verify_cli_claims: {path}")
                    result = run_verify_cli_claims(path, args.cwd)
                else:  # critique_test
                    path = args_blob.get("path", "")
                    task_desc = args_blob.get("task_description", "")
                    # Observed in P0 dogfood runs 1-5 that qwen3-coder
                    # condenses the task description when it passes it
                    # to critique_test (e.g. a 50-word gloss), dropping
                    # the count signal and the backtick-quoted
                    # literals the critic relies on. Detect that and
                    # fall back to the full original prompt.
                    has_count_signal = (
                        re.search(r"\b\d+\s+(?:@?test|bats)\b", task_desc, re.IGNORECASE)
                        or re.search(r"\btest_count\s*[:=]", task_desc, re.IGNORECASE)
                    )
                    if not has_count_signal:
                        task_desc = args.task
                    log(f"critique_test: {path} (task_desc={len(task_desc)}B)")
                    result = run_critique_test(path, task_desc, args.cwd)
                    if result["exit_code"] == 0:
                        # Clear the pending-critique flag for this path.
                        test_writes_pending_critique.discard(path)
                        tel["critiques_pass"] += 1
                    else:
                        tel["critiques_fail"] += 1
                exit_code = result["exit_code"]
                stdout = result["stdout"]
                stderr = result["stderr"]
                if stdout:
                    log(f"[stdout]\n{stdout.rstrip()}")
                if stderr:
                    log(f"[stderr]\n{stderr.rstrip()}")
                log(f"[exit] {exit_code}")
                messages.append({
                    "role": "tool",
                    "name": name,
                    "content": (
                        f"exit_code={exit_code}\n"
                        f"stdout={stdout}\n"
                        f"stderr={stderr}"
                    ),
                })
                continue

            log(f"unknown tool: {name}")
            messages.append({
                "role": "tool",
                "name": name,
                "content": "unknown tool",
            })

    log(f"\n(reached max turns {args.max_turns})")
    log(f"Total run: {time.time() - started:.1f}s")
    if args.telemetry:
        record_telemetry(args.cwd, args, tel, "max_turns",
                         args.max_turns, time.time() - started, args.task)
    return 1


if __name__ == "__main__":
    sys.exit(main())
