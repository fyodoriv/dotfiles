---
name: update-tooling
description: >
  Safely refreshes tooling repositories, applies the current dotfiles and
  AgentBrew configuration to this machine, verifies machine health, and ranks
  the next AgentBrew and dotfiles tasks. Use when the user says "update latest
  tooling", "update my tools", "fetch latest tools", "update tooling",
  "install all updates", or "bring my tooling current". Do not use for normal
  feature work in one named repository; use ship-it for that.
---

# Update tooling

Refresh the machine without overwriting another person's work. A tooling
update is more than `agentbrew sync --pull`: source repositories, the applied
dotfiles checkout, and generated agent configuration each need separate care.

## Outcome and boundaries

Complete these outcomes in order:

1. Refresh safe primary tooling checkouts from their configured remotes.
2. Apply the refreshed dotfiles and agentbrew state to this machine.
3. Prove the relevant machine checks are healthy or report exact blockers.
4. Recommend the highest-impact next work in agentbrew and dotfiles.

The default refresh does not commit, rebase, force-push, delete worktrees,
open pull requests, or upgrade third-party packages. Those
actions need their own explicit request or an active `/ship-it` session.

Do not use the legacy `bin/tooling-sync` for this interactive workflow. Its
separate background contract can commit and push task changes, while this skill
must preserve unowned work and report it.

Do not assume remote hosts or default branches. Read each checkout's configured
`origin` and `origin/HEAD`. This supports enterprise origins, GitHub origins,
and forks without embedding host-specific rules.

Why this is a local skill and not an upstream tool: topgrade's `git_repos`
step and `chezmoi update` (`git pull --autostash --rebase`) do not skip and
report dirty or diverged checkouts. Decision and re-check triggers:
`docs/plans/replace-relocate-update-tooling-orchestration.md`.

## 1. Inventory every checkout

Start with the current project context in every repository you inspect. Then
set the root once:

```bash
export TOOLING_ROOT="${TOOLING_ROOT:-$HOME/apps/tooling}"
```

Inspect only direct child primary checkouts. A linked worktree has a `.git`
file, so it is intentionally excluded by the directory test below. Do not
pull applied checkouts, scratch worktrees, or nested repositories directly.

```bash
agentbrew_updated=false
for repo in "$TOOLING_ROOT"/*; do
  [ -d "$repo/.git" ] || continue
  git -C "$repo" fetch --all --prune
  git -C "$repo" status --short --branch
  git -C "$repo" worktree list --porcelain
done
```

For every checkout, record:

- path, remote URL, branch, and upstream;
- dirty or untracked files;
- ahead/behind state;
- linked worktrees; and
- fetch failures.

If a checkout is dirty, has no upstream, is on a non-canonical branch, is
ahead, or is diverged, fetch only. Treat any `git status --porcelain` output,
including untracked files, as dirty. Preserve it for its owner. Do not use
`git pull --rebase`, `git reset`, `git checkout .`, `git clean`, or a force
push during this workflow.

### Clean up local branches and stashes

After the inventory, apply `docs/ship-it-reference.md` Step 9 § "Local
branches and stashes" to every checkout. Delete only branches and stashes
with a recorded proof; keep and report the rest.

## 2. Fast-forward only clean canonical checkouts

For a clean primary checkout, choose the pull remote and derive the canonical
branch instead of guessing:

```bash
PULL_REMOTE=origin
if ! git -C "$repo" remote get-url "$PULL_REMOTE" >/dev/null 2>&1; then
  PULL_REMOTE="$(git -C "$repo" remote | awk 'NR == 1 { print; exit }')"
fi
[ -n "$PULL_REMOTE" ] || { echo "no remote: $repo"; continue; }
remote_ref="$(git -C "$repo" symbolic-ref --quiet --short "refs/remotes/$PULL_REMOTE/HEAD" 2>/dev/null || true)"
canonical_branch="${remote_ref#"$PULL_REMOTE/"}"
current_branch="$(git -C "$repo" branch --show-current)"
upstream="$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
```

Only update when all of these are true:

- the worktree is clean;
- `current_branch` equals `canonical_branch`;
- `upstream` equals `$PULL_REMOTE/$canonical_branch`; and
- `git rev-list --left-right --count "HEAD...$upstream"` reports zero local
  commits and one or more remote commits.

Then use only:

```bash
before_oid="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" merge --ff-only "$upstream"
after_oid="$(git -C "$repo" rev-parse HEAD)"
if [ "$repo" = "$TOOLING_ROOT/agentbrew" ] && [ "$before_oid" != "$after_oid" ]; then
  agentbrew_updated=true
fi
```

If the selected remote's `HEAD` is absent, the branch is not canonical, the
upstream does not match, or the checkout is not a fast-forward, report the
reason and leave it unchanged.

