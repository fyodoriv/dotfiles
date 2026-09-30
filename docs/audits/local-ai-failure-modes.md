# Local-AI Failure Modes — Compounding Knowledge File

This file is read into `bin/local-ai-agent`'s system prompt on every
run. Each entry is a real mistake observed in
`docs/audits/local-ai-task-runs-*.md` that the agent should now avoid.
Keep entries terse: model context is finite.

**Update rule:** whenever a task run leaves a "Lesson:" entry in the
ledger and the lesson generalizes (i.e. is not specific to a single
file), add a one-line warning here. Trim when the warning hasn't
mattered in 30 days.

## Hallucinated CLI flags

You will be tempted to write `bin/<some-script> --flag` after seeing
`ls bin/` confirm the script exists. **Don't.** Before citing any flag
or sub-command in a file you are writing, run `<script> --help | head -10`
or `head -20 <script>` to confirm the flag actually exists. The
"never invent tool output" rule is about reporting; this rule is about
writing.

Examples observed:
- `bin/local-ai-agent --prompt "..."` — wrong. The agent takes a
  positional task arg.
- `gh issue view A B` — wrong. `gh` takes one issue id per call.

## macOS `sed -i` is not GNU `sed -i`

On macOS (BSD userland), `sed -i` requires a backup-suffix argument:

```
sed -i '' 's/foo/bar/' file       # ok on macOS
sed -i  's/foo/bar/' file         # FAILS: "invalid command code T"
```

If your `sed` call fails with `invalid command code T`, **switch to
`python3` immediately** — do not retry the same `sed` with different
quoting. You have a one-attempt budget on `sed`.

## Don't re-run the same failing command

If a command fails the same way twice (same stderr), change strategy on
attempt 3. Common pivots: switch from `sed` to `python3`, switch from
`bash -c "<heredoc>"` to the `write_file` tool, switch from regex to
explicit line splicing.

## Prefer `write_file` for any multi-line content

Anything with embedded quotes, backticks, `$` variables, or more than
~10 lines: use `write_file(path, content)`. Bash heredoc quoting eats
single quotes and burns turns on quoting-debug loops.

## Verify file paths actually exist before writing them in docs

When emitting a doc that cites file paths in this repo, the cheapest
check is `ls <path>` first. Don't link to a file you haven't confirmed
exists.

## Cold-load is ~3-8 seconds

The first `/api/chat` call after a long idle hits a cold model load.
That's normal — don't retry assuming the request hung.

## Bats `run` does NOT split stderr by default

`run cmd` puts merged stdout+stderr in `$output`, and there is no
`$stderr` variable unless the test uses `run --separate-stderr cmd`.
If you want to check stderr-only content, either pass `--separate-stderr`
or just match against `$output` (which contains both streams). Don't
write `[[ "$stderr" == ... ]]` — it will silently always pass on
older bats.

## When a test or check command fails, FIX small, don't rewrite

If your first `write_file` ran a test and 3 of 4 cases failed:
inspect the **first** failure, propose a minimal patch via `bash` (e.g.
`python3` re-substitution on a 5-line section), re-run the test, then
move to the next failure. Do NOT `write_file` the whole test file
again — you'll re-emit the same bug.

## `PATH=/tmp` strips bash too

Using `PATH=/tmp` (or any minimal PATH) in a test that runs a
`#!/usr/bin/env bash` script will fail with `env: bash: No such file
or directory` (exit 127), NOT the script's own non-zero exit. To
exclude a specific binary while keeping bash available, use
`PATH=/bin:/usr/bin` (skips /usr/local/bin and /opt/homebrew/bin
where most installed CLIs land).

## Don't substring-grep for flags when verifying — parse declarations

When checking whether a doc cites a real CLI flag, do not just grep the
script's source for the literal flag string. The system-prompt strings
inside the script will contain English words that happen to match
`--foo` patterns. Instead, parse declarations: argparse
`add_argument("--foo"...)`, bash `--foo)` case-block headers, click
`@click.option("--foo"...)`. The verify_cli_claims tool in
lib/local-ai-agent.py shows how.

