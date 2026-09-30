# Local-AI loop session retro (2026-05-11, 7 PRs)

## Scoreboard

| PR | Title | What landed |
|----|-------|------------|
| #14 | dogfood loop closes 1 P2 + 2 bug fixes | First end-to-end dogfood, surfaced verifier shebang false-positive + loop TASKS.md ownership |
| #15 | hard guards + mock-Ollama fixture | DENY_BASH (kill/pkill/launchctl), $HOME-write block, HTTP 500 retry, done precondition, tests/fixtures/mock-ollama.py |
| #16 | per-task telemetry CSV | docs/audits/local-ai-runs.csv, --telemetry flag, 14 columns |
| #17 | tighten done gate to make-check only + per-task cleanup | Loop reverts uncommitted changes between failed tasks; gate rejects narrow `bats tests/*.bats` |
| #18 | self-critique blocks hallucinated stubs | New `critique_test` tool catches placeholders, tautologies, missing anchors; required before done |
| #19 | critic anchor-filter + destructive-overwrite guard | Test's own path no longer "required anchor"; `write_file` refuses large→tiny overwrites |

5 dogfood runs over the course of the session. Each run found new failure modes; each next PR landed permanent guardrails.

## Numbers

- **84 local-AI bats tests** (up from ~25 at session start), all passing.
- **23 failure modes** captured in `docs/audits/local-ai-failure-modes.md` (loaded into the agent's system prompt at every run).
- **Telemetry CSV** at `docs/audits/local-ai-runs.csv` — accumulates per-run rows for trend analysis.
- **Median speed**: 75-82 tok/s on qwen3-coder:30b warm (M3 Max).

## Architecture (what's running)

```
bin/local-ai-loop  →  reads TASKS.md, picks P0/P1/P2 unblocked tasks
   ↓ (per task)
bin/local-ai-agent --telemetry
   ↓
lib/local-ai-agent.py (system prompt + failure-modes file)
   ↓ tools
   bash      — gated by DENY_BASH regex (kill/pkill/launchctl/...)
              and HOME_WRITE regex (no bats writes to $HOME)
   write_file — atomic via tmp+rename, refuses large→tiny overwrites
   verify_cli_claims — scans doc for bin/<name> refs, runs --help, parses flags
   critique_test — scans bats files for placeholders / tautologies /
                   missing context anchors
   done       — refused if pending critique OR if make check hasn't passed
                since last write_file
   ↓
On `done`:  loop closes TASKS.md block + commits + appends CSV row
On rc!=0:   loop reverts tracked file changes via `git checkout HEAD --`
            and deletes untracked files in safe prefixes
            (PRESERVES docs/audits/local-ai-runs.csv)
```

## Lessons that became code

Each entry below started as a recurring agent mistake and became a hard guard:

1. Kill / pkill / launchctl bootout / docker stop — agent has no service ownership.
2. Writing $HOME / ~/.config from a bats test heredoc — would clobber developer state.
3. Hallucinated CLI flags in docs — verify_cli_claims parses declarations.
4. `done` called with failing tests — precondition requires passing `make check`.
5. Agent gaming the gate with `bats tests/<one-file>.bats` — only `make check` counts.
6. Failed-task leftovers polluting next task — loop reverts on failure.
7. Telemetry CSV deletion in cleanup — PERSIST_PATHS allowlist.
8. Placeholder / TODO / "would require" comments in tests — critique_test signal #1.
9. Tautological assertions (`export X="foo" && [ "$X" = "foo" ]`) — critique_test signal #2.
10. Tests that don't reference the task description's file paths or quoted literals — critique_test signal #3.
11. Test's own path counted as a required anchor — discard the write target.
12. Destructive overwrite of large tracked file — `run_write_file` refuses <25% size ratio when target is >100 lines.

## What still needs a human

After 5 dogfood runs, the agent CANNOT YET autonomously complete these tasks (all blocked at max_turns by the new guards — which is the correct outcome):

- `cover-devin-model-three-layer-consistency-test` — needs cross-repo introspection. Agent doesn't have a tool to read cross-repo files.
- `doctor-opencode-tools-auto-fix` — needs to write a JSON-edit fix mode in the doctor module. The agent kept getting HTTP 500s on Ollama under the long context. Need to figure out why Ollama 500s on sustained traffic.
- `ci-gate-verify-counts` — needs to extend `git-hooks/pre-commit` (the destructive-overwrite guard now prevents the wrong shape of fix).

These are good follow-ups for another session — or for a stronger model than qwen3-coder:30b.

## How to resume

```bash
cd ~/apps/dotfiles
make check                            # baseline (everything green)
./bin/local-ai-loop --max-tasks 3 --deadline 30m
                                      # next dogfood run
tail -5 docs/audits/local-ai-runs.csv # see the telemetry rows
```

Or for a single task experiment:
```bash
./bin/local-ai-agent --max-turns 14 --telemetry "task prompt here"
```

If the agent's behavior shifts in a way you want to remember:
```bash
bin/local-ai-record-lesson  # appends to docs/audits/local-ai-failure-modes.md
                            # which is loaded into the next agent system prompt
```
