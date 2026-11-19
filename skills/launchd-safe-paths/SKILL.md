---
name: launchd-safe-paths
disable-model-invocation: true
description: >
  Write scripts that work in launchd's stripped PATH, and smoke-test them under a
  launchd-like env before you push. Use when adding or editing a LaunchAgent script
  or plist, when logs show "command not found", `ModuleNotFoundError`, or a wrong
  node version, or when a script must run from both a shell and launchd.
  Don't use for shell startup files (zshrc) or doctor checks.
---

**Agent contract:** Claude Code + ChatGPT Work/Codex; shared memory required when configured; regression: tests/user-stories.bats.

## The problem

launchd gives a job a minimal PATH: `/usr/bin:/bin:/usr/sbin:/sbin`, plus whatever the plist sets in `EnvironmentVariables`. Tools that your shell finds are missing there.

| Tool | Where your shell finds it | In launchd |
|---|---|---|
| `node` | fnm, nvm, or asdf install dir | not found |
| `python3` | Homebrew, uv, or a venv | the system python in `/usr/bin` (no packages) |
| `gh`, `jq`, `rg` | `/opt/homebrew/bin` | not found |
| `claude`, `opencode` | `~/.local/bin`, `~/.opencode/bin` | not found |

Symptoms: `command not found`, `ModuleNotFoundError`, a wrong node version, or a tool "missing" only in the job log.

## The fix

1. **Prepend the user bin dirs to PATH** at the top of the script: Homebrew, `~/.local/bin`, `~/.npm-global/bin`, `~/.opencode/bin`, and the fnm, nvm, or asdf node dir. Use `$HOME`, never a hardcoded path.
2. **Resolve version-sensitive tools by absolute path.** For python with venv packages, use the venv python. For node, put the version manager's dir first. Allow an env override and fall back to the bare name.
3. **Probe that the tool works, not only that it exists.** Example: `python -c 'import <pkg>'`, not `which python`. An existence-only check is a false pass.

## `${HOME}` in plists

launchd expands `${HOME}` in `Program` and `ProgramArguments`, but not in `StandardOutPath` or `StandardErrorPath`. A plist with `${HOME}/x.log` there makes launchd create a directory literally named `${HOME}` in the job's cwd.

Fix: render the plist at install time (chezmoi template, or `envsubst` with `${HOME}` in its allowlist). Do not rely on launchd to expand it.

## Smoke: run the script under a stripped env

Run this before you push any change to a LaunchAgent script or plist. Real integration tests often stub the very tools that fail in production.

```bash
# 1. The script under a launchd-like env: no shell rc, minimal PATH.

Follow the [agent workflow acceptance](../../docs/user-stories/README.md#agent-workflow-acceptance) before context-dependent work.
env -i HOME="$HOME" PATH=/usr/bin:/bin bash <script> <short-run-args>
```

Expect exit 0 and the log line you would see in production. A minimal PATH exposes missing tools. `set -u` exposes unset variables and empty arrays.

```bash
# 2. A background job stays alive (no GNU-only `sleep infinity` on macOS).
( bash <script> & ); sleep 1; pgrep -f <script> >/dev/null && echo alive
```

```bash
# 3. The rendered plist is valid.
plutil -lint <rendered.plist>
rg -n '\$\{?HOME' <rendered.plist>   # must print nothing: no unexpanded HOME
```

The smoke does not catch: bugs that need your real shell rc (it strips them on purpose), or real network and auth failures.

## Checklist for a new launchd-driven script

- [ ] First ~30 lines prepend the user bin dirs to PATH.
- [ ] Version-pinned tools resolve by absolute path or a helper.
- [ ] The plist is rendered at install time; log paths hold no `${HOME}`.
- [ ] A liveness probe checks the tool works.
- [ ] The stripped-env smoke above exits 0.
- [ ] `dotfiles-launchagent-drift --check` is clean after `dotfiles apply`.