## 3. Apply the refreshed tooling safely

### agentbrew

`agentbrew sync --pull` refreshes managed sources and generated agent
configuration. It does not update the agentbrew repository itself.

The applied AgentBrew checkout is normally `$TOOLING_ROOT/agentbrew`, a
read-only clone whose `dist/cli.js` the global `agentbrew` command resolves
to. It can be detached. Refresh it separately from any development clone. Do not assume the global
`agentbrew` command resolves there; record its actual target and use the
applied CLI explicitly after a successful build. It is safe to advance only
when the applied checkout is clean and its detached `HEAD` is an ancestor of
`origin/main`:

```bash
AGENTBREW_APPLIED="${AGENTBREW_APPLIED:-$TOOLING_ROOT/agentbrew}"
ENDPOINT_NODE_SAFE_MODE=false
[ -e "$HOME/.local/state/dotfiles/endpoint-node-publisher-blocked" ] \
  && ENDPOINT_NODE_SAFE_MODE=true
if [ ! -e "$AGENTBREW_APPLIED/.git" ]; then
  echo "preserved applied AgentBrew checkout: not a git checkout"
elif ! git -C "$AGENTBREW_APPLIED" fetch origin main; then
  echo "preserved applied AgentBrew checkout: fetch failed"
elif [ -n "$(git -C "$AGENTBREW_APPLIED" status --porcelain)" ]; then
  echo "preserved applied AgentBrew checkout: dirty"
elif ! git -C "$AGENTBREW_APPLIED" merge-base --is-ancestor HEAD origin/main; then
  echo "preserved applied AgentBrew checkout: ahead or diverged"
elif ! git -C "$AGENTBREW_APPLIED" diff --quiet HEAD origin/main; then
  git -C "$AGENTBREW_APPLIED" merge --ff-only origin/main
  if $ENDPOINT_NODE_SAFE_MODE; then
    echo "deferred applied AgentBrew build: endpoint Node safe mode is active"
  else
    (cd "$AGENTBREW_APPLIED" && heavy-run npm run build)
  fi
else
  echo "applied AgentBrew checkout is current"
fi
```

Do not force, reset, rebase, or check out the detached applied checkout. If its
state is not a clean fast-forward, report it and leave it unchanged. Record
`command -v agentbrew`. If it does not point at
`$AGENTBREW_APPLIED/dist/cli.js`, report the mismatch and do not silently use
that other build. After a successful build, set:

```bash
APPLIED_AGENTBREW="$AGENTBREW_APPLIED/dist/cli.js"
test -x "$APPLIED_AGENTBREW"
GLOBAL_AGENTBREW="$(command -v agentbrew 2>/dev/null || true)"
if [ "$GLOBAL_AGENTBREW" != "$APPLIED_AGENTBREW" ]; then
  printf 'global agentbrew differs from applied build: %s (expected %s)\n' \
    "${GLOBAL_AGENTBREW:-not found}" "$APPLIED_AGENTBREW"
fi
```

The endpoint safe-mode sentinel is
`$HOME/.local/state/dotfiles/endpoint-node-publisher-blocked`. When it exists,
skip the build and apply-time AgentBrew sync because they would execute blocked
Node automation. Do not invoke `agentbrew` to inspect the catalog in this mode.
Instead compare the static catalog and global Agentfile with a non-Node YAML
reader, then report every catalog skill missing from `skills:`:

```bash
if command -v yq >/dev/null 2>&1; then
  skill_compare_dir="$(mktemp -d)"
  yq -r '.skills[].name' "$AGENTBREW_APPLIED/src/catalog.yaml" | sort -u > "$skill_compare_dir/catalog"
  yq -r '.skills[]' "$HOME/.config/agentbrew/Agentfile.yaml" | sort -u > "$skill_compare_dir/configured"
  comm -23 "$skill_compare_dir/catalog" "$skill_compare_dir/configured"
  rm -rf "$skill_compare_dir"
else
  echo "cannot compare catalog skills safely: yq is unavailable"
fi
```

Do not infer missing skills from generated agent directories. After safe mode
is cleared, build the advanced applied checkout if needed, then link the
configured skills with:

```bash
env -u DOTFILES_DIR "$APPLIED_AGENTBREW" sync --only skills --no-recommended --agentfile "$HOME/.config/agentbrew/Agentfile.yaml"
# Equivalent when the global command resolves to this applied build:
# env -u DOTFILES_DIR agentbrew sync --only skills --no-recommended --agentfile "$HOME/.config/agentbrew/Agentfile.yaml"
```

When the sentinel is absent, run the normal sync from `$HOME` or another
directory without a project Agentfile:

```bash
cd "$HOME" && env -u DOTFILES_DIR "$APPLIED_AGENTBREW" sync --pull --no-recommended --agentfile "$HOME/.config/agentbrew/Agentfile.yaml"
```

