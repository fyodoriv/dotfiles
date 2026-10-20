# agent-browser attach-first policy

This text moved here from `AGENTS.md` so the always-loaded file stays short. `AGENTS.md` keeps a summary and links here. The text is unchanged.

## agent-browser attach-first policy

At most three browsers run on this Mac. Zero is fine.

| Browser | How agents use it |
|---------|-------------------|
| The user's own Chrome | Agents never use it unless the user says so. The ChromeWork link router keeps links there. |
| One agents Chrome: `com.dotfiles.agent-browser-chrome`, CDP port `9223` | The user signs in once. Agents share it in their own tabs and share its cookies. This is the default. |
| One temporary browser: `temp-browser`, CDP port `9230` | For disposable or bot sign-ins. Each use starts with a fresh profile, deleted after use, like incognito. One agent at a time holds it. |

The old `chrome-debug` (9222), `debug-chrome` (9224), and `tooling-chrome` (9225) agents are retired. `dotfiles apply` unloads and deletes them (orphan unload), and the doctor check `agent-browser.no_retired_chromes` removes any copy left behind.

`~/.agent-browser/config.json` sets `"cdp": "9223"` (chezmoi `private_dot_agent-browser/modify_config.json`, other keys kept). So agent-browser attaches to the agents Chrome by default. When that Chrome is down, agent-browser fails. It does not start its own browser. Start it with `~/.agent-browser/ensure-chrome.sh`.

### The temporary browser

```bash
port="$(temp-browser acquire --owner "$AGENT_BROWSER_SESSION" --reason "bot sign-in")"
agent-browser --cdp "$port" open https://example.com
temp-browser status                                  # holder, reason, pid, lease expiry
temp-browser release --owner "$AGENT_BROWSER_SESSION"  # stops the browser, deletes the profile
```

- The lock is a directory under `~/.local/state/temp-browser/lock` (`mkdir` is atomic). It records the owner, the reason, the browser pid, the port, the profile, and the lease expiry (default 1 hour, `TEMP_BROWSER_LEASE_SECONDS`).
- A second agent is refused (exit 3) with the holder's name and reason.
- An expired lease or a browser that exited is discarded (browser stopped, profile deleted) and taken over.
- The same owner can acquire again; that renews the lease and prints the port.
- The browser runs `--headless=new` in the background. It never raises or focuses a window.
- Calls that need isolation (`--session-name`, `--profile`, `--extension`) go to the temporary browser through this lock.

The `home/zshrc.ai-tools` wrapper routes normal operator calls and dotfiles-assigned agent sessions to `agent-browser --cdp 9223` when the dashboard Chrome is reachable. Launchd Chromes run `--headless=new` so CDP tab create never opens a GUI window. After agent-browser, the wrapper logs suspected focus steals to `~/.local/share/dotfiles/logs/focus-steal.log` only — it never hides Chrome or `osascript activate`s another app (both can switch Spaces). Use `--headed` or `AGENT_BROWSER_ALLOW_FOCUS=1` when you want Chrome to stay frontmost for SSO. Preserve tab safety with per-agent daemons plus own-tab discipline: open your own tab, act only on tabs you opened, and close extra tabs at task end.

The managed agents Chrome is `RunAtLoad` only, not `KeepAlive`: if the operator quits Chrome for logout/shutdown, launchd and `dotfiles doctor --fix` must not reopen it. Agents attach when it is available; otherwise they fail, or use the temporary browser.

This Chrome runs the real `Google Chrome.app`, so macOS registers them as `com.google.Chrome`. With your own Chrome closed, a Dock click, Cmd-Tab, or `open -a "Google Chrome"` can bring a headless one to the front. It has no window, so Chrome looks stuck. `com.dotfiles.chrome-dock-guard` (`bin/dotfiles-chrome-dock-guard`, source `lib/chrome-dock-guard.swift`) watches the frontmost app and hands that click to your own Chrome: it raises it, or starts it with `open -n -a`. A headless Chrome turns frontmost without posting `didActivateApplicationNotification`, so the guard observes `NSWorkspace.frontmostApplication` too. It hands off only when that agent Chrome has no on-screen window. A headed agent Chrome (for example one left open so you can finish a sign-in) keeps focus. To turn the guard off, run `launchctl disable gui/$(id -u)/com.dotfiles.chrome-dock-guard` and `launchctl bootout` the same label; `dotfiles doctor` has no fix step for it, so it stays off. Moving the agents to Chrome for Testing would fix this at the source, but it drops their saved logins (different keychain key), so the owner chose the guard (2026-10-18). Manual fix: `open -na "Google Chrome"`.

Do not set `AGENT_BROWSER_PROFILE` to launchd-owned profiles under `~/.agent-browser/chrome-profile` (or the retired `debug-profile` and `tooling-profile`). Chrome ProcessSingleton forwards those launches into the existing browser and creates stray `chrome://newtab` windows; the wrapper delegates such profiles to `agent-browser-singleton-preflight` or refuses. These helpers stay in dotfiles because they encode this repo's launchd profile-to-port contract ([decision](plans/replace-relocate-agent-browser-singleton-helpers.md)).

Use the temporary browser only for true isolation, conflicting credentials, or a disposable sign-in. For a visible human sign-in in a separate window, use `agent-browser --headed --session-name sso-<purpose> ...` with a stable purpose name, and close it when done. Never start another browser on ports `9222`-`9225`.
