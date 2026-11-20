# Agent hooks and wrappers

This text moved here from `AGENTS.md` so the always-loaded file stays short. `AGENTS.md` keeps a summary and links here. The text is unchanged.

## Hook-based enforcement (post-2026-05-27)

`dotfiles hook-native install` builds the status shortcut offline and enables
it for the dangerous-Git guard. `dotfiles hook-native rollback` restores the
shell guard. The guard checks the binary digest before use and blocks if a
selected native execution cannot provide a valid completion receipt. Other
commands fall back to the existing guard. Fallback input is stored locally in
an owner-only temporary file, unlinked before it is written and closed on exit.

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

The managed `git` wrapper also enforces Rule 9 on direct agent commits.
It refuses `--no-verify`, `-n`, and a command-local `core.hooksPath` of
`/dev/null` before Git runs. `git-safe` uses the same check when it delegates
to the managed wrapper. Push approval does not waive the commit rule.

When a Claude Code Bash session opts in to Agentbrew's Git script guard,
Dotfiles shell startup keeps that managed guard first on PATH. Allowed
calls still pass through the Dotfiles Git wrapper. If the system Git
probe fails, the fallback skips the Agentbrew guard and looks for Git.
If the Claude command hook rewrites PATH, the session marker lets the
Dotfiles wrapper ask the managed guard for a decision. Dotfiles still
runs each allowed Git operation once.

## block-dangerous-git (dotfiles hook)

The guard blocks missing, empty, or malformed command input. It reports a clear
error instead of allowing an unparsed command to proceed.

The guard uses `shfmt` to recognize one plain `cat` text write or display.
Only its wholly quoted heredoc bodies are masked before command checks.
Shell consumers, pipelines, arithmetic, unquoted substitutions, special-file
outputs, and commands after a heredoc keep the conservative checks. The
deployment script links the syntax filter beside the hook. A missing parser
or failed proof also keeps the original command. Homebrew installs `shfmt`
on both profiles.

For one fixed branch, literal Python document, add, and commit sequence, the
guard checks each proven command boundary separately. It still checks the
Python body and commit message. Unknown syntax or a missing checker keeps the
original conservative check.

The guard recognizes one literal comparison between the current branch and a
pull request's head branch. It can stand alone or start an `&&` chain. The
shell parser must prove the first condition's boundary before the branch
scanner omits that comparison. The remaining commands still go through the
guard. If the parser is unavailable or the comparison differs, the existing
decision applies. Separate metadata lookups also work.

The Git-guard suite keeps multiline command samples in fixture files. Hosted CI
also runs the suite as a standalone Bats invocation so its parser and complete
test count are checked independently of the affected-test runner.

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
as `--delete` and `--force`: any prefix of `delete` (`--d`, `--de`), and 4 letters
or more for `force` (`--fo` and `--for` clash with `--format`). Before matching, the hook drops
quotes and backslashes and strips the path from the `git` word, so `'git'`,
`g''it`, `\git`, `/usr/bin/git`, `git 'branch'` and `-d '-f'` are all seen as a
force-delete; the strict parser then rejects every such form, so they block. An
in-command alias (`git -c alias.b=branch b -D x`, `--config-env`) counts as a
force-delete too and blocks.

Three more commands that destroy a branch are checked with the same proof, in
the repo the command acts on (a branch that does not exist yet has nothing to
lose and passes):

- `git update-ref [-d] refs/heads/<b> [<value>]`: `<b>` must be proven merged.
  Other refs (tags, `refs/stash`, notes) pass. Any `refs/remotes/` ref blocks,
  as does `--stdin`, a command with no `refs/` first word, or a value that is
  not a plain revision.
- `git push . :<b>` (or `:refs/heads/<b>`): `<b>` must be proven merged. Any
  other refspec to `.` (such as `<src>:<b>`) blocks. A push to a remote is not
  looked at.
- `git branch -M <x> <b>` (or `-m` with `-f`): the old tip of `<b>`, the last
  name, must be proven merged. `git branch -f <b> <x>` (or `--force`): the old
  tip of `<b>`, the first name, must be proven merged.

A command the shell rewrites before git runs (`$'git'`, `$'-D'`, `${x:--D}`,
`$(echo git)`, backticks, or a glob in the path such as `/usr/bin/gi?`) that
also names `branch` or `update-ref` and a delete-like flag counts as a match
and then blocks, because the parser reads only plain words. A rewritten
subcommand (`git $'branch' -D x`, `git $(echo branch) -D x`) with a delete-like
flag after it is a match too. A rewritten word that could expand to a flag
(`${x}`) counts only outside a read-only listing (`--list`, `-l`,
`--show-current`, `--contains`, `--merged`, `--no-merged`, `--points-at`), so
`git branch --list ${x}` passes. A plain `$var` or `$(...)` in an ordinary
`git branch` command is not a match.

