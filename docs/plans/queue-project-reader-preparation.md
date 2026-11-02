# Project identity reader preparation

## Overall goal and vision

Keep project capacity correct while preparing the shared heavy-command queue
for private metadata. Each repo and its worktrees must keep one project cap
through a record-format transition. Older queue readers must remain safe.

This is Phase A: readers accept raw and typed project identities, while
writers retain the current raw fields. It does not complete metadata privacy.
The original seven privacy controls remain unchanged and are not claimed to
pass. No baseline, candidate implementation or installation has run for this
preparation. The commit introducing this plan registers the prediction before
those results.

## Decision and alternatives

Use reader-first compatibility on scheduler revision `2d313f4`. Reuse Perl's
`Digest::SHA::sha256_hex`; no new daemon or package is needed. Keep raw bytes
and normalized identity within each controller's lifecycle.

Reject a writer-only hash change: strict 429 and 430 readers compare raw
project fields and cannot count opaque owners or pending grants correctly.
Reject rewriting another controller's live records: it retains its own raw
project in process memory. A coordinated quiescent installation is a later
alternative, not part of this preparation.

## Evidence and current state

| Claim | Current source of truth | Delivery path | Status |
|---|---|---|---|
| Project selection uses an explicit override, Git common directory, then working folder. | `bin/heavy-run`, shell project selection | Controller environment to Perl process | fact |
| One scheduler reads both numeric and `s<n>` slot owners. | `snapshot` | Held owner records to capacity snapshot | fact |
| Pending grants consume capacity before an owner exists. | `tick`, `took` | Ticket identity and `.grant` to capacity snapshot | fact |
| Gate tickets keep strict 429 waiters behind the scheduler. | `gate`, `tick` | Gate file and kernel locks | fact |
| New tickets use `kind=v2`; unknown kinds block scheduling. | `tick` | Ticket fields to decision | fact |
| Typed project identities share the same grouping as raw fields. | Proposed shared identity parser | All owner and ticket readers to `decide` | proposed |
| Compatible old readers continue to count preparation writers. | Proposed isolated interoperability matrix | Real scratch controllers and kernel locks | verify |

Facts above refer to `2d313f4f101e9f9024f1f19b81d78db090c2f6c8`.

## Registered experiment

- **Goal**: preserve project-cap decisions across compatible record formats.
- **Question**: can new readers count raw and typed identities while strict
  readers still count preparation writers and tickets?
- **Hypothesis**: one shared project-identity reader reduces the expected
  six failing preparation controls out of ten on unchanged scheduler 430 to
  zero. Wrong same-project admissions and lost independent-project admissions
  for valid records are zero in the isolated matrix. Invalid typed live
  records explicitly block all new admissions. Two controls check the reader
  capability marker; they are not privacy outcomes.
- **Measurement**: integrate the frozen ten-control harness at the proposed
  path below. Run it on unchanged 430 before production edits, then run the
  same harness on the candidate. Run the current scheduling suite and the
  required commit gate through the shared heavy-run queue.
- **Success**: all ten controls pass; zero wrong admissions; zero lost
  independent-project admissions for valid records. Raw owner line two, raw
  ticket line three, numeric owner line three `start=`, `kind=v2`, and project
  grouping remain intact. Existing scheduling controls all pass.
- **Pivot**: any wrong admission, misleading capability marker, changed
  grouping or failed scheduling regression rejects this adapter. Do not
  enable opaque writers or change the ticket kind as a shortcut. Resolve the
  observed protocol failure before choosing another approach.
- **Anchor**: Basili, Caldiera and Rombach (1994), Goal Question Metric;
  Herlihy and Wing (1990), Linearizability, ACM TOPLAS 12(3), 463–492,
  <https://doi.org/10.1145/78969.78972>. Measure observable admission behavior
  under one project capacity, not counts of implementation activity.

## Boundary contract

### Fixture erratum before corrected measurement

The initial unchanged-430 run reached ten cases and reported eight failures.
It is not a valid whole-matrix baseline. The synthetic Python `-c` argument
contained a physical newline. Existing raw command metadata put that newline
inside its first record line, shifting positional project and start fields.
Three owner-readiness cases timed out, and the ticket position assertion saw
`wait=` where it expected the project. These are fixture-format failures.

The failure also exposes an existing queue limitation: physical CR/LF in raw
command arguments can shift strict 429 positional project fields and break
project-cap accounting. It is not only a test artifact. The corrected fixture
isolates the planned identity adapter; it does not fix multiline arguments
or prove old/A interoperability for those unsupported record inputs.

Preserve that run and its frozen harness. Correct only the fixture command
representation: encode the same Python loop with `repr` inside `exec`, so
the argument has no physical CR/LF. Keep all workloads, handshakes, controls,
thresholds and the original seven privacy fixtures unchanged. Commit this
erratum before running the corrected baseline. Wrong-admission assertions
remain evidence, but do not count the incomplete matrix as the registered
six-control baseline or as a production result.

The current shell owns project selection. The controller process owns its
raw project bytes and normalized identity for that invocation. Held owner
records, live tickets and pending grants provide scheduling evidence; a PID
alone does not prove ownership or liveness.

One parser handles both representations:

- `project=<raw>` hashes the raw bytes once.
- `project_id=sha256:<64 lowercase hex>` carries an already typed identity.
- A raw name beginning `sha256:` remains raw; do not overload `project=`.
- Missing, invalid or inconsistent identity on a live record blocks new
  grants. Do not omit that record from counts or group it under empty text.

Phase A writers retain raw fields in their existing positions. Append only
the constant `reader=project-id-v1` marker after existing fields. Preserve
`kind=v2`, `start=`, gate ordering, old-slot counting, grants and pause marks.
The marker advertises a capability; it does not prove old readers have left.

