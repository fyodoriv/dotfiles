# Keep Git branch checks within their shell commands

A live guard refused a compound verification script. It contained a
read-only `git -C "$repo" branch --show-current` comparison and separate
fetch, diff, and merge operations. No branch deletion ran. The earlier
pull request #824 already covers quoted GitHub issue bodies.

Use the existing typed shell parser to distinguish executable Git
operations from literal text and independent commands. Preserve the
existing decision for input the parser cannot classify. The tests submit
synthetic shell source to the hook and never run that source.

- **Hypothesis:** Correct command boundaries eliminate the current false
  refusal and let proved literal text describe branch deletion.
- **Measurement:** Run `bats tests/agent-hooks-block-dangerous-git.bats tests/agent-hooks-block-dangerous-git-merged.bats`
  on hosted macOS. Run the current-base fixture before editing the hook.
  Measure guard latency with the repo's existing timing gate.
- **Success:** All registered harmless controls pass, there are 0
  allowances of registered unsafe inputs, and the existing suite stays
  green. Keep the task's 100 ms guard latency limit.
- **Pivot:** Reject the approach after 1 mistaken allowance, 1 changed
  existing decision outside the proved safe cases, or a breach of the
  100 ms limit.
- **Anchor:** [Dotfiles #761](https://github.com/fyodoriv/dotfiles/issues/761),
  [Dotfiles #824](https://github.com/fyodoriv/dotfiles/pull/824), and
  `git-guard-parsed-words-and-gaps` in TASKS.md.

The standard performance row times `git status`. The repo-query row
times the parser path with the same synthetic input the standalone test
uses. The 100 ms fastest-run ceiling covers fixture setup and the guard.