The branch scanner can set aside an exact leading comparison of
`$(git branch --show-current)` with a literal branch name, plain or in single
quotes. It also accepts that comparison immediately after a plain `set -e`
line. The shell parser must confirm the complete condition. The scanner still
checks the remaining command and keeps the conservative result for uncertain
forms.

For a literal branch list or containment query, the shell parser can prove
where that invocation ends. The guard reads the other commands separately
from that query. It keeps the conservative result when the parser cannot
prove a boundary.

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
  is blocked (the hook refuses any `refs/remotes/` write), but other ways to
  forge it are not seen: `git symbolic-ref refs/remotes/origin/HEAD
  refs/remotes/origin/<x>`, `git branch -r`, or editing `.git` files directly.
- A shell alias, function or wrapper that runs the command under another name
  never shows the word `git` to the hook.
- Other ways to rewrite a branch are not checked: `git reset` on a checked-out
  branch, `git checkout -B`, `git switch -C`, `git fetch <remote> +<src>:<b>`,
  `git push <path> :<b>` to this repo by path, and `git update-ref --stdin`
  (blocked, but only because it cannot be parsed).
- The shell-rewrite check needs `branch` or `update-ref` and a delete-like flag
  in the same command; a rewritten `push` (for example `$(echo git) push . :b`)
  is not seen.

Tests: `tests/agent-hooks-block-dangerous-git.bats`,
`tests/agent-hooks-block-dangerous-git-merged.bats`.

## block-local-tests (dotfiles hook)

`agent-hooks/block-local-tests.sh` is a `PreToolUse` Bash hook from the
dotfiles Agentfile. Owner decision 2026-11-16: "Lint local, tests on CI". Inside
a dotfiles checkout or worktree it refuses `bats`, `bin/bats-affected`,
`make check`, `make test`, `make test-*` and `make e2e` (also behind `heavy-run`,
`time`, `nice`, `env`, `bash -c`, `cd <checkout> &&` and `make -C <checkout>`). It
exits 2 and tells the agent to run `make lint`, push, and read CI
(`gh pr checks <n> --watch`, `gh run view <id> --log-failed`).

- A checkout is a folder, or a parent of the session folder, that holds both
  `agent-hooks/require-heavy-run.sh` and `bin/dotfiles-doctor`. Other repos are
  not affected.
- Allowed: `make lint*`, `shellcheck`, `bash -n`, `make -n`, `bats --version`,
  and read-only commands such as `rg bats`. Quoted text (a commit message that
  names `make check`) is data.
- It also reads `xargs` (with its flags, including `-I{}`, `--replace`,
  `-R`, `-S` and `--max-chars`), `find ... -exec/-execdir`, `npx`, `bunx`,
  `npm exec`/`npm x` and `pnpm exec`/`pnpm dlx` (also after global flags such
  as `--prefix`), and `eval` as launchers of the command they start. The
  quoted string after `npx -c` or `npm exec -c` is read as a command.
- It is a guardrail against mistakes, not a security boundary. It fails open:
  with no `plutil` or `perl`, malformed input, or a stripped `PATH` it allows
  the command. Known gaps: a command name built at run time (`$(which bats)`)
  and a script piped to a shell (`echo make check | sh`). Known false
  blocks: a launcher flag value read as the command
  (`npx --package bats -- eslint .`) and `bash -c` or `npx -c` text quoted
  inside a commit message. A command that is
  in a dotfiles checkout by session folder and also `cd`s elsewhere still
  blocks.
- It applies to Claude Code and Codex, because both run the PreToolUse hooks
  from this Agentfile.
- `DOTFILES_ALLOW_LOCAL_TESTS=1` turns the hook off. It works only when you
  export it before you start Claude or Codex: the hook reads its own
  environment, so an agent that writes the variable inside a command still gets
  blocked. A human's own terminal has no hook, so tests run there as usual.
- CI is not affected: hooks run only inside an agent session, and hosted
  runners start no agent.

Tests: `tests/agent-hooks-block-local-tests.bats`.

## require-heavy-run (dotfiles hook)

