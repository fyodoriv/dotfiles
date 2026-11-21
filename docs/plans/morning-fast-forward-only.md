# Keep morning refreshes fast-forward only

[Issue #644](https://github.com/fyodoriv/dotfiles/issues/644) recorded
a morning refresh replaying local commits onto an unrelated upstream.
The refresh should advance a branch only when it can do so directly.

- **Hypothesis**: The refresh advances a normal behind branch, while
  two branches that would need a rebase stay at their original commits.
- **Measurement**: Run hosted `bats tests/morning.bats`. Point a
  disposable checkout at a new local bare repository with an unrelated
  root. In a separate case, diverge from a common ancestor. Compare the
  exact HEAD and clean worktree bytes before and after each refresh.
  In the forward case, compare HEAD with the new upstream commit.
- **Success**: Zero local commit or file changes in the 2 non-forward
  cases. Both show a hint to inspect the checkout. The forward case
  reaches the upstream commit. The full morning suite still passes.
- **Pivot**: One changed local commit or file on refusal, one failed
  fast-forward, or one regression in the morning suite rejects the fix.
- **Anchor**: Issue #644 and the matching fast-forward-only tooling
  refresh contract.
