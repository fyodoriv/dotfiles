# Current status

Nov 6: the first audit found 51 open Agentbrew task blocks and 46 open
Dotfiles task blocks. Explicit blocked fields do not capture every dependency.
Separate audits are checking the tasks against source, existing PRs, and the
actual acceptance criteria. GitHub issues and PRs overlap these task blocks.

The first pass found actionable preparation in both repositories. Agentbrew
includes sync-selection, locked-install, dependency evidence, eval-ID,
inventory, checkup-record, document-capture, browser-error and leak-audit
work. Dotfiles includes compiler-observation preparation, queue-privacy
prerequisites, source collection and the measured gate-speed pivot. An
actionable preparation step does not mean its whole task is deliverable.
Other tasks remain blocked or need current evidence; do not count missing
samples as success.

The compiler queue protocol and receipt oracle have shipped. An independent
review found that the oracle does not execute an observer against the sealed
cases, so its zero-false-decision criterion is not yet proved. The live capture
and queue epoch remain separate, unqualified boundaries.
[PR #512](https://github.com/fyodoriv/dotfiles/pull/512) registered the
test-only oracle harness and its controls. The harness shipped in
[PR #513](https://github.com/fyodoriv/dotfiles/pull/513). A separate pure
decision-model experiment was registered in
[PR #514](https://github.com/fyodoriv/dotfiles/pull/514); no decision subject
or live observer has been qualified.

The queue project-identity reader has shipped. Its preparation does not make
the current metadata private or authorize an opaque-writer cutover.

The registered seven-day `make check` result crossed its pivot threshold.
[PR #509](https://github.com/fyodoriv/dotfiles/pull/509) records the result;
the speed task remains open. Existing step timings lack a run identifier and
cannot yet be tied to the measured tool calls.

The Dotfiles Rust inventory task permits source collection before its shared
validator is available. The pinned agent-hook source receipt shipped in
[PR #511](https://github.com/fyodoriv/dotfiles/pull/511) as a partial
collection; it does not close the repository-wide inventory task.

On Nov 6, the compiler holdout hash was registered and bound in
[PR #515](https://github.com/fyodoriv/dotfiles/pull/515) and
[PR #516](https://github.com/fyodoriv/dotfiles/pull/516). Source review found a
missing independently qualified root; [PR #517](https://github.com/fyodoriv/dotfiles/pull/517)
records that finding. No candidate or holdout decision result was measured.

The gate attribution experiment was registered in
[PR #518](https://github.com/fyodoriv/dotfiles/pull/518). Its fourteen
synthetic controls passed in [PR #519](https://github.com/fyodoriv/dotfiles/pull/519).
Real-agent receipt delivery and the original speed outcome remain unproved.

The managed-browser stray-tab doctor guidance shipped in
[PR #521](https://github.com/fyodoriv/dotfiles/pull/521), after registration in
[PR #520](https://github.com/fyodoriv/dotfiles/pull/520). It is one slice of
issue #475, which remains open. The Dock-guard issue #487 remains unverified:
a disabled job alone does not establish the options used by its doctor skip.
The compiler holdout author confirmed that its platform was unspecified; it
cannot be retrospectively claimed as a Darwin-specific fixture.