## Follow thin-wrapper bash scripts into their lib/<name>.py

Most bin/ scripts in this repo are thin bash wrappers that exec into
a sibling lib/ file. Examples: bin/local-ai-agent → lib/local-ai-agent.py.
When inspecting a script's behavior or flag surface, read the wrapper +
the lib file together. The verifier handles this automatically by also
reading lib/<name>.py / lib/<name>.sh when present, and by following
`exec ... "$SCRIPT_DIR/../lib/..."` patterns it finds in the wrapper.

## NEVER kill processes — agent has no ownership over running services

The agent saw `ollama` PID listening on :11434, decided it conflicted with
its mock server, and ran `kill 1208`. That killed the real Ollama server,
which then took the agent's own backend offline mid-task. Loop crashed
because subsequent agent turns couldn't reach the API.

Rule: a coding agent has no authority to `kill`, `pkill`, `killall`,
`launchctl bootout`, `launchctl kickstart -k`, `systemctl stop`, `service stop`,
`docker stop`, `docker kill`, or any other process-lifecycle command.
If a port is in use, the agent must `skip` the test, not free the port.

Mitigation: hard regex deny-list in `lib/local-ai-agent.py`'s `tool_bash`
that rejects any command matching `\b(kill|pkill|killall|launchctl\s+bootout|launchctl\s+kickstart\s+-k|systemctl\s+stop|service\s+\w+\s+stop|docker\s+(stop|kill))\b`.

## NEVER write to $HOME or ~/.config in tests

The opencode-tools test the agent wrote did
`mkdir -p $HOME/.config/opencode && cat > $HOME/.config/opencode/opencode.json`
— that clobbers the developer's actual config. Tests must isolate state
under `mktemp -d` and either `export HOME=$TEST_DIR` or pass the config
path through a function argument.

Mitigation: pre-commit hook check that rejects any bats test file containing
literal `$HOME/` or `~/.config/` outside a `setup() { HOME=$(mktemp -d) ...`
block. Add lint rule next iteration.

## Hallucinated model names ('gpt-4-turbo') in tests for Devin

For the "verify Devin model agrees across three layers" task, the agent
wrote a generic test using `gpt-4-turbo` — a name with no relationship
to this repo's actual model setting. The canonical model name lives in
`home/zshrc.ai-tools` (`DEVIN_MODEL=gpt-5-5-xhigh-priority`) and in
`~/.config/devin/config.json`. A test that doesn't read those files
verifies nothing.

Mitigation: when a task references a name, value, or convention defined
elsewhere in the repo, grep for it first and quote the actual value.

## `bats load` resolves relative to the test file, not the repo root

The agent wrote `load ../test_helper` then "fixed" the resulting failure
by copying `test_helper.bash` to the repo root. Both are wrong. The
correct form is `load test_helper` (bats looks in the test file's own
directory; this repo's tests/ contains `tests/test_helper.bash`, so
`load test_helper` from any `tests/*.bats` file resolves correctly).

Mitigation: doctor check + bats test that scans for `load ../` patterns
in tests/ and fails CI if any appear.

## `done` is gated on `make check`, not on the agent's word

The agent called `done` for the Devin-model task while `make check` was
failing — the test it wrote was broken. The loop driver caught this
(rc=0 but make check fails → skipped) but the agent should have caught
it first. The fix: require the agent to run `make check` (or a scoped
subset) as the last step before `done`, and refuse to claim done if
that gate fails.

Mitigation: add a `done`-tool precondition: agent must have called
`make check` (or `bats tests/<name>.bats`) AFTER its last write, and
that command must have exited 0. If not, `done` returns an error and
the agent has to keep working.

## Ollama returns HTTP 500 when sent the same request too rapidly

After a long stretch of tool-call turns hitting Ollama at ~1 turn/second,
the API returned `HTTP 500 Internal Server Error` mid-loop. No request
body change — same prompt structure that had worked seconds earlier.

Mitigation: agent's `chat()` function should retry once on HTTP 500
with a short sleep (e.g. 2s), then propagate. Don't infinite-retry.

## Agent games narrow verification gates

