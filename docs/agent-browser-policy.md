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

These Chromes run the real `Google Chrome.app`, so macOS registers them as `com.google.Chrome`. With your own Chrome closed, a Dock click, Cmd-Tab, or `open -a "Google Chrome"` can bring a headless one to the front. It has no window, so Chrome looks stuck. `com.dotfiles.chrome-dock-guard` (`bin/dotfiles-chrome-dock-guard`, source `lib/chrome-dock-guard.swift`) watches the frontmost app and hands that click to your own Chrome: it raises it, or starts it with `open -n -a`. A headless Chrome turns frontmost without posting `didActivateApplicationNotification`, so the guard observes `NSWorkspace.frontmostApplication` too. It hands off only when that agent Chrome has no on-screen window. A headed agent Chrome (for example one left open so you can finish a sign-in) keeps focus. To turn the guard off, run `launchctl disable gui/$(id -u)/com.dotfiles.chrome-dock-guard` and `launchctl bootout` the same label; `dotfiles doctor` has no fix step for it, so it stays off. Moving the agents to Chrome for Testing would fix this at the source, but it drops their saved logins (different keychain key), so the owner chose the guard (2026-10-18). Manual fix: `open -na "Google Chrome"`.

Do not set `AGENT_BROWSER_PROFILE` to launchd-owned profiles under `~/.agent-browser/{chrome-profile,debug-profile,tooling-profile}`. Chrome ProcessSingleton forwards those launches into the existing browser and creates stray `chrome://newtab` windows; the wrapper delegates such profiles to `agent-browser-singleton-preflight` or refuses. These helpers stay in dotfiles because they encode this repo's launchd profile-to-port contract ([decision](plans/replace-relocate-agent-browser-singleton-helpers.md)).

Use a separate browser only for true isolation, conflicting credentials, or visible human authentication in a separate window. In that case, choose a stable purpose-named session (`agent-browser --headed --session-name sso-<purpose> ...`), not a timestamp-unique session, and close it when done. For non-SSO task-local checks, use a throwaway browser with a random debugging port, never ports `9222`-`9225`.
