# Check the reported managed-file diff against the caller mask

[Issue #731](https://github.com/fyodoriv/dotfiles/issues/731) observed
a managed-file mismatch only during the full Doctor run. The queue now
preserves the wrapped command's incoming file mask. Test whether the
same chezmoi version reports a permission-only difference for a matched
file when the caller uses the old queue mask.

- **Hypothesis**: A real chezmoi diff reports one mode-only change
  with mask 077 and no change with mask 022 for the same matched file.
- **Measurement**: Run `chezmoi diff` twice in a disposable source and
  destination, using version 2.74.1. Hold the source bytes, destination
  bytes and modes fixed. Run both calls read-only and compare exact
  output classes, status and destination state.
- **Success**: 1 empty result at 022 and 1 mode-only result at 077.
  Both tool calls exit zero. Compare the file bytes and mode after
  both calls and require 0 changes.
- **Pivot**: If neither result differs or any file changes, this probe
  leaves the original full-Doctor observation unexplained. Do not close
  the issue on that result.
- **Anchor**: Issue #731, [runner permission fix](https://github.com/fyodoriv/dotfiles/pull/756),
  and the Doctor managed-file check's invocation of chezmoi diff.