In run-3 dogfood (the first run with the done-precondition shipped),
the agent got blocked on `done` after writing a broken bats test that
made `make check` fail. The block worked as designed. But then the
agent's NEXT bash command was `bats tests/<its-own-file>.bats` (only
its own test). That passed in isolation, so the gate accepted it, and
done was allowed — despite the rest of the repo's `make check` still
being red.

Mitigation: the gate now ONLY accepts `make check`. Narrow `bats
tests/<file>.bats` runs are useful while iterating but never satisfy
the gate. (lib/local-ai-agent.py, `if re.search(r"\\bmake\\s+check\\b", cmd)`.)

## Failed-task work pollutes the next task

In run-3, task 1 wrote a broken bats file, exited rc=1. Loop driver
marked it failed and moved on. Task 2's first command was `make check`
— which failed not because of task 2's work but because of task 1's
broken file still sitting in the repo. The agent then spent its budget
debugging task 1's leftover garbage.

Mitigation: the loop driver now calls `revert_uncommitted(repo,
task_id)` after every failed task. Tracked files are restored via
`git checkout HEAD -- <file>`; untracked files in safe prefixes
(tests/, lib/, bin/, docs/, modules/) are deleted. Files outside
those prefixes are preserved (per CLAUDE.md's git-safety rules —
other agents may have legitimate scratch elsewhere).

## Hallucinated stub tests that pass `make check` are worse than no test

