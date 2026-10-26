# Config hygiene: duplicates, memory, hooks, new skills (Phase 7)

The script checks in `config-audit.md` find broken files. This pass keeps
the whole agent setup small and true: each fact in one home, no stale memory,
hooks that still work, and no new skill that repeats one the user already has.

## Back up first

Before any edit to rules, settings, skills, or memory, copy them to
`~/.local/state/tooling-checkup/backups/checkup-YYYY-MM-DD/` (`CLAUDE.md`,
`settings.json`, the memory folder, and personal skills; skip folders an app
manages). Do not put backups under `~/.claude/`: Claude Code keeps its own
backups there.

Never prune backups by yourself. When more than four `checkup-YYYY-MM-DD`
folders exist, list the older ones in the Phase 11 questionnaire. Delete
only folders with that exact name, and only after the owner's yes.

## Ask before you delete

Never delete memory, rule, or skill files without the owner's yes.

- Editing a stale fact in place is fine.
- Collect every proposed deletion or merge of a memory, rule, or skill file.
  Put them in the Phase 11 questionnaire as one batch, with the backup path.
- Act on the batch only after the owner says yes.

## One home per fact

For each rule, skill section, and memory, ask: is this its one right home?

| Kind of fact | Home |
|---|---|
| Applies to every task | the always-loaded rules source (shared rules, `AGENTS.md`) |
| A procedure with steps | a skill, linked from the rules in one line |
| Applies to some files only | a path-scoped rule |
| Who the user is, a decision, a pointer | a memory entry |
| Must never break | a hook, with the prose as the reason |

- Search for the same instruction in two places (`rg -n '<key phrase>'`
  across the rules, skills, and memory folders). Keep the best home. Propose
  replacing the other copy with a one-line pointer, or deleting it, in the
  Phase 11 batch.
- Propose merging skills whose jobs overlap in the Phase 11 batch. After
  the owner's yes, update every reference to the renamed or removed skill.
- Propose moving multi-step procedures out of always-loaded files into
  skills, in the Phase 11 batch.
- When two places contradict each other and the intent is unclear, ask in the
  Phase 11 questionnaire. Do not guess.

## Memory hygiene

Skip this when the agent keeps no file memory.

- Re-check each memory that names a file, flag, version, branch, or state.
  Edit a stale fact in place. When the whole memory is no longer true,
  propose its deletion in the Phase 11 batch.
- Propose merging duplicate memories, and deleting a memory that only
  restates a rule or a skill, in the Phase 11 batch.
- The memory index has exactly one line per memory file, and every line
  points to a file that exists.
- Remove answered items from any open-questions memory. This is an edit in
  place, not a file deletion.
- Dates are absolute ("2026-10-25", not "yesterday").

## Hooks

For each hook in the agent settings: does it still run, and is it still
wanted? Pipe-test it with a sample event:

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"echo hi"}}' | <hook command>; echo "exit $?"
```

A hook that errors on every call, or guards a rule that no longer exists, goes
to the questionnaire. Never change hooks or permissions without the user's yes.

## New upstream skills

After `agentbrew sync --pull` (Phase 3), find new skills by name. The
installed skills are symlinks, so their dates do not show updates. Diff
today's list against the list the previous run saved, then save today's:

```bash
state=~/.local/state/tooling-checkup; mkdir -p "$state"
ls ~/.claude/skills | sort > "$state/skills-now.txt"
if [ -f "$state/skills-last.txt" ]; then
  comm -13 "$state/skills-last.txt" "$state/skills-now.txt"
else
  cat "$state/skills-now.txt"   # first run: every skill is new
fi
```

After you review the new skills, save the list for the next run:
`mv "$state/skills-now.txt" "$state/skills-last.txt"`. If the run stops
before the review, do not save it. For each new one:

- Compare its description with the user's own skills. Two skills must not
  claim the same triggers.
- When a new skill covers a personal skill, propose a thin wrapper or the
  removal of the personal copy in the questionnaire.
- When a personal skill holds a generally useful step the upstream skill
  lacks, file it as a fix or task PR to that skill's source repo.

## Best-practice log

When a source page in `config-audit.md` changed a rule, note the date and the
change in one line in the report, and update the audit script or this file in
the same PR.
