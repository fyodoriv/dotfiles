# Codex install and health

Goal: the terminal CLI survives a Node switch and both primary agents get
visible readiness checks. ChatGPT.app is the GUI host; it owns its bundled
CLI. Agentbrew owns agent configuration.

## Pre-registered experiment

- Hypothesis: reinstalling the managed npm package on the selected Node and
  restoring its user-bin link reduces a missing Codex after upgrade from one
  reproduced incident to zero. Checking executable health catches the same
  failure even when the config folder remains.
- Measurement: `bats tests/codex-cli.bats tests/codex-doctor.bats tests/dotfiles-node-upgrade.bats`.
  Before implementation, the new installer and doctor cases failed because
  neither entry point existed; the existing owner-file test passed vacuously.
- Success: zero failed cases, including the Node-upgrade relink assertion.
- Pivot: any failure to execute the relinked CLI after an upgrade means the
  npm route is rejected; use a managed Homebrew install instead.
- Anchor: Basili, Caldiera, Rombach (1994), Goal Question Metric; Forsgren,
  Humble, Kim (2018), change failure rate.

## Scope and verification

Install through one helper used by apply, upgrades, and doctor fixes. Never
read auth files. Keep sign-in and ChatGPT.app checks advisory because these
need an account or a GUI install. Parse TOML rather than matching strings.
Test missing CLI, stale package metadata, repeat applies, opted-out Macs, owner-file
preservation, malformed config, stale executable paths, and sign-out.

The install and link state is per macOS user and npm prefix. The doctor has
no persistent cache. Module helper functions live for one doctor process.

## Review correction

The first Node-upgrade adapter installed Codex unconditionally. An independent
review caught the opt-out regression. A new opted-out test failed before the
guard. The adapter now installs only for `use_ai_tools: true` or to preserve an
existing user-bin Codex link. Login checks always use a two-second subprocess
timeout, including machines without GNU timeout.

A second review caught the same opt-out policy in the new doctor: full-profile
Macs without Codex were checked despite `use_ai_tools: false`. A failing
regression now pins the skip. Existing links remain checked so a broken install
is not hidden by a later setting change.

## Acceptance evidence

The parent goal run verified the helper on this Mac: exit 0 and
`codex-cli 0.166.0`. `npm view @openai/codex version` also returned `0.166.0`.
The worktree doctor returned exit 0 with all Codex checks passing. A minimal
environment login shell resolved Codex and returned its version with exit 0.
Sign-in was checked with `codex login status`, without reading auth files.

Node upgrade acceptance uses an isolated fnm/npm fixture. A disruptive host
Node upgrade was not needed. The fixture verifies the new Node's executable
and the user-bin link, preserves old Node installs, and checks AI opt-out and
already-installed behavior.

The opt-out fix retains the task's config-only incident on core profiles:
with AI tools enabled and `~/.codex` already synced, a missing binary is still
reported. A focused test failed before restoring that distinction.

## Codex hook protocol experiment

Hypothesis: the native `hookSpecificOutput.updatedInput` response reduces
ignored PATH rewrites from one failing Codex fixture to zero while keeping
legacy hook responses unchanged. Measurement:
`bats tests/agent-hooks-prepend-endpoint-path.bats`. Success: zero failed
fixtures. Pivot: if native Codex does not accept the documented response,
leave the hook untrusted and report the unsupported surface. Anchor: the
[official hooks protocol](https://learn.chatgpt.com/docs/hooks) and GQM
(Basili, Caldiera, Rombach, 1994). Both new native fixtures failed before
the response branch was implemented.

## Doctor speed pivot — registered before the change

The original task set a 500 ms module budget. The first live module probe
took 1,015 ms; separate version and login probes took 389 ms and 399 ms.
This triggers its pivot away from running sign-in checks on every audit.

- Hypothesis: local file and executable-path checks take at most 500 ms when
  version and sign-in execution move to an explicit `--full` audit. Default
  audits still diagnose absent executables and invalid configuration.
- Measurement: `heavy-run bats tests/codex-doctor.bats`, then the timed module
  command below. Run `dotfiles doctor --full --module codex` to verify the
  opt-in runtime and sign-in checks.
- Success: all regression cases pass and module wall time is at most 0.50 s.
- Pivot: above 0.50 s, abandon this default-check split and profile the
  remaining file/config checks before choosing another approach.
- Anchor: Basili, Caldiera, Rombach (1994), Goal Question Metric.

```bash
heavy-run /usr/bin/time -p bash -c '
  check() { eval "$3" >/dev/null 2>&1; }
  check_advisory() { check "$@"; }
  DOTFILES_DIR=$PWD
  source modules/codex/doctor.sh
'
```

Full-check selection belongs to one doctor process and resets on each run.
No persistent cache or new account state is introduced.

The focused regression run passed all 13 cases after the split. The timed
module command returned `real 0.19` (190 ms), below the 500 ms threshold.
Independent review approved the flag lifecycle, watch forwarding, check-list
discovery, saved overrides, and default execution behavior.