The heavy-run controller creates private queue records. A wrapped program
receives its caller's file-creation mask, including inside exclusive and
already-held runs. Set the mask explicitly before calling heavy-run when
the program's output must stay private.

`agent-hooks/require-heavy-run.sh` is a `PreToolUse` Bash hook from the
dotfiles Agentfile. It blocks full test suites and builds that do not start
with `heavy-run`: `npm test`, `npm run test*`, `yarn`/`pnpm` test or build
scripts, `vitest`/`jest` with no file argument, `playwright test`, and `bats`
on a folder or wildcard. Bats can run one named file or use `-f` or
`--filter` with named files. It also blocks the other headless-browser entry points:
`e2e*` and `ui*` package scripts, `npm exec`/`pnpm exec`/`yarn playwright test`,
and `make e2e`, `make test-all`, or `make test-force` (`make -n` passes). It checks each part of a `&&`, `||`, `;`, or `|` chain.
Single-file and single-test runs (`npx vitest run one.test.ts`, `bats tests/x.bats`,
`pnpm ui -g login`, `playwright test tests/one.spec.ts`) pass. It also reads
`pnpm --filter <pkg> e2e`, `pnpm dlx`, and `bunx playwright test`.
Rust compilation (`cargo build`, `test`, `check`, `clippy`, `bench`, `run`,
`rustc`, and direct `rustc`) must queue, including filtered Cargo tests.
Unknown Rust tool invocations also refuse. Only the bounded version, help,
metadata, project-location and sysroot inspection forms in the
[caller coverage contract](plans/queue-caller-coverage.md) pass unwrapped.
The exact `verify` package script must queue even with a filename argument.
Project gate scripts must queue too: `check.sh` (any mode but `inputs` and
`--help`), `e2e.sh`, and `public-readiness.sh --first-run`, also through
`bash`, `nice`, or `VAR=x` prefixes. `batch-gate.sh` queues itself and passes.
`pytest` (also as `uv run pytest`, `uvx pytest`, or `python -m pytest`) must
queue when it runs in parallel (`-n N` with N above 0) or names no test file
and no `-k` filter. One or more named `.py` files without `-n` pass. Added
after the 2026-11-15 freeze: a gate run under `nice -n 15` outside the queue
beside another heavy job, and the Mac had to be forced off.
Read-only discovery passes unwrapped: `command -v` or `command -V` (also with
`-p`) followed only by literal names and output redirections such as
`>/dev/null 2>&1`, and a lone `bats --version`, `-v`, `--help`, or `-h`.
A probe chained to a suite (`command -v bats && bats tests/`), a probe with a
command substitution, and `command` without a lookup flag still refuse.
The lookup allowance holds only for a top-level probe whose output feeds
nothing. A probe inside `$(...)`, backticks, `sh -c`, or `eval` text refuses,
and so does any probe when the command has a pipe (`|`, `|&`) or a process
substitution (`<(...)`, `>(...)`), as in `command -v cargo | xargs -I{} {} build`.
One narrow alternative passes: `rg --no-config -- 'term' "$(command -v bats)"`,
optionally with `-n` or `-l` before `--` and an initial `command -v bats &&`.
The term uses only letters, numbers, underscores, dots, or hyphens. Searches
without either safety flag and forms with extra shell syntax still refuse.
The hosted runner-search fixture shows why the original search needs both
flags. A configured ripgrep preprocessor can run a command when it opens
the named file. `--no-config` disables the configured preprocessor and `--`
keeps the search term separate from command options.
Literal quoted Rust executable paths are recognized at a bare command boundary;
inert documentation strings remain ignored. Each hook invocation owns only
its input text and decision. This does not prove queue ownership or cover
commands launched through other channels.

Set `HEAVY_RUN_HOOK=off` to turn it off. Tests:
`tests/agent-hooks-require-heavy-run.bats` and
`tests/agent-hooks-heavy-build-callers.bats`.

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

## PATH hook output

`prepend-endpoint-path.sh` recognizes Codex hook input by its nonempty
`turn_id`. Native Codex `PreToolUse` calls for shell execution use `Bash` and
`tool_input.command`. The hook returns `hookSpecificOutput` with
`hookEventName: PreToolUse`, `permissionDecision: allow`, and an
`updatedInput.command` when it adds PATH or rewrites a managed shim.
Unchanged Codex input gets native allow without an input update. Claude
Code uses its native `updatedInput` response when the envelope includes
the PreToolUse event, permission mode, and a transcript path. The hook
retains Claude's other tool arguments and leaves the approval decision to
Claude. SessionStart writes the managed PATH to the Claude-provided
`CLAUDE_ENV_FILE` for the Mac shell. The write preserves an active
Agentbrew Git guard at the front of PATH. In accept-edits, don't-ask,
and bypass-permissions modes, Bash keeps its original command unless it names a tool with an
explicit shim rewrite. Those rewrites still use the managed shim. Default,
auto, Codex, and legacy PreToolUse replies follow their existing routes.