Always pass `--no-recommended --agentfile`, as the dotfiles lifecycle does. A
bare `agentbrew sync` also installs every catalog skill marked `recommended`,
including skills the Agentfile removed, which brings back duplicates.

Use the dotfiles `agentbrew` shim when it resolves to the applied build. Do not
edit generated agent configuration directories directly.

### Dotfiles

Keep the development and applied checkouts separate. The applied checkout is
the one returned by `chezmoi source-path`.

The `dotfiles-sync` LaunchAgent runs `chezmoi apply` every 30 minutes and
holds the chezmoi state lock while it runs. Then `chezmoi source-path` fails
with "timeout obtaining persistent state lock" and prints nothing. Wait for
that run to end (up to 5 minutes) before you read the path, and stop if it is
still empty:

```bash
for _ in $(seq 60); do pgrep -qf '^chezmoi apply' || break; sleep 5; done
DOTFILES_APPLIED="$(chezmoi source-path)"
[ -n "$DOTFILES_APPLIED" ] || { echo "chezmoi source-path failed; is chezmoi still locked?"; exit 1; }
CHECKED="$DOTFILES_APPLIED/bin/dotfiles-lock-checked"
env -u DOTFILES_DIR "$CHECKED" -- "$DOTFILES_APPLIED/bin/dotfiles-sync"
cd "$HOME" && env -u DOTFILES_DIR "$CHECKED" -- "$DOTFILES_APPLIED/bin/dotfiles" apply --if-changed
env -u DOTFILES_DIR "$DOTFILES_APPLIED/bin/dotfiles-reload-launchagents"
```

A dotfiles command that finds the dotfiles lock taken prints
`[lock] Skipping` or `[lock] Timed out` and still exits 0. Never count that
as applied. `dotfiles-lock-checked` runs the command, finds those lines,
waits for the lock owner, and re-runs it (3 tries, 60 s apart by default). It
exits 75 when the lock never frees: report that step as "not applied" with
the lock owner from the output. Do not go on to the next apply step as if it
ran.

The applied-checkout helper only fast-forwards and reapplies chezmoi. Never
run an applied-checkout update against a dirty or diverged worktree.

Run the explicit apply after the helper intentionally. One refresh runs
`chezmoi apply` at most once (`tests/update-tooling-apply-count.bats` counts
the runs):

- The helper re-applies only when the fast-forward brought commits, its last
  apply failed, or `chezmoi status` shows drift. A successful re-apply writes
  the last-apply record. Its output says `chezmoi re-applied` or
  `skipped chezmoi apply`.
- `dotfiles apply --if-changed` then finds that record and skips. When the
  helper did not apply (its apply failed, or it left a dirty checkout
  untouched), the explicit apply converges the current manifest.

Do not add a second plain `dotfiles apply` to this step. If both commands
apply in one refresh, a drift line survived the helper's apply: chezmoi
cannot converge that file (for example, another program rewrites it). Report
that line as drift to fix in the source.

`--if-changed` makes the explicit apply cheap when nothing changed. It skips
`chezmoi apply` and the doctor pass (about 200 s) when both are true:

- the source commit, chezmoi config, and plugin lock match the last
  successful full apply (by `dotfiles apply` or `dotfiles-sync`), and the
  source checkout has no uncommitted change; and
- `chezmoi status --exclude=always` prints nothing (no hand-edited, missing,
  or pending file, and no changed `run_onchange_` script).

Then it prints `skipped chezmoi apply and doctor`, and the step 4 doctor
modules check the rest of the machine. Otherwise it prints why, including
each drift line, and runs the full apply. Report each drift line. Use plain
`dotfiles apply` when the user asks for a full apply or a step 4 check
fails. If apply asks for a noninteractive drift confirmation, such as a
missing TTY, do not use `--force`. Preserve the live file and report the
drift for source reconciliation.

### LaunchAgents

Only `$DOTFILES_APPLIED` may mutate or reload Home LaunchAgents. The PATH
repair records which jobs were loaded before it edits a plist, never starts an
unloaded job, keeps `com.minsky.*` off without its opt-in marker, and leaves
Node-backed jobs alone while endpoint safe mode is active. The separate
`dotfiles-reload-launchagents` command is an explicit post-apply reload of its
declared release whitelist; use it only from `$DOTFILES_APPLIED`, not as a
general repair command.

