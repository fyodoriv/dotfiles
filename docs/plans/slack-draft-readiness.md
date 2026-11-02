# Slack draft readiness

Goal: count and delete from a channel tab without a manual navigation or
confirmation click. Prediction committed as e5f03b1 before new tests.

1. Reproduce missing navigation with fake channel state and a fresh-dialog
   confirm variant. Reproduce a view timeout and a non-Slack tab.
2. Reuse `agent-tab nav` for the owned tab and the plugin sandbox process-group
   deadline pattern for bounded calls. Derive only the current Slack workspace's Drafts URL; never keep a
   workspace URL or payload in source. A deadline belongs to one command.
3. Keep exact recipient/full-body rechecks and confirmation rules. Limit the
   confirm fallback to a fresh draft-delete dialog and stop action when the
   browser-side deadline expires.
4. Run `bats tests/slack-draft.bats`, then `heavy-run make check` and an
   independent safety review. Preserve all existing decoy, changed-list,
   duplicate, authorization, and injection controls.

Success: zero failed assertions, each reported failure fixture resolved, and
one bounded deadline no larger than 30 seconds. Pivot: any wrong-row delete,
wrong-dialog click, or deadline overrun abandons automatic action pending a
verified selector contract. Anchor: Basili, Caldiera, Rombach (1994), GQM;
Forsgren, Humble, Kim (2018), stability.

Tests execute the real generated page scripts in a synthetic DOM. No live
workspace or organization payload is read, and no live draft is deleted.
Slack markup remains an external compatibility boundary; source comments
retain the requirement for a throwaway-workspace check when it changes.

Review regressions: resolve the deployed command symlink through the existing
Cwd `abs_path` pattern. A TERM-ignoring browser call must finish under three
seconds with a one-second budget; a call-owned process group receives KILL
at its deadline. Both deployment/deadline regressions failed before the fix.
The shared timeout library stays outside this change.

A review fixture delays child process-group setup past the deadline. The
group-only adapter failed its under-three-second threshold. Cleanup now
kills both the call-owned group and its unreaped direct child before wait,
so that startup scheduling race also remains bounded.
