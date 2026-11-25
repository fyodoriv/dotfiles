# Extend commit messages through the installed overlay

Issue: #838. The global commit-message hook currently calls only the
repository hook. Reuse the verified overlay hook runner before that call.

Hypothesis: an overlay can extend a commit message without replacing the
global hook, while an overlay failure stops the commit before the repo hook.

Measurement: hosted `tests/commit-msg-chain.bats` creates synthetic repositories
and overlays. A real Git commit must retain the appended message line. A
failing overlay must preserve its error and prevent the repo hook from running.
Existing `tests/commit-msg.bats` must pass.

Success: message edit persists in Git; the first nonzero overlay result stops
the commit; no-overlay behavior and existing validation remain unchanged.

Pivot: any ignored overlay failure, lost message edit, duplicate hook run,
or changed existing validation rejects the implementation.

Anchor: issue #838 and the existing `oss_readiness_run_overlay_hook` boundary
used by `git-hooks/pre-push`.

The installed plugin owns its optional hook. The existing plugin verifier
and capabilities check keep that ownership boundary. This change adds no
mutable state. Per-Mac hooks and prepare-commit-msg are optional proposals
outside this change.
