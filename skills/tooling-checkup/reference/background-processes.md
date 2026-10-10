# Background processes (Phase 5)

## Collect

```bash
bash <skill-dir>/scripts/background_audit.sh
pgrep -fl '(^|/)claude( |$)'                  # open Claude Code sessions
```

The script lists every plist in `~/Library/LaunchAgents`,
`/Library/LaunchAgents`, and `/Library/LaunchDaemons`, with an owner and a
verdict. Then it lists the top processes by CPU and by memory, and the load.

Login items are not plists. Check them with
`sfltool dumpbtm` (needs `sudo`, so ask the user to run it) or in
System Settings > General > Login Items. Report them; do not change them.

## Decide

| Verdict | Owner | Action |
|---|---|---|
| `remove` | any | Program is gone. Ask the user, then disable (below). |
| `duplicate` | tooling | Two jobs run the same command. Fix in the source repo. The rule is one LaunchAgent per job. |
| `duplicate` | third-party | Ask the user which one to keep. |
| `off-rule` | minsky | A minsky job is loaded. Minsky must never start on its own. Unload it now, then check `~/.minsky/autostart-enabled` is absent. |
| `failing` | tooling | Read its log (`StandardErrorPath` in the plist). Fix the cause in the source repo, or file a task. |
| `failing` | third-party | Report it. Ask the user if the app is still in use. |
| `review` | third-party | Updaters and helpers of apps. Ask only about jobs for apps the user may not use. Leave Apple, security, and VPN tools alone unless the user asks. |
| `keep` | any | Nothing to do. |

Tooling-owned jobs (`com.dotfiles.*`, `com.agentbrew.*`, `com.minsky.*`,
`com.taskgrind.*`) come from their source repo. Change the template there and
deliver it with `/ship-it`. Never edit or delete their installed plist by hand:
the next apply puts it back.

A heavy process is a lead, not a verdict. Name it with its CPU, memory, and
uptime. Common causes on this kind of Mac:

- Spotlight (`corespotlightd`, `mds_stores`) indexing large trees such as
  `node_modules` or worktrees. Dotfiles has Spotlight exclusions; check them.
- Many open Claude Code sessions. Each one is a full Node process.
- An MCP server that restarts in a loop.

## Disable a third-party job (only after the user says yes)

Disable is reversible. Never delete a plist.

```bash
label=<label>
plist=<path from the audit>
stash="$HOME/.local/state/tooling-checkup/disabled-launchd/$(date +%Y%m%d)"
mkdir -p "$stash"
launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true   # user agents
mv "$plist" "$stash/"
```

For `/Library/LaunchAgents` and `/Library/LaunchDaemons`, the user must run
the commands with `sudo` (`launchctl bootout system/<label>` for daemons).
Give them the exact lines. Put each one in the report.

To restore: move the plist back and run
`launchctl bootstrap "gui/$(id -u)" <plist>`.

If the app re-creates the job, the app needs a setting change or removal.
Ask the user.
