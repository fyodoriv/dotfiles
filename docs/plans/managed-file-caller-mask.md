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

## Isolated chezmoi result

Both calls returned 0. With mask 022, standard output was empty.
With mask 077, the diff changed mode 100644 to 100600 and contained
no content hunk. The fixture file still matched the source at 0644.

## Check the result through Doctor and heavy-run

- **Hypothesis**: The equivalent restrictive caller produces the
  original managed-file failure through Doctor. The current queue
  wrapper restores the usual caller mode and the same Doctor check
  passes.
- **Measurement**: Run hosted `bats tests/doctor.bats` for a disposable
  `managed.editorconfig` check. Use the actual Doctor and chezmoi
  with a fixed 0644 destination. Run the check directly under 022
  and 077, then put the 022 Doctor behind the current heavy-run
  controller with a fixture-owned queue. Compare its JSON result
  and the file's bytes and mode.
- **Success**: The two usual-mask checks each report one managed
  pass. The restrictive control reports exactly one managed
  failure. All three leave the fixture file unchanged.
- **Pivot**: One incorrect managed status, an unavailable fixture
  tool, or one file mutation leaves the reported symptom unqualified.
- **Anchor**: The isolated result above, the
  [chezmoi mask reference](https://www.chezmoi.io/reference/configuration-file/umask/),
  and the shipped caller-mask fix in #756.
