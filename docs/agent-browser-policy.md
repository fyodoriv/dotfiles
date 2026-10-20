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
- `TEMP_BROWSER_HEADED=1` starts a headed window, for passkey, hardware-key, or visible sign-ins. It launches with `open -g -n -a`: a new instance, kept in the background. It never activates or raises a window; you bring it forward yourself.
- `TEMP_BROWSER_LAUNCH=<cmd>` replaces the launch. temp-browser runs `<cmd> <profile> <port>`. The command must start a browser with that profile and CDP port and print its pid on the last stdout line. temp-browser records that pid in the lock and stops it on release. The hook must not raise or focus a window.
- Calls that need isolation (`--session-name`, `--profile`, `--extension`) go to the temporary browser through this lock. The `home/zshrc.ai-tools` wrapper hands them to `bin/agent-browser-temp-route`. It takes the lock and runs `agent-browser --cdp <temp port> ...`.
  - Owner: the `--session-name` value, else `$AGENT_ID`, else `$AGENT_BROWSER_SESSION`. With none, the call fails (exit 2).
  - Reason: `$AGENT_BROWSER_TEMP_REASON`, default `isolated agent-browser session`.
  - Held by another agent: the call fails (exit 3) and prints the holder and the reason. agent-browser does not run.
  - `--profile <dir>` is dropped, because the temporary browser always starts with a fresh profile.
  - `agent-browser ... close` releases the lock. Otherwise the lease expires.

### Exit code contract

Wrappers can rely on these codes for `temp-browser`, `agent-browser-temp-route`, and `agent-tab`:

| Code | Meaning |
|------|---------|
| 0 | OK |
| 1 | Error (browser did not start, Chrome not reachable, tab not tracked, page command failed, `health` found tabs that do not answer) |
| 2 | Usage error |
| 3 | Busy: another owner holds the lock or the tab. The holder and the reason go to stderr. Wait, or pick another resource. For `agent-tab`: a page command (`text`, `eval`, `nav`, `shot`) on a tab you do not own or whose lease expired, or `clear-cookies` while a live-lease tab uses that site (stderr lists the blocking tabs). |

`tests/temp-browser.bats` and `tests/agent-tab.bats` pin `exit 3`.

### Tab leases in the agents Chrome: `agent-tab`

Agents share the agents Chrome (9223). `agent-tab` records who owns each tab, so agents never close each other's tabs.

```bash
tab="$(agent-tab open --owner "$AGENT_ID" --reason "check dashboard" https://example.com)"
agent-tab list                                   # id, owner, live/expired, expiry, reason, url
agent-tab renew --owner "$AGENT_ID" --lease 1800 "$tab"
agent-tab close --owner "$AGENT_ID" "$tab"

export AGENT_TAB_OWNER="$AGENT_ID"              # default for --owner
agent-tab text "$tab"                            # page text
agent-tab eval "$tab" 'document.title'           # value of a JS expression
agent-tab nav "$tab" https://example.com/next
agent-tab shot "$tab"                            # prints the PNG path
agent-tab health [--fix]                         # tabs that do not answer
agent-tab clear-cookies example.com              # one site's cookies
```

- Records live in `~/.local/state/agent-tab/tabs.json`. Writes take a `mkdir` lock and replace the file with `mv` (atomic).
- `open` uses CDP `PUT /json/new`; `close` uses `/json/close/<id>`. Neither raises a window.
- Default lease is 1 hour (`--lease`, `AGENT_TAB_LEASE_SECONDS`).
- Closing or renewing another owner's tab with a live lease exits 3 and prints the holder and the reason. After the lease expires, anyone can close it.
- `text`, `eval`, `nav`, and `shot` work only for the owner with a live lease. Others get exit 3. An owner with an expired lease gets exit 3 too: run `renew` first. They send one CDP call over the tab's websocket (Node built-in `WebSocket`) and never raise a window.
- `shot` writes PNGs to `~/apps/agent-scratch/screenshots/` (`AGENT_TAB_SHOT_DIR`).
- `health` evaluates `1` in every page tab and lists the ones that do not answer (exit 1). `--fix` reloads them. If a reload does not help, it closes the tab only when no live lease owns it; a leased tab is kept and its holder printed.
- `clear-cookies <domain>` deletes the cookies of that domain and its subdomains. If any live-lease tab is on that site, it exits 3 and lists the blocking tabs. Tabs with an expired lease do not block.

The `home/zshrc.ai-tools` wrapper routes normal operator calls and dotfiles-assigned agent sessions to `agent-browser --cdp 9223` when the dashboard Chrome is reachable. Launchd Chromes run `--headless=new` so CDP tab create never opens a GUI window. After agent-browser, the wrapper logs suspected focus steals to `~/.local/share/dotfiles/logs/focus-steal.log` only — it never hides Chrome or `osascript activate`s another app (both can switch Spaces). Use `--headed` or `AGENT_BROWSER_ALLOW_FOCUS=1` when you want Chrome to stay frontmost for SSO. Preserve tab safety with per-agent daemons plus own-tab discipline: open your own tab, act only on tabs you opened, and close extra tabs at task end.

The managed agents Chrome is `RunAtLoad` only, not `KeepAlive`: if the operator quits Chrome for logout/shutdown, launchd and `dotfiles doctor --fix` must not reopen it. Agents attach when it is available; otherwise they fail, or use the temporary browser.

This Chrome runs the real `Google Chrome.app`, so macOS registers them as `com.google.Chrome`. With your own Chrome closed, a Dock click, Cmd-Tab, or `open -a "Google Chrome"` can bring a headless one to the front. It has no window, so Chrome looks stuck. `com.dotfiles.chrome-dock-guard` (`bin/dotfiles-chrome-dock-guard`, source `lib/chrome-dock-guard.swift`) watches the frontmost app and hands that click to your own Chrome: it raises it, or starts it with `open -n -a`. A headless Chrome turns frontmost without posting `didActivateApplicationNotification`, so the guard observes `NSWorkspace.frontmostApplication` too. It hands off only when that agent Chrome has no on-screen window. A headed agent Chrome (for example one left open so you can finish a sign-in) keeps focus. To turn the guard off, run `launchctl disable gui/$(id -u)/com.dotfiles.chrome-dock-guard` and `launchctl bootout` the same label; `dotfiles doctor` has no fix step for it, so it stays off. Moving the agents to Chrome for Testing would fix this at the source, but it drops their saved logins (different keychain key), so the owner chose the guard (2026-10-18). Manual fix: `open -na "Google Chrome"`.

Do not set `AGENT_BROWSER_PROFILE` to the launchd-owned profile `~/.agent-browser/chrome-profile`. `agent-browser-singleton-preflight` maps only that profile (to `9223`). It refuses the retired `debug-profile` and `tooling-profile` and points at `temp-browser`; no mapping to `9224` or `9225` is left. Chrome ProcessSingleton forwards those launches into the existing browser and creates stray `chrome://newtab` windows; the wrapper delegates such profiles to `agent-browser-singleton-preflight` or refuses. These helpers stay in dotfiles because they encode this repo's launchd profile-to-port contract ([decision](plans/replace-relocate-agent-browser-singleton-helpers.md)).

Use the temporary browser only for true isolation, conflicting credentials, or a disposable sign-in. For a visible human sign-in, ask the user; `--session-name` calls now run in the headless temporary browser. Never start another browser on ports `9222`-`9225`.
