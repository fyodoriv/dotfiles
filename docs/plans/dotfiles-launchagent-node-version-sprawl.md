# Plan: dotfiles-launchagent-node-version-sprawl

## Goal

One command switches this Mac to a new Node. It moves every piece that names a
Node path at the same time, so `agentbrew.launchagent_node_pinned` stays green.

## Why

- `~/.node-version` and the `~/.local/bin/{node,npm,npx}` links were hand-made.
- agentbrew plists store `process.execPath`. Only a manual
  `agentbrew auto-sync install` (and `agentbrew sync` for the memory maintain
  job) rewrote them.
- Between those manual steps, LaunchAgents ran an old Node and macOS could ask
  about each drifted path.

## Scope (in)

- `bin/dotfiles-node-upgrade [VERSION] [--dry-run]`:
  1. `fnm install`, `fnm default` (and `fnm alias lts-latest` for the LTS default).
  2. Write `~/.node-version`.
  3. Relink `~/.local/bin/{node,npm,npx}`. Never replace a regular file.
     The managed Codex CLI is reinstalled and relinked on the selected Node.
  4. Run the agentbrew CLI on the new Node: `auto-sync install`, then
     `sync --no-recommended --agentfile ~/.config/agentbrew/Agentfile.yaml`.
  5. Kickstart `com.dotfiles.gui-path` (it reads `~/.node-version`).
  6. Run the drift check from `lib/node-pin.sh`; exit 1 on drift.
- `dotfiles upgrade --node [VERSION]` runs it. The weekly topgrade pass does not.
- The drift check moves from `modules/agentbrew/doctor.sh` to `lib/node-pin.sh`
  so the doctor and the script share one copy.

## Scope (out)

- No `fnm uninstall`. minsky pins an older Node in its repo.
- No automatic reinstall of arbitrary npm globals. The managed Codex CLI is
  the explicit exception. Other globals are per version and some need
  special flags (`@railway/cli`). The script lists the old version's globals.
- No chezmoi template for `~/.node-version`: the version changes on upgrade,
  not on apply.

## Verification

- `bats tests/dotfiles-node-upgrade.bats` (fixture fnm, Node, and agentbrew).
- `dotfiles-node-upgrade --dry-run` on this Mac.
