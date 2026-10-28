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
- The commit footer goes before a trailing git trailer block (`Task:`,
  `Signed-off-by:`), so git still reads those trailers. With no trailer
  block, the footer goes at the end.
  To check trailers like `git log` does, run
  `git interpret-trailers --parse --no-divider`: without the flag, git stops
  at the footer's `---` line and misses them.

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

## block-dangerous-git (dotfiles hook)

`agent-hooks/block-dangerous-git.sh` blocks `git reset --hard`,
`git clean -f`, `git checkout .`, `git restore .`, and the force-delete of a
local branch. A force-delete passes only when every named branch is proven
merged:

1. The branch tip is the head commit of a merged PR (`gh pr list --state merged`).
2. The tip is already an ancestor of the default branch.
3. The whole branch diff is already on the default branch as one commit (same
   stable patch-id), which is the squash-merge case.

Order of proofs: the cheap local ones (ancestor, patch-id) run first; `gh` is
asked only for branches they do not prove. The default branch's last 200 patch
fingerprints are computed once per hook run, however many branches are named.
`gh`'s answer is saved first and then searched, so a long answer (over 64 KB)
still proves a merged PR.

The hook reads the command as words, not as literal text. A `git` call counts
as a force-delete when its subcommand is `branch` and the flags mean delete
without a merge check: `-D`, `-d` with `-f`, `--delete` with `--force`, glued
letters such as `-fd` or `-Dr`, in any order, before or after the branch name.
Global options before the subcommand are understood: `-C <dir>` and
`--git-dir[=]<dir>` move the proof into that repo. `-c`, `--work-tree` and any
other global option block. Only plain delete flags are allowed: a glued extra
letter such as `-Dr` blocks, because `-r` would delete remote-tracking refs.
Git reads any unambiguous prefix of a long option, so `--del` and `--forc` count
as `--delete` and `--force` (3 letters or more). Before matching, the hook drops
quotes and backslashes and strips the path from the `git` word, so `'git'`,
`g''it`, `\git`, `/usr/bin/git`, `git 'branch'` and `-d '-f'` are all seen as a
force-delete; the strict parser then rejects every such form, so they block. An
in-command alias (`git -c alias.b=branch b -D x`, `--config-env`) counts as a
force-delete too and blocks.

Each branch word must match `^[A-Za-z0-9._/-]+$` and not start with `-`. Braces,
quotes, `$`, globs, `@{}`, `^`, `~` and the like block. The branch must exist as
`refs/heads/<name>` (checked with `git show-ref --verify`). The default branch
is read from `origin/HEAD`; its target must start with `refs/remotes/origin/`,
and it must not have the name of the branch to delete, or the hook blocks. Any
`;`, `&`, `|`, newline or backslash after the flag blocks, so a chained command
never hides a second delete. A command before the flag, or a second flag, also
blocks. `git branch` is matched in any letter case. A trailing `2>&1`,
`2>/dev/null`, or `>/dev/null` is ignored only as its own word. The merged-PR
proof counts only PRs into the default branch (`--base`). `gh` runs under
`gtimeout` or `timeout`: one call gets `DOTFILES_GH_TIMEOUT` (default 10 s) and
all calls together get `DOTFILES_GH_BUDGET` (default 15 s), then the PR proof
fails closed. With neither binary the PR proof is skipped (a perl alarm cannot
stop `gh`). A non-repo folder blocks.

Known gaps (the same as before this change; none is newly allowed):
- The hook matches the flag text anywhere in the command line, so a heredoc or
  file body that only mentions it is blocked.
- A command before the delete (`git checkout main && git branch -D x`) is
  blocked, because a `cd` could change the repo the proof must check. Run the
  delete as its own command.
- Forged default ref: `git update-ref refs/remotes/origin/main <local branch>`
  forges the default ref itself, and `git symbolic-ref refs/remotes/origin/HEAD
  refs/remotes/origin/<x>` points it at a forged `refs/remotes/origin/<x>`. The
  hook cannot detect either offline.
- A shell alias, function or wrapper that runs `git branch` under another name
  never shows the word `git` to the hook.
- Other commands that delete or overwrite a branch are not checked at all:
  `git update-ref -d refs/heads/<b>`, `git push . :<b>`, `git branch -M <x> <b>`,
  and `git branch -f <b> <x>` over an unmerged branch. Tracked as
  `git-ref-delete-other-commands` in `TASKS.md`.

Tests: `tests/agent-hooks-block-dangerous-git.bats`,
`tests/agent-hooks-block-dangerous-git-merged.bats`.

## require-heavy-run (dotfiles hook)

`agent-hooks/require-heavy-run.sh` is a `PreToolUse` Bash hook from the
dotfiles Agentfile. It blocks full test suites and builds that do not start
with `heavy-run`: `npm test`, `npm run test*`, `yarn`/`pnpm` test or build
scripts, `vitest`/`jest` with no file argument, `playwright test`, and `bats`
on a folder. It also blocks the other headless-browser entry points:
`e2e*` and `ui*` package scripts, `npm exec`/`pnpm exec`/`yarn playwright test`,
and `make e2e`, `make test-all`, or `make test-force` (`make -n` passes). It checks each part of a `&&`, `||`, `;`, or `|` chain.
Single-file and single-test runs (`npx vitest run one.test.ts`, `bats tests/x.bats`,
`pnpm ui -g login`, `playwright test tests/one.spec.ts`) pass. It also reads
`pnpm --filter <pkg> e2e`, `pnpm dlx`, and `bunx playwright test`.
Set `HEAVY_RUN_HOOK=off` to turn it off. Tests:
`tests/agent-hooks-require-heavy-run.bats`.

The doctor check `resilience.headless_chrome_under_heavy_run` is the safety
net for runs the hook cannot see (a plain `node script.js` that starts
Chrome). `bin/headless-chrome-unlocked` counts headless Chrome main
processes with no `heavy-run` parent; the check warns above
`HEADLESS_UNLOCKED_MAX` (default 3). Why: the 2026-10-27 checkup found
`chrome-headless-shell` on top of the overload rows. A launcher that starts
Chrome itself must also pass `--use-mock-keychain --password-store=basic`.

The hook strips the prefixes `time`, `timeout`, `env`, `sudo`, `nice`, `nohup`, `caffeinate`,
`command`, and `exec` (with their own flags), reads `if`/`while`/`then`/`do` bodies, `( ... )`
and `{ ...; }` groups, and `$(...)` or backticks inside double quotes. A `-g`, `--grep`, `-t`, or
`--testNamePattern` filter, or a spec path, marks a one-test run; the value of any other flag
(`--output out/res`) does not.

Also read: `npx`/`bunx`/`npm exec`/`pnpm dlx`/`bun x` with flags and version suffixes
(`npx -y playwright@1 test`), program paths (`./node_modules/.bin/playwright test`),
`bun` and `turbo` scripts, `gmake`, the string after `bash -c` or `sh -c`, and a `$(...)` or
backtick sitting inside a word (`make -j$(nproc) e2e`). A string after `bash -c` is read as a
command of its own, so `bash -c "heavy-run make e2e"` passes.

After `exec`, `dlx`, or `x`, the program is read like a plain command (`pnpm exec vitest`,
`bun x vitest`, `pnpm exec turbo run test`). `timeout 600`, `nice -n 5`, `caffeinate -i`, and
shell flags with values (`bash -euo pipefail -c`) may come before `bash -c`.

Still not seen by the hook: `yarn workspace <pkg> <script>`, a single spec run through `turbo`
with `--filter` (it reads as a full run), a program started by a script (`node run.js`), and `eval`.
The doctor check is the net for these.