The same normalized representation must reach `snapshot`, `tick`, `took`,
`decide`, the first-reason hint and the no-queue fallback. Keep raw project
text separately for existing Phase A wait wording. Invalid snapshots must
not become empty runnable queues in a fallback.

## Numbered work breakdown

### 1. Freeze and measure interoperability controls

- **Why**: prove reader capability and preserve old/new scheduling behavior.
- **Parallelism**: first; production edits depend on actual assertion failures.
- **Owner / boundary**: Dotfiles tests; all queue state and process groups
  belong to a scratch fixture. The outer run uses owner-configured limits.
- **Change**: integrate the reviewed draft as
  `tests/helpers/heavy-run-project-interop.py`. Reuse the strict 429 fixture;
  add an exact strict 430 fixture. These harness paths are proposed, not
  existing commands at the plan-only checkpoint.
- **Evidence / acceptance**: each waiter observation matches its own
  controller's numbered ticket, held lock and nonstarting wait reason, with
  no grant. A synthetic unrelated ticket cannot satisfy readiness. Owner
  readiness matches the workload PID plus raw project and numeric start
  fields; a workload marker alone is insufficient.
- **Verification**, after harness integration:
  `heavy-run python3 tests/helpers/heavy-run-project-interop.py --candidate tests/fixtures/heavy-run-430 --legacy-429 tests/fixtures/heavy-run-429 --legacy-430 tests/fixtures/heavy-run-430`.

| Frozen control | Required behavior |
|---|---|
| A reads numeric raw 429 owner | Same project waits; an independent project starts. |
| Strict 429 reader and A owner | Gate holds strict waiter until A ends. |
| Strict 430 reader and A owner | Raw fields preserve the project cap. |
| A owner capability | Raw line two, numeric `start=` line three and reader marker. |
| A ticket capability | Raw line three, `kind=v2` and reader marker. |
| A reads typed future owner | Same project waits; independent project starts. |
| A reads typed capped ticket | With a raw owner, skip the capped typed ticket and start the independent project. |
| A reads typed pending grant | Count its project before a slot owner exists. |
| Raw digest-looking project | Keep its raw project grouping. |
| Invalid typed live owner | Grant no workload while that held identity is invalid. |

Strict fixtures are public `bin/heavy-run` blobs:

| Fixture | Commit | Git blob |
|---|---|---|
| 429 | `c97d7f6c684ebbcb6a92985685364cff1b8da985` | `f7c345a9c6fd4eac7bec36a36e918cddc740c5c5` |
| 430 | `2d313f4f101e9f9024f1f19b81d78db090c2f6c8` | `32e591a590f56d4a4c1d8c7784082cbd125c2f05` |

### 2. Add the shared reader and preserve writers

- **Why**: every capacity path must use the same project identity.
- **Parallelism**: depends on step 1's actual red evidence.
- **Owner / boundary**: existing Perl controller module in `bin/heavy-run`.
- **Change**: implement the parser and normalize every listed reader and
  decision path. Retain raw writer fields and append the constant marker.
  Keep source changes within this protocol preparation.
- **Evidence / acceptance**: all ten controls pass on the same harness. A
  negative mutation bypassing `snapshot` normalization fails the typed-owner
  control. A separate mutation bypassing ticket/grant normalization fails
  the typed-ticket or pending-grant control. A marker-only patch cannot pass.
- **Verification**:
  `heavy-run python3 tests/helpers/heavy-run-project-interop.py --candidate bin/heavy-run --legacy-429 tests/fixtures/heavy-run-429 --legacy-430 tests/fixtures/heavy-run-430`.

### 3. Verify and deliver preparation only

- **Why**: retain current settings, memory ordering and legacy gate behavior.
- **Parallelism**: depends on step 2; source and harness review can run
  independently of queued regression checks.
- **Owner / boundary**: Dotfiles delivery; no owner setting change.
- **Change**: document the compatibility marker, raw metadata still present,
  controller lifecycle and deferred opaque-writer activation. Keep the
  original privacy task open and its seven controls unchanged.
- **Evidence / acceptance**: all current worktree-grouping, live-setting,
  memory oldest-first, realtime STOP/CONT, gate and orphan controls pass.
  Independent review verifies exact source and final tree before delivery.
- **Verification**: `heavy-run bats tests/heavy-run.bats`, then
  `heavy-run make check BATS_JOBS= TEST_FILE_JOBS=`.

## Rollout, security and unresolved boundaries

Deliver Phase A normally after green gates. Do not activate opaque writers
in this change. A strict 430 scheduler can remain leader with old loaded code
after an entrypoint update. Gate tickets solve old slot visibility; they do
not teach an old scheduler how to read a typed project identity.

Later Phase B needs a separately verified guard for strict 429 and 430
leaders, running owners, pending grants, queued readers and pre-ticket
launchers. A once-empty queue is insufficient. Never rewrite another
controller's held records or kill unowned jobs. Arbitrary future obsolete
copies against live state remain outside a managed-entrypoint rollout.

Current raw project and command fields are line-oriented. Physical CR/LF in
project names or command arguments can shift strict 429 positional fields;
the initial fixture run demonstrated this for a command argument. This
preparation does not fix that unsafe format, claim compatibility for those
inputs, or silently transform them. Phase B's content-free first line will
address command metadata. Rejecting unsupported raw project names before
writing records needs a separately registered negative test. Until then,
old/A compatibility claims apply only to record inputs without physical
CR/LF in raw project names or command arguments.

Scratch interoperability tests use synthetic content, private temporary
folders, bounded handshakes and only their own child process groups. They
must never address the owner's live state directory. Keep the original
privacy baseline and all negative results; preparation is not privacy
completion or a runtime installation claim.
