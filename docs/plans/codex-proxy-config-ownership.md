# Keep the Codex proxy repair in the configuration owner

- Hypothesis: running the Dotfiles doctor on an existing Codex config makes zero writes or backups, while a missing proxy produces one advisory.
- Measurement: hosted Codex doctor controls for missing, enabled, explicitly disabled and inline TOML feature settings.
- Success: zero writes, one advisory for the missing key and no advisory for either explicit Boolean value.
- Pivot: stop if a doctor check still registers a config write or makes a missing optional proxy fail a tooling update.
- Anchor: the ownership contract in `docs/constitution.md` and Dotfiles PR #743.

Keep the sandbox advisory. Use the Codex CLI for a deliberate operator change.
Agentbrew owns automatic managed configuration changes.