After the apply step, check that launchd runs what the plists say (#297):

```bash
"$DOTFILES_APPLIED/bin/dotfiles-launchagent-drift"
```

It prints one line per `com.dotfiles.*` job: `ok`, `drift` (the loaded job
runs other arguments than its plist), `stopped` (a KeepAlive job is not
running), or `unloaded`. A job disabled in launchd is off on purpose and
skipped. When it prints anything but `ok`, run it again with `--fix` from
`$DOTFILES_APPLIED`: it reloads a drifted job, kickstarts a stopped one, and
bootstraps an unloaded one. Report each fixed and each remaining line.
Reloading the agent Chrome (`com.dotfiles.agent-browser-chrome`) restarts it;
its profile and sign-ins stay.

Do not run `dotfiles update`, `dotfiles-upgrade`, Homebrew upgrades, or package
manager upgrades unless the user explicitly asks to upgrade third-party
software. Those operations have a wider and less reversible machine impact.

### Codex CLI

Always run `codex --version`, `codex login status`, and
`dotfiles doctor --full --module codex` after refresh. A synced `~/.codex` folder does
not prove the executable works. Report sign-in failures without reading auth
files. When package upgrades are explicitly requested, run
`bash "$DOTFILES_APPLIED/bin/dotfiles-install-codex" --upgrade`, then compare
`codex --version` with `npm view @openai/codex version`. The helper re-links
`~/.local/bin/codex` to the selected npm prefix. Do not use ChatGPT.app's
bundled CLI as the terminal CLI or install the discontinued `codex-app` cask.

## 4. Verify machine stability

Run these checks after the apply. Capture actual output and separate owned
failures from environment or authorization blockers.

```bash
if $ENDPOINT_NODE_SAFE_MODE; then
  echo "skipped AgentBrew runtime checks: endpoint Node safe mode is active"
else
  cd "$HOME" && env -u DOTFILES_DIR "$APPLIED_AGENTBREW" status --ci \
    || env -u DOTFILES_DIR "$APPLIED_AGENTBREW" status --fix
  cd "$HOME" && env -u DOTFILES_DIR "$APPLIED_AGENTBREW" status --ci
  env -u DOTFILES_DIR "$APPLIED_AGENTBREW" mcp probe --deep
  env -u DOTFILES_DIR "$APPLIED_AGENTBREW" measure context
fi

env -u DOTFILES_DIR "$DOTFILES_APPLIED/bin/dotfiles" doctor --module agentbrew \
  --module terminal --module agent-browser --module chrome --module resilience \
  --module security --fix
env -u DOTFILES_DIR "$DOTFILES_APPLIED/bin/dotfiles-heal-stuck-agents" --fix --quiet

curl -sf --max-time 2 http://127.0.0.1:9223/json/version && echo CDP9223=ok
```

When Minsky is installed, verify its opt-in autostart state remains off:

```bash
test ! -e "${MINSKY_STATE_DIR:-$HOME/.minsky}/autostart-enabled"
! launchctl list | rg -qi 'minsky'
```

If a check needs authentication, preserve the evidence, follow the active SSO
protocol, and continue independent checks. Do not call the machine stable until
the remaining failure is classified as fixed, intentionally skipped, or blocked.

## 5. Recommend the next work

Read the current queue from the refreshed remote branch for both
`$TOOLING_ROOT/agentbrew` and `$TOOLING_ROOT/dotfiles`. Also read
`RECURRING.md` when present, but include a recurring task only when its cadence
is due.

Do not claim, edit, or complete a task while making recommendations. Exclude
P3 work unless the user explicitly authorizes it. Exclude blocked human-only
work unless it is the only route to restore a failed stability check.

Rank candidates with this order:

1. A live safety, data-loss, or stability failure observed in this refresh.
2. Work that restores the self-healing or cross-agent sync promises in the
   repository vision.
3. Work that unblocks several higher-priority tasks or removes an active
   manual recovery step.
4. Other unblocked P0 or P1 work. Consider P2 only when it has a clear,
   measured machine impact.

Return at most three recommendations. For each, include the repository, task
ID, priority, concrete evidence, why it outranks alternatives, dependencies,
and the first verification command. Do not hard-code task IDs in this skill;
the queue is the source of truth.

## 6. Report

End with a published Artifact, not chat text and not a loose HTML file
(shared-rules **## Long-run reports**). Only without the Artifact tool, write
one self-contained HTML file under `~/.local/state/update-tooling/` and give
its path. Then ask in chat which next work to start, with the options from
the Artifact. Paths show as `~/…`; no secrets. Build it from this outline:

```markdown
## Repository refresh
- Updated: …
- Skipped safely: …
- Fetch failures: …

## Machine delivery
- agentbrew: …
- Dotfiles: …
- LaunchAgents: …

## Stability
- Passing: …
- Fixed: …
- Blocked or environmental: …

## Recommended next work
1. `<repo>/<task-id>` — why now; first verification.
2. …
3. …
```

If `/ship-it` is active, deliver only the current-session or verified
user-owned changes through its full branch, pull-request, CI, merge, and
machine-refresh protocol. Do not treat a routine repository refresh as
permission to publish unknown work.