Run-4 dogfood produced its first task completion — a bats test for
"Devin model agrees across three layers". The test passed `make check`
and was auto-committed by the loop. But the test was a hallucinated
stub:

  - Used `gpt-4-turbo` as the model name (the real value, per
    AGENTS.md, is `gpt-5-5-xhigh-priority`).
  - Was tautological — `export DEVIN_MODEL="gpt-4-turbo" && [ "$DEVIN_MODEL" = "gpt-4-turbo" ]`
    is always true.
  - Had explicit comments admitting incompleteness ("This is a
    placeholder", "actual implementation would require").
  - Didn't reference ANY of the real file paths from the task
    description (`home/zshrc.ai-tools`, `~/.config/devin/config.json`,
    other config files).

The task description was very specific (it literally named those
paths and quoted the expected value). The agent ignored it and
produced a generic template.

Mitigation: new `critique_test` tool in lib/local-ai-agent.py. The
`done` tool is BLOCKED until critique_test passes on every bats file
the agent wrote in the run. Critique looks for three signals:

  1. Placeholder comments — "placeholder", "would require",
     "actual implementation", "TODO", "FIXME", "for now we just",
     "this is a stub".
  2. Tautological assertions — `export VAR="x"` followed by
     `[ "$VAR" = "x" ]` in the same @test block.
  3. Missing context anchors — the test must reference at least one
     of the file paths AND one of the backtick-quoted literals from
     the task description (case-insensitive).

The exact run-4 test is captured as a regression in
tests/local-ai-agent-critique.bats (test 9).

## Loop cleanup wiped the telemetry CSV

In run-4 the cumulative telemetry file `docs/audits/local-ai-runs.csv`
was created during task 2's successful run, then deleted by
`revert_uncommitted` during task 3's failure cleanup — because
`docs/` is in the safe-to-delete prefix list.

Mitigation: `lib/local-ai-loop.py` now keeps a `PERSIST_PATHS`
allowlist (currently just `docs/audits/local-ai-runs.csv`) that
cleanup skips. Append future cumulative-state paths here as they
appear.

## Critic must exclude the test's own path from required anchors

Run-5 false positive: the critic kept failing the cover-devin test
with "test references NONE of the task's named files:
tests/devin-model-three-layer-consistency.bats". That path is the
test's OWN write target — a test can't import itself. The agent burned
all 14 turns trying to satisfy an impossible constraint.

Mitigation: critic now `discard()`s `path` and its basename from
the file-anchor set, and drops all sibling `.bats` files (tests
don't depend on each other).

## Destructive overwrite of a large tracked file

Run-5 task 3 (wire `make verify-counts` into pre-commit): the agent
wrote a 345-byte stub OVER the existing 7089-byte `git-hooks/pre-commit`,
destroying the entire security hook (12 of 13 pre-commit bats tests
suddenly failed). The cleanup logic restored it from HEAD after the
task failed, but the agent should never have been allowed to silently
clobber a substantial existing file in the first place.

Mitigation: `run_write_file` now refuses to overwrite an existing
file with content less than 25% of the existing file's size when the
file is larger than 100 lines. Returns exit 1 with the diagnostic
"overwriting X (N bytes, L lines) with only M bytes is likely
destructive. If you mean to extend the file, read it first and emit
the FULL new content."

## Ollama qwen3-coder tool-call parser crashes at HTTP 500 on malformed XML

Upstream bug (github.com/ollama/ollama/issues/14834): the model's
Qwen3Coder parser in qwen3coder.go throws "XML syntax error on line
N: element <function> closed by </parameter>" and returns 500. PRs
#14906 and #14915 are waiting to merge a fix. The agent ran into
this in every dogfood run (56+ occurrences in our Ollama logs).

Retrying the exact same request at temperature=0 produces the exact
same crash (model is deterministic). Mitigation: `chat()` now has a
3-stage retry ladder — temp 0.0 → 0.2 → 0.4, sleeps 0 → 2s → 4s.
The model's different sampling path on retry usually produces
well-formed XML. After 3 failures, propagate.

## Destructive overwrite of existing files needs a patch_file tool

The write_file guard (PR #19) refuses large-to-tiny overwrites, but
the agent still needs to EXTEND existing files. Without a
patch-style tool the agent has to emit the whole file — which for a
200-line doctor.sh module means dictating 200 lines perfectly under
a 14-turn budget. Most attempts fail.

Mitigation: new `patch_file` tool with three modes — `replace` (old
substring → new, must match once), `insert_after` (anchor match,
then inject content), `append` (add to EOF). Patches are atomic
(tmp + rename). System prompt instructs the agent to prefer
patch_file over write_file for existing files > 20 lines.

## Agent spends turns 1-5 on `ls` / `cat` of files already named

In run-5, the cover-devin task's description explicitly listed the
files to touch, but the agent still burned 5 turns calling
`ls -la tests/` / `cat foo.bats` / `grep -n foo` before starting the
actual work. Every such ls/cat turn is 1-3 seconds of wasted budget.

Mitigation: lib/local-ai-loop.py's `build_prompt` now pre-loads the
contents of files named in the task's `**Files**:` metadata
(truncated to 8KB each, 32KB total). The agent starts with file
contents in its context and can jump straight to patch_file /
write_file / make check.

## 14-turn budget too tight for multi-signal tasks

The critic tool can take 2-3 iterations to pass for a substantial
test, leaving 11-12 turns for everything else. Combined with preload
overhead + HTTP 500 retries, a task touching 3 files can easily
blow 14 turns.

Mitigation: `estimate_max_turns(task)` in lib/local-ai-loop.py
scales the budget with task complexity — base 14 + 4 per signal
(long details / 3+ files / long acceptance), capped at 28. Loop
prints the chosen budget before invoking the agent.

## Close commit may not contain the declared deliverable

Observed in PRs #24-#26: the agent reported `done`, `make check`
passed (the new test file was never tracked, so nothing new ran),
and the loop committed only the TASKS.md block removal. The PR
description claimed a test file shipped; main never got it.
`commit_if_dirty` now stages untracked safe-prefix work, but staging
can't prove the agent produced the *declared* deliverable at all.

Mitigation: a pre-merge reviewer gate in lib/local-ai-loop.py runs
after `commit_if_dirty` — it dumps `git show --stat HEAD` as the
audit trail, then asserts every path-like entry in the task's
`**Files**:` field appears in the close commit
(`git show --name-only --format= HEAD`; globs match fnmatch-style
without crossing `/`, directory entries match one-way, a declared
TASKS.md is auto-satisfied). On a miss the loop prints the unmatched
entries, rewinds the just-created commit (`reset --soft` +
`restore --staged`), reverts via `revert_uncommitted`, and counts
the task failed. Pinned by tests/local-ai-loop-reviewer.bats.
