# Claude Code input latency in Ghostty (Phase 6)

The goal: keys typed into Claude Code appear fast. Measure before you change
anything. Claim a gain only with before and after numbers from this session.

## Measure

Run from a trusted project directory (for example `$TOOLING_ROOT`). Starting
`claude` elsewhere shows the folder-trust prompt, and the prompt takes the keys.

```bash
cd "$TOOLING_ROOT"
for run in 1 2 3; do
  uptime
  python3 <skill-dir>/scripts/echo_latency.py --settle 1 -- zsh -f
  python3 <skill-dir>/scripts/echo_latency.py --settle 10 -- claude
done
```

Each line gives `median_ms`, `p95_ms`, `max_ms`, and `timeouts`. Report the
median of the three runs for each value. `zsh -f` is the floor: the terminal
and the machine without Claude Code. When the shell is slow too, the cause is
the machine (load), not Claude Code.

The harness types into a pty, not into Ghostty. It measures Claude Code and
the machine. Ghostty's own render time is not in the number.

Run-to-run noise is large on a busy Mac. A change counts only when the claude
p95 moves more than the spread between the three runs.

## Collect the likely causes

```bash
pgrep -fl '(^|/)claude( |$)' | wc -l                 # open sessions
ls -l ~/.claude.json                                   # config size
ls ~/.claude.json.tmp.* 2>/dev/null | wc -l            # orphaned temp files
uptime                                                 # load average
jq '.statusLine // empty' ~/.claude/settings.json      # status line command
cat ~/.config/ghostty/config                           # owned by dotfiles
```

## Levers, in order of measured effect

1. **Fewer open sessions.** Several sessions share `~/.claude.json` and lock
   it. Debug logs show "Lock acquisition took longer than expected" and event
   loop stalls of seconds. Ask the user how many sessions they need open.
2. **Machine load.** A load average far above the core count slows every
   key. Phase 5 finds what drives it (often Spotlight indexing).
3. **Orphaned `~/.claude.json.tmp.*` files.** Move them, do not delete them:
   `mkdir -p ~/.local/state/tooling-checkup/claude-json-tmp && mv ~/.claude.json.tmp.* "$_"/`
   Only do this when no session is writing (no new tmp file in the last minute).
4. **A large `~/.claude.json`.** Report its size. Do not edit it by hand;
   Claude Code rewrites it. Ask the user before you clear project history.
5. **A slow status line command.** It runs on many redraws. Time it alone.
   A fix goes in the dotfiles or agentbrew source, not in `settings.json`.

Toggles that did not move the numbers in earlier tests: `--bare`,
`--strict-mcp-config`, the fullscreen renderer, the classic renderer. Do not
recommend them without new numbers.

Ghostty settings change only through the dotfiles source
(`dot_config/ghostty/`). Test one change at a time, and keep it only if the
numbers improve.

## Record

At the end of the checkup, store the numbers so the next run can compare:

```bash
python3 <skill-dir>/scripts/checkup_state.py record --verdict "<verdict>" \
  --metric claude_echo_median_ms=<n> --metric claude_echo_p95_ms=<n> \
  --metric shell_echo_p95_ms=<n> --metric claude_sessions=<n>
```
