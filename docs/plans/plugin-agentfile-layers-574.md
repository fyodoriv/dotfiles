# Register per-user plugin Agentfile layers

Dotfiles issue #574 reports that doctor rewrites the global Agentfile
without a plugin's per-user settings. Apply and doctor already filter
Agentfile contributions through the same list and merge guard.

A verified plugin can list optional data files in
`contributes.agentfile_layers`. Paths are relative to that plugin's
directory under `${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/plugins`.
Apply and doctor process the files in manifest order with the existing
plugin merge guard. Missing files are skipped. Files outside the plugin's
directory and links are refused. The normal local override still comes
after plugin layers. Detect additions, edits, and removals when deciding
whether to skip apply.

## Prediction

- **Hypothesis**: A declared per-user layer survives apply and doctor
  repair when it extends the shared Agentfile. A missing or disallowed
  layer leaves the shared merge intact.
- **Measurement**: Hosted Bats exercises plugin manifest validation,
  the ordered list consumed by apply and doctor, the existing merge
  guard, and apply-state invalidation.
- **Success**: Three red controls reproduce the missing declaration,
  missing discovery, and unchanged apply fingerprint. All pass after
  the fix. Zero path escapes or shared hook, agent, or MCP replacements.
- **Pivot**: Stop delivery if one rejected layer reaches the merge,
  one allowed layer disappears during repair, or one edit or removal
  fails to invalidate the skip record.
- **Anchor**: [Dotfiles #574](https://github.com/fyodoriv/dotfiles/issues/574)
  and the Agentfile extension rules in [plugins.md](../plugins.md).