The hook preserves explicit `/usr/bin/python3` and `/usr/bin/python3.13`
paths in commands and literal text. Use an explicit path when the
interpreter matters. A bare Python command still uses the managed PATH.

The response is based on the [Codex hooks protocol](https://learn.chatgpt.com/docs/hooks).
Input detection and temporary output files are scoped to one hook process.
The temporary plist is removed before the response is printed.

## heavy-run and Mac freezes

`heavy-run` defaults to 1 slot. Four parallel slots froze the owner's Mac twice
(2026-11-01): suites pass the memory check at start, then grow together. A frozen Mac shows
`force_off` in `/Library/Logs/DiagnosticReports/ResetCounter-*`. With more slots, two limits
apply. One project (a repo and its worktrees) holds at most `heavy_run_project_slots` (3).
The memory guard stops every run but the oldest while memory pressure is high, so the
oldest finishes and frees memory; the rest go on when pressure clears.

A game stream (GeForce NOW 2.0.90) next to heavy runs crashed it 5 times the same day
(WindowServer watchdog panic). So `heavy-run` holds every run while an app in
`HEAVY_RUN_PAUSE_APPS` runs (default `GeForceNOW`): no new run starts, and a running one
gets SIGSTOP until the app quits. Set `HEAVY_RUN_PAUSE_APPS=""` to turn it off.

The periodic jobs `dotfiles-sync`, `tooling-sync` and `agent-scratch-prune` use the same
list through `lib/realtime-hold.sh`: while a listed app runs, each skips its run and prints
`skipped: <app> is running`; the next interval retries. On 2026-11-15 a `git` process at
about six cores ran beside GeForce NOW and the stream lagged. `DOTFILES_REALTIME_HOLD=0`
turns this skip off; `tooling-sync --force` ignores it. Two differences from
`heavy-run`: if the `pgrep` probe fails, the job runs (heavy-run holds), so a broken probe
never stops syncing; and names are split on commas without trimming, so write
`GeForceNOW,Steam`, not `GeForceNOW, Steam`.

Each controller caches the app check for at most two seconds. A successful
check must return process IDs, or report no matches with no output. A failed,
missing or invalid check holds new runs with `real-time app probe unavailable`.
It also keeps existing real-time pause marks until a valid check reports no
matching app. This applies to the first run, exclusive runs and added parallel
runs. It does not change the configured slot limits.

One scheduler decides for the whole queue. Every `heavy-run` process tries for the
leader lock `sched.lock`; the holder reads the settings live and writes a grant or a wait
reason per ticket, and the pause marks. So `dotfiles config set heavy_run_slots N` reaches
every waiter within about a second. Waiters from an older `heavy-run` keep their place in
line: new processes hold the gate ticket `queue/0000000000-0`, and the scheduler opens it
for one older waiter at a time when its turn comes. Never kill waiters to make them pick up
new code or settings: their callers get exit 143.

Project identity readers accept existing raw project fields and typed
`project_id=sha256:...` fields. Each controller keeps its selected raw project
and normalized identity for that invocation. Running owners, queued tickets
and pending grants use the same normalized key when applying the project cap.
Missing, invalid or duplicate identity in a live record holds new grants with
`queue project metadata unavailable` until valid metadata can be read.

This is reader preparation only. New owners and tickets still write the raw
project in its existing field and append `reader=project-id-v1`. Owner line
three stays the numeric `start=` used by memory ordering, and tickets keep
`kind=v2` for the existing scheduler. Raw command and folder metadata remains;
this release does not complete the privacy change.

Do not enable opaque writers while strict older controllers can still make
admission decisions or lead the scheduler. A source-file update does not
replace code already loaded in those processes. The reader marker helps a
future rollout guard identify compatibility; it does not itself authorize
that rollout. Existing live records belong to the controller holding their
kernel locks. Never rewrite another controller's live records.

To trace a freeze, read `~/.local/state/dotfiles/load-samples.tsv` first: it survives a forced
power-off. `dotfiles-load-sampler report` counts kernel-stall rows (high load with a low CPU-busy
column).
