# Codex readiness: upstream boundary

Decision: keep the machine adapter. Use `codex doctor --json` for Codex's
own runtime diagnosis. Do not make each fast dotfiles check start the full
native doctor.

## Current probe

On Sun Nov 1, 2026, installed Codex 0.166.0 returned schema version 1 with
24 named checks from `codex doctor --json`. The command exited 0. Its help
offers `--network-only`, but no local-only or individual-check selector.
Only check IDs, statuses, and schema information informed this decision.
The raw local report is not committed.

| Concern | Native check | Boundary |
| --- | --- | --- |
| Installation and executable provenance | `installation`, `runtime.provenance` | Native doctor diagnoses its running executable. Dotfiles must also work before Codex exists and repair its GUI-accessible user-bin link. |
| Config parsing | `config.load` | Native doctor owns loaded configuration diagnosis, including its active scope. Dotfiles retains a cheap check of the managed home TOML file. |
| Stored sign-in credentials | `auth.credentials` | Use native doctor for detailed diagnosis. Dotfiles retains its bounded `login status` advisory in full mode. Neither result proves a live session can complete a request. |
| Desktop runtime | `desktop.app.version`, `desktop.app_server.handshake` | Native doctor owns app runtime diagnosis. Dotfiles separately checks the expected ChatGPT.app installation paths. |
| GUI command path | No matching check proved by this probe | Keep `codex.local_bin` and the installer link repair. Finding a CLI on terminal PATH does not prove the GUI path exists. |
| Nested `CODEX_CLI_PATH` values | No matching check proved by this probe | Keep the recursive executable-path check. |
| Hook file write access | No matching check proved by this probe | Keep the hook-file/parent permission check. |
| Installation before the CLI exists | Cannot run native doctor | Keep the npm installer, endpoint-policy opt-out, and owner-file protection. |

Native `installation` does not replace installation. The adapter also
reconnects the selected Node installation to `~/.local/bin/codex` after a
Node upgrade. Never replace that link with the app's bundled executable.

## Replacement gate

Recheck when native doctor gains a bounded local-only selector or covers a
machine gap above. Before replacing a check, prove its missing-CLI, broken
link, invalid-config, stale nested path, and unwritable-hook fixtures still
fail correctly. Also preserve profile opt-outs, list mode, and owner-file
protection. Run `bats tests/codex-doctor.bats` and the required `make check`.
No source check or installer is removed by this decision.

This is a documentation decision; the existing repository gate is its
metric exemption. It makes no performance or reliability improvement claim.
