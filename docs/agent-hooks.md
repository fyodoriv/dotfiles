# Agent hooks and wrappers

This text moved here from `AGENTS.md` so the always-loaded file stays short. `AGENTS.md` keeps a summary and links here. The text is unchanged.

## Hook-based enforcement (post-2026-05-27)

`bin/gh` and `git-hooks/commit-msg` are **backstop** enforcement now. The
primary enforcement happens via agentbrew Claude Code hooks deployed to
`~/.claude/codeassist/hooks-scripts/` and wired into `~/.claude/settings.json`.

The Claude Code hooks fire ahead of the dotfiles wrappers — they catch
violations at the `PreToolUse` protocol layer, before the wrapper ever
runs. The wrappers stay because:

- Non-Claude shells (interactive zsh, scripts, manual `gh pr create`) bypass
  Claude Code's hook layer entirely. The dotfiles wrappers catch them.
- The wrapper's MUTATE logic (strip foreign attribution + append canonical
  Fyodor footer) is harder to express as a Claude Code hook (PreToolUse
  can't cleanly rewrite tool_input). The hook WARNS; the wrapper MUTATES.

`dotfiles/lib/strip-agent-attribution.sh` is the **single source of truth**
for the agent-attribution regex set. Both the dotfiles wrappers and the
agentbrew hooks source the same logic — `agentbrew/hooks/lib/strip-agent-attribution.sh`
is a copy maintained in sync via a CI lint (or manual update on drift).

The 8 deterministic hooks deployed today:
1. `code-no-timestamps` — blocks Write/Edit with `// YYYY-MM-DD` in source
2. `gh-pr-body-attribution` — warns on foreign attribution in PR body
3. `gh-pr-body-requires-rationale` — blocks PR body without Why/ticket
4. `git-commit-conventional` — enforces conventional commits on `-m`
5. `git-strip-agent-attribution` — warns on foreign attribution in `-m`
6. `no-git-add-all` — blocks `git add -A` / `.` / `-u` (multi-agent safety)
7. `no-force-push-protected` — blocks `git push --force` to main/master/develop
8. `no-commit-no-verify` — blocks `git commit --no-verify` (no bypass — iron rule)

See `agentbrew/hooks/manifest.yaml` for the canonical hook source and
`agentbrew/docs/research/deterministic-rules-via-hooks.md` for the
migration architecture.
