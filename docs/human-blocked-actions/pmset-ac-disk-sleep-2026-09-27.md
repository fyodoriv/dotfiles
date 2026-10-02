# Human-blocked action: set the AC disk-sleep timer

- **Status**: reopened 2026-10-02 (setting reset by an outside writer)
- **Filed**: 2026-09-27
- **Agent**: GPT-5.6 Terra
**TASKS.md entry**: the merged sleep-protection work

## Why the action is required

The live AC power policy has `disksleep 0`, but the managed policy requires
`disksleep 10` when no Cursor or Claude Code process is running. The
process-scoped manager correctly prevents disk sleep while a tracked process
runs, so this remaining drift only affects normal idle behavior after those
processes exit. The macOS doctor reports this exact check as failed.

## Why it cannot be avoided

The merged manager and its `caffeinate -m` assertion cannot set a global
`pmset` preference; it intentionally only exists while a tracked process runs.
`dotfiles apply` already ran the managed macOS repair and its doctor pass, but
the preference stayed at `0`. An unprivileged `pmset -c disksleep 10` attempt
returned `'pmset' must be run as root...'`. The scoped non-interactive command
`sudo -n pmset -c disksleep 10` returned `sudo: a password is required`.
No sudo timestamp, user-level power-management API, or approved credential
source is available in this session. The Mac is MDM-enrolled, but this session
has no MDM write access and a profile change would be broader than this one
local preference. Storing an administrator password in dotfiles, a LaunchAgent,
or a script would violate the repository's no-secrets boundary.

## Workarounds attempted

| Path | Tried | Outcome | Reason ruled out |
|---|---|---|---|
| `dotfiles apply` and its quiet doctor repair | 2026-09-27 | Completed successfully, but AC `disksleep` remained `0` | The repair calls `sudo -n`; no cached administrator authorization was available. |
| Unprivileged `pmset -c disksleep 10` | 2026-09-27 | Failed with `pmset must be run as root` | macOS protects this power preference. |
| `sudo -n pmset -c disksleep 10` | 2026-09-27 | Failed with `sudo: a password is required` | The agent cannot enter or retain the administrator password. |
| Process-scoped manager and `caffeinate -ims` | 2026-09-27 | Verified live for the Cursor process | It deliberately controls only active-agent assertions, not idle configuration after the process exits. |
| MDM configuration path | 2026-09-27 | Device enrollment is present, but no MDM write capability is available in this session | Changing a management profile is not a safe replacement for one scoped local setting. |

## Sources consulted

- **Live observation**: `pmset -g custom` reported `sleep 1` and
  `disksleep 0` under AC Power. `dotfiles doctor --module macos` reported
  only `AC disk sleep = 10 min when no agent is running` as failed.
- **Live verification**: `dotfiles-agent-keepawake --dry-run` found the
  Cursor process; `pmset -g assertions` showed its manager-owned
  `caffeinate` child asserting `PreventDiskIdle` and `PreventSystemSleep`.
- **Code anchors**:
  [`macos.sh`](../../macos.sh) sets AC `disksleep 10`, and
  [`modules/macos/doctor.sh`](../../modules/macos/doctor.sh) detects and
  repairs that exact value with `sudo -n`.
- **Management state**: `profiles status -type enrollment` reported DEP and
  user-approved MDM enrollment. No MDM write endpoint or credential is
  available to this session.

## Exact action the human must take

1. Open a normal local Terminal.
2. Run the following command and enter the local administrator password when
   macOS asks:

```bash
sudo pmset -c disksleep 10
```

This changes only the AC disk idle timer. It does not affect Git branches,
remotes, shutdown/restart behavior, or the agent manager's active
`caffeinate` protection.

## Verification after action

```bash
pmset -g custom | rg -A16 '^AC Power:'
cd "$(chezmoi source-path)"
bin/dotfiles doctor --module macos --quiet
```

The AC section must include `disksleep 10`, and the macOS doctor must exit
successfully.

## Pivot if the action fails

If `pmset` reports that the setting is managed or it returns to `0`, do not
store credentials or add a privileged LaunchAgent. Record the result and ask
the device-management administrator whether an MDM power-management profile
enforces the value. The process-scoped manager remains safe in the meantime:
it removes its own assertions when Cursor and Claude Code exit.

## Resolution

2026-09-28 — The operator ran `sudo pmset -c disksleep 10`. AC Power now
reports `disksleep 10`. `dotfiles doctor --module macos --quiet` exited 0
with only expected skips, and the resilience module exited 0 with one expected
skip. The live manager continues to protect the tracked Cursor process with
`PreventSystemSleep` and `PreventDiskIdle`.

## Recurrence (2026-10-02)

The setting drifted back. Both power profiles now match one template that
dotfiles never writes. So a second one-time `sudo pmset` would drift again.

**Evidence gathered:**

- `/Library/Preferences/com.apple.PowerManagement.plist` was last written at
  2026-10-02 06:40:00, the same second the Mac switched to battery
  (`pmset -g log`). No other readable file changed in that window.
- No dotfiles, agentbrew, or Minsky code, shell history, sleep/wake hook, or
  readable device-management script or log sets these values.
- A device-management payload stores power keys in that plist, so device
  management does write power preferences on this Mac. No Energy Saver timer
  payload is visible from this session.
- Some system logs and profile details are not readable from this session.

**Next step:** `com.dotfiles.pmset-drift-watch` now logs every change to
`~/.local/share/dotfiles/logs/pmset-drift.log` with the diff, the power source,
and the processes alive at that moment. The next reset names its writer. Then
either fix the dotfiles-side cause, or ask the device-management team to drop
or change the energy policy. Do not add a privileged enforcer that fights MDM.

**Resolution:** `.overrides` now skips `macos.pmset_ac_disk_sleep_10`, the same
way it already skips the display-sleep and battery checks that this template
also resets. On an SSD-only Mac, disk sleep has almost no effect. The drift
watcher stays installed, so the next reset still names its writer.
