# agent-browser attach-first policy

This text moved here from `AGENTS.md` so the always-loaded file stays short. `AGENTS.md` keeps a summary and links here. The text is unchanged.

## agent-browser attach-first policy

Agent sessions should attach to the launchd-owned Chrome that matches the task instead of spawning a new Chrome instance by default:

| Port | LaunchAgent | Purpose |
|------|-------------|---------|
| `9223` | `com.dotfiles.agent-browser-chrome` | dashboard / general SSO |
| `9224` | `com.dotfiles.debug-chrome` | debug work |
| `9225` | `com.dotfiles.tooling-chrome` | tooling repo work |

The `home/zshrc.ai-tools` wrapper routes normal operator calls and dotfiles-assigned agent sessions to `agent-browser --cdp 9223` when the dashboard Chrome is reachable. Launchd Chromes run `--headless=new` so CDP tab create never opens a GUI window. After agent-browser, the wrapper logs suspected focus steals to `~/.local/share/dotfiles/logs/focus-steal.log` only — it never hides Chrome or `osascript activate`s another app (both can switch Spaces). Use `--headed` or `AGENT_BROWSER_ALLOW_FOCUS=1` when you want Chrome to stay frontmost for SSO. Preserve tab safety with per-agent daemons plus own-tab discipline: open your own tab, act only on tabs you opened, and close extra tabs at task end.

These three managed Chromes are `RunAtLoad` only, not `KeepAlive`: if the operator quits Chrome for logout/shutdown, launchd and `dotfiles doctor --fix` must not reopen it. Agents attach when a purpose Chrome is available; otherwise use the documented isolated/task-local browser modes.

Do not set `AGENT_BROWSER_PROFILE` to launchd-owned profiles under `~/.agent-browser/{chrome-profile,debug-profile,tooling-profile}`. Chrome ProcessSingleton forwards those launches into the existing browser and creates stray `chrome://newtab` windows; the wrapper delegates such profiles to `agent-browser-singleton-preflight` or refuses.

Use a separate browser only for true isolation, conflicting credentials, or visible human authentication in a separate window. In that case, choose a stable purpose-named session (`agent-browser --headed --session-name sso-<purpose> ...`), not a timestamp-unique session, and close it when done. For non-SSO task-local checks, use a throwaway browser with a random debugging port, never ports `9222`-`9225`.
