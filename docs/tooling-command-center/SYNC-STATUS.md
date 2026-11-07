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

Dotfiles [PR #522](https://github.com/fyodoriv/dotfiles/pull/522) added the
person-owned browser Spotlight repair steps after a reproduced missing-guidance
control and passing module and repository gates. Issue #475 remains open.

Agentbrew [PR #848](https://github.com/fyodoriv/agentbrew/pull/848) merged the
registered eval-ID composition observation and removed its completed task.
Four synthetic controls, the existing validator tests and the corrected full
gate passed. Two independent reviews confirmed that ordinary clean-tree gates
are separate from the closed research cohorts.

The pure recorder-health preparation in
[Agentbrew #819](https://github.com/fyodoriv/agentbrew/pull/819) passed nine
controls; its real health channel and group-signal runner remain unqualified.
[Agentbrew #830](https://github.com/fyodoriv/agentbrew/pull/830) merged after
sixteen fake-transport controls and all 21 local gate steps passed. Hosted CI
remains separate. The registered local-model baseline stopped on an invalid
response for its first case. Its empty reservation is retained and must not be
reused; no real chat was used. Its task and issue #821 remain open.

[Agentbrew #850](https://github.com/fyodoriv/agentbrew/pull/850) merged a
separate schema-based protocol after its 22-step full gate passed. No new
baseline was run; distinct cases and a fresh prediction remain required.

[Agentbrew #851](https://github.com/fyodoriv/agentbrew/pull/851) shipped a
bounded reviewer-command classifier. Its synthetic controls, stock hook suite,
and full gate passed. Real event qualification remains. It sends no message
and does not enable a hook.

[Agentbrew #852](https://github.com/fyodoriv/agentbrew/pull/852) shipped
synthetic target controls for the existing native pair verifier. Both controls
and the full 22-step gate passed. It does not qualify a real binary or install.

[Agentbrew #853](https://github.com/fyodoriv/agentbrew/pull/853) was closed
without merge and preserves a rejected synthetic chat runner approach. A forged-mode control triggered a
fake request, meeting its registered rejection threshold. Later passing tests
do not qualify it. A distinct approach needs a new prediction before testing;
caller-provided bindings and transport do not qualify live admission.

[Agentbrew #854](https://github.com/fyodoriv/agentbrew/pull/854) shipped a
synthetic reviewer report parser and its gate discovery. Focused, stock-shell
and full 22-step controls passed. Event integration remains open.

[Dotfiles #523](https://github.com/fyodoriv/dotfiles/pull/523) shipped exact
active-account GitHub scope checks. Its eight controls, existing auth tests and
full gate passed. It covers part of #475; that issue remains open.

[Agentbrew #855](https://github.com/fyodoriv/agentbrew/pull/855) shipped the
fixed imported unittest report format. Focused, stock-shell and full 22-step
controls passed. The event runner and real hook remain unqualified.

[Agentbrew #856](https://github.com/fyodoriv/agentbrew/pull/856) prepares the
JSON-bound core-rule selection model. Eleven synthetic controls and type
checking and final discovery pass; the full gate is running. It does not qualify
real enabled-plugin state or session delivery.

[Agentbrew #767](https://github.com/fyodoriv/agentbrew/pull/767) now also
contains nine pure owner-receipt controls for issue #810. The first format was
rejected after review; the registered compatibility pivot passed. This does
not qualify worker ownership, process cleanup or a physical observation.

[Agentbrew #849](https://github.com/fyodoriv/agentbrew/pull/849) merged
read-only guidance for a busy source lease after its full 21-step gate passed.
It does not authorize or implement stale-lease removal; issue #814 stays open.

The sync-warning fix [#847](https://github.com/fyodoriv/agentbrew/pull/847)
merged after its full 20-step gate passed; issue #787 is closed and local
Agentbrew main was fast-forwarded to the merge.
The local composition for judge draft #755 has four unresolved build/install
conflicts. Main's compiler-free prebuilt pair does not cover the draft's judge
reader or changed publisher; a source-qualified asset set is still needed.
Two synthetic models passed their tests but failed independent review; neither
qualifies the asset set or a production installation.

The official [registry working group charter](https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/community/working-groups/registry.mdx)
still lists registry API v1 GA as ideating, with no target date. The registry
lookup remains opt-in pending that external milestone.

[Agentbrew #857](https://github.com/fyodoriv/agentbrew/pull/857) merged its
owned synthetic reviewer-event runner. Eight runner controls, six gate controls,
stock discovery, independent review and the uncached 22-step gate passed
(6,495 tests passed; 33 skipped). The first discovery observation lost its log
and was rejected. Local main was fast-forwarded to `68e0d1da`. Issue #822
still needs real event, MCP and delivery qualification.

[Agentbrew #856](https://github.com/fyodoriv/agentbrew/pull/856) merged its
JSON-bound synthetic core-rule model after 11 controls, independent review and
an uncached 22-step gate passed (6,495 tests passed, 33 skipped). Local main
was fast-forwarded to `806ad42b`. Issue #826 remains open for trusted live
plugin-state selection and delivery.

[Agentbrew #858](https://github.com/fyodoriv/agentbrew/pull/858) was closed
without merging after its full gate found an unused writer export. The finding
was reproduced locally and met the transfer's pivot. Its source and logs are
preserved. The process-group runner and real diagnosis remain unqualified.

[Agentbrew #859](https://github.com/fyodoriv/agentbrew/pull/859) was closed
without merging after its full gate rejected the isolated `.prep.ts` file as
behavior without a test. The finding was reproduced and met the registered
pivot. The earlier synthetic results and source are preserved. The four target
selection cases remain sealed.

[Agentbrew #860](https://github.com/fyodoriv/agentbrew/pull/860) merged its
no-writer recorder pivot after nine controls, Knip, independent review and an
uncached 22-step gate passed (6,504 tests passed; 33 skipped). Local main was
fast-forwarded to `55c1032c`. The process-group runner and earlier timeout cause
remain unqualified.

[Agentbrew #861](https://github.com/fyodoriv/agentbrew/pull/861) uses an
explicit default exclusion for its synthetic sync test. Nine controls,
discovery, rule-3, Knip, types and independent review passed. The uncached
22-step gate passed with 6,504 tests passed and 33 skipped. It was merged and
local main fast-forwarded to `cef72da9`. The real selection cases remain sealed.

The [Rust archive probe](plans/judge-rust-archive-probe-v2.md) acquired six
official Linux musl toolchain archives. Their sizes, hashes, receipt and private
file metadata passed an independent recheck. XZ headers report about 1.6 GB
uncompressed. The files have not been extracted or run; #755's source-bound
assets and build/reproducibility controls remain open.

The [Alpine runtime probe](plans/judge-linux-image-probe.md) passed on both
Linux architectures. Independent review confirmed the recorded configuration,
outputs and cleanup. This does not prove network egress isolation, qualify a
toolchain or establish build reproducibility.

The [Rust image probe](plans/judge-rust-image-probe.md) then passed on both
architectures. Independent review confirmed the pinned images, compiler and
Cargo versions, musl targets, configuration and cleanup. It did not build a
program or independently test network egress.

The [synthetic compiler probe](plans/judge-synthetic-build-probe.md) passed
on both architectures. Each ran two builds of a fixed program, compared the
outputs and ran one. Independent review confirmed the command, results and
cleanup. The binaries were not retained for later comparison; the real reader
and its dependencies remain unqualified.

The [locked crate probe](plans/judge-locked-crate-probe.md) acquired the one
missing Linux archive. Its size, checksum, receipt and private file metadata
passed independent review. It remains unextracted; this is not a reader build
or a qualification of the registry metadata.

The [reader build admission](plans/judge-reader-build-draft.md) first passed
seven independently checked synthetic controls. Its one permitted attempt
stopped before container creation: Docker returned `No such image` for the
pinned ARM image. The registered result is inconclusive. The same image was
visible in a later read-only check; the reason for the earlier response is
unknown. The admission marker is consumed, and no reader build was attempted.
