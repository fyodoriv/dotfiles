# Decision: keep the agent-browser singleton helpers in dotfiles

- **Task**: replace-relocate-agent-browser-singleton-helpers
- **Date**: 2026-10-16
- **Status**: decided — keep in dotfiles; no upstream PR or relocation now

## Question

Should these thin adapters move upstream (agent-browser), move to agentbrew,
or stay in dotfiles?

- `bin/agent-browser-singleton-preflight`: maps a managed profile path to its
  launchd Chrome CDP port (`chrome-profile` → 9223, `debug-profile` → 9224,
  `tooling-profile` → 9225). If that Chrome answers on CDP, it runs
  `agent-browser --cdp <port>` instead of a second Chrome on the same profile.
  It also runs the focus-restore helper.
- `bin/agent-browser-reap-strays`: stops stray Chromes on ports 9223-9225
  that launchd does not own.
- `~/.agent-browser/ensure-chrome.sh` and `launch-chrome.sh`: kick the
  `com.dotfiles.agent-browser-chrome` LaunchAgent and wait for CDP.

## Options and evidence

| Option | Evidence (checked 2026-10-16) | Verdict |
|---|---|---|
| Upstream to agent-browser | agent-browser 0.39.0 already has `connect <port>`, `--cdp`, and `--auto-connect` ("connect to a running Chrome"). The missing piece is the mapping from *this repo's* profile paths and launchd labels to ports. That mapping is host policy, not a browser-CLI feature. | No PR. The generic part already exists upstream; the rest is local. |
| Relocate to agentbrew | agentbrew owns agent config and shared rules, not LaunchAgents. The helpers read `com.dotfiles.*` plists and ports that `launchagents/*.plist.tmpl` in dotfiles define. The policy text lives in `docs/agent-browser-policy.md` here. | No. Moving the scripts would split one contract (plist + port + helper) across two repos. |
| Keep in dotfiles | The helpers are small and depend only on the dotfiles launchd profile and port contract. Tests exist: `tests/agent-browser-singleton-preflight.bats`, `tests/agent-browser-reap-strays.bats`, `tests/module-agent-browser.bats`. | **Recommended.** |

## Recommendation

Keep the helpers in dotfiles. Reason: they encode the dotfiles launchd
profile → port contract (9223/9224/9225), which is host policy. The generic
attach feature is already upstream (`--cdp`, `--auto-connect`).

Re-check when one of these happens:

- agent-browser can attach by profile path (for example, `--profile <path>`
  reuses a running Chrome that holds that profile's singleton lock). Then
  the preflight can shrink to a pointer.
- The launchd Chrome contract moves out of dotfiles.

No follow-up task: nothing to build now.
