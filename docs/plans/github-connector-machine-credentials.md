# Plan: prepare keyring-backed connector credentials

- **Task**: github-connector-machine-credentials
- **Repo**: dotfiles
- **Author**: deployment-cutover-audit, 2026-11-02
- **Status**: original preparation prediction at `7d6006d`; standalone transfer registered below
- **Validated-by**: root reviewed the source intake and fixed groups on 2026-11-02

## Overall goal and vision

Keep a selected machine connector from using an expired environment token after
GitHub CLI sign-in rotates. A doctor repair must recognize a stale nonempty GUI
value, preserve unrelated explicit-token policy and disclose no credential.
This follows VISION G1/G3 and the user-directed machine ownership boundary.
Source request: [agentbrew issue #693](https://github.com/fyodoriv/agentbrew/issues/693).
Dotfiles owns this work; do not close that issue before linked delivery.

## Decision and alternatives

First deliver runnable Rust contract instrumentation, then qualify native
credential/launchd adapters and the callback consumer before production wiring.
Keep domain policy in dotfiles. Reuse the pinned shared Rust measurement and
process boundary rather than adding a shell/Python credential engine.

A whole-gh environment override would break explicit token use. A nonempty
environment check cannot detect stale values. Inferring callback coverage from
a filename cannot authorize deletion. These alternatives are rejected.

## Evidence and current state

| Claim | Current source of truth | How provided | Status |
| --- | --- | --- | --- |
| User assigns machine helper and GUI repair to dotfiles | Issue #693 and user clarification | Machine configuration | fact |
| Ordinary gh auth checks retain environment precedence | `modules/git/doctor.sh:172-200`, `bin/gh` | Existing git doctor and wrapper | fact |
| Current GitHub MCP check tests nonempty GITHUB_TOKEN only | `modules/agentbrew/doctor.sh:232-262` | Existing doctor module | fact |
| Security doctor checks GUI PATH, not credential freshness | `modules/security/doctor.sh:552-580` | Machine doctor | fact |
| Repairs recheck and a dev checkout is report-only | `bin/dotfiles-doctor:334-345,525-580` | Existing fix/recheck path | fact |
| No matching helper source was found | Tracked source search at `3955d331`; bounded installed code-helper metadata search | Chat/log/auth stores excluded | bounded non-discovery |
| Shared Rust source/measurement boundary | [Rust migration](rust-migration.md), source tree `187687c9aa6c674fc47fc71b5cfc02b456e8a6f3` | Pinned private preparation input; not an installed release | proposed reuse |
| Actual callback output format, endpoint and owned helper | Matching installed consumer and source | No verified ownership record yet | unqualified |

## Scope (in)

- Register and seal synthetic credential/policy/repair controls.
- Add a fail-closed pure contract stub, then retain its actual semantic red.
- Separate typed absent/matching/stale/unknown decisions and guarded repair.
- Keep secret values invocation-scoped in RAM, outside receipts and logs.
- Prepare future thin existing-doctor/native adapter boundaries.

## Scope (out)

- Live credentials, keyring, GH token lookup, launchctl calls or GUI mutation.
- Changes to ordinary gh, `bin/gh`, current git doctor or explicit-token users.
- Generated agent files, agent setup, native conversations and account privacy.
- Native callback output/coverage qualification or an issue-complete claim.
- Another secrets store, credential persistence or a new process supervisor.

## GET before IMPLEMENT

Reuse GitHub CLI's keyring lookup, launchctl's GUI environment API and the
existing doctor check/fix/recheck convention. Existing installed helper source
was not recovered by the bounded search. Do not claim source absorption.
Use the shared Rust fixture/receipt protocol through a pinned adapter, keeping
machine policy in dotfiles. Missing native qualification does not block pure
fixture preparation or justify a temporary credential script.

## Boundary contracts

The selection is a typed machine policy: unconfigured, refresh-managed-GUI or
remove-when-covered. Unknown/unconfigured selection performs zero lookups and
zero mutations. The default is not permission to repair arbitrary GUI tokens.

Only the selected keyring header callback's child removes BOTH GH_TOKEN and
GITHUB_TOKEN before fixed `gh auth token -h github.com`. Preserve other owner
context. Do not alter general gh precedence or other hosts. Native execution
remains unavailable during this preparation; tests use a synthetic adapter.

Secret values have invocation scope. Their type has no Debug, Serialize,
receipt, stable digest or persistent representation. No token travels in a
process argument. Limit an accepted synthetic token to 4096 visible ASCII
bytes; reject empty, newline/control-bearing and oversized data before header
construction. The future native lookup must bound each child stream to 8192
bytes and refuse overflow. These are preparation caps, not a total-RSS claim.
Do not echo lookup stderr. A dedicated callback sink may receive a synthetic
successful header in tests; no production stdout/header format is qualified.

Read results distinguish absent, value and unknown. Compare keyring and GUI
values only in RAM. Emit fixed absent/matching/stale/unknown categories, never
values, lengths or hashes. Missing and stale managed GITHUB_TOKEN can propose
refresh only after a valid keyring read. Do not overwrite unrelated GH_TOKEN.
An unset operation requires verified consumer coverage and a selected remove
policy. Native coverage stays unqualified; no filename or nonempty-env inference.

Separate proposal, write and recheck. Read-only mode never writes. Rejected
writes or a nonmatching/unknown recheck never report fixed. A second matching
run is a no-op. Preserve the applied-checkout guard and existing doctor result
semantics. A future native adapter requires bounded execution/cancellation and
owned cleanup proof; pure replay does not supply that authority.

## Numbered work breakdown

### 1. Register the experiment and frozen oracle

- **Why:** prevent post-hoc safety thresholds or stale-credential counts.
- **Parallelism:** independent of native platform qualification.
- **Owner / boundary:** dotfiles machine policy; shared Rust fixture protocol.
- **Change:** commit this plan, then freeze actual variants and expected outcomes.
- **Evidence / acceptance:** no runtime results before prediction commit.
- **Verification:** `heavy-run make check BATS_JOBS= TEST_FILE_JOBS=`.

### 2. Deliver runnable contract instrumentation

- **Why:** a missing production command is not a credential failure baseline.
- **Parallelism:** after step 1; no native operations.
- **Owner / boundary:** private immutable Rust candidate, separate from shared WT.
- **Change:** tests plus minimal fail-closed stub; preserve first semantic red.
- **Evidence / acceptance:** compiled assertions fail for missing policy behavior,
  not absent commands/setup. Freeze before reducer implementation review.
- **Verification:** contract command below, one worker and one test thread.

### 3. Qualify native integration separately

- **Why:** replay cannot prove keyring, callback coverage or GUI repair.
- **Parallelism:** requires delivered instrumentation and separately registered
  native measurements; it does not block step 2.
- **Owner / boundary:** dotfiles source/doctor; agent configuration stays with
  agentbrew's existing owner.
- **Change:** later source-bound consumer/endpoint and owned-process adapters.
- **Evidence / acceptance:** explicit before/after native proof and green gates;
  no unknown coverage removal or credential disclosure.
- **Verification:** proposed future native target, registered before its code.

## Risks and mitigations

- **Credential disclosure:** prohibit secret Debug/serde/digests and raw child
  diagnostics; test markers on every output/failure path.
- **Wrong-token policy:** isolate both-var removal to keyring callback lookup;
  retain ordinary explicit-token precedence and unrelated GUI variables.
- **False repair:** require successful write plus matching/absent recheck.
- **False coverage:** keep the native coverage capability unavailable until
  the actual consumer, endpoint and owned helper are qualified.
- **Fixture-only confidence:** label replay evidence separately from live
  credential rotation, bounded child cleanup and real launchd behavior.

## Acceptance criteria

GQM hypothesis: every sealed pure decision matches the independent expected
outcome; zero wrong credential-source selections, unauthorized mutation
proposals, false fixed results and fixture-marker disclosures. The first
missing-capability stub is a policy-layer baseline, not a count of actual
credential failures. Do not claim a numeric field improvement before measuring.

Success: all pure assertions pass, positive controls remain valid and each
forbidden action/disclosure count is zero. Pivot: any unsafe proposal, unknown
read treated as absent, unrelated-token override, false fixed result or leaked
marker rejects the boundary. Change the adapter, never weaken the oracle.

Anchors: issue #693; Basili/Caldiera/Rombach (1994), GQM;
Munafò et al. (2017), pre-registration; OWASP Logging Cheat Sheet, data to exclude.

| ID | Fixed group | Expected decision/action |
| --- | --- | --- |
| C01 | Stale GITHUB_TOKEN, good synthetic keyring | Callback lookup removes both vars; keyring value only in dedicated fixture sink |
| C02 | GH_TOKEN stale alone or both vars conflicting | Same callback boundary; no environment-token header |
| C03 | Neither token variable | Valid callback; unrelated owner context preserved |
| C04 | Ordinary gh with explicit tokens | Existing precedence unchanged; no callback override applied |
| C05 | Missing/failing/timed-out lookup; empty/multiline/control/oversized value | No header or raw error; fixed failure and no secret persistence |
| C06 | GUI absent, valid keyring, selected refresh | Propose one refresh; fixed only after matching recheck; repeated run no-op |
| C07 | GUI stale nonempty, valid keyring | Refresh under selected policy; require matching recheck |
| C08 | GUI matches keyring | Matching, no write |
| C09 | GUI/keyring read failure or unknown | Unknown; zero writes; never infer absence |
| C10 | Selected remove plus coverage proof | Synthetic proof permits remove/recheck; native unqualified coverage refuses |
| C11 | Explicit unrelated GH_TOKEN or env-backed consumer | Preserve its policy; no blanket overwrite/unset |
| C12 | Write failure or mismatching/unknown recheck | Fixed count zero; failure retained |
| C13 | Secret markers on child/output/failure paths | Zero doctor/receipt/log disclosures; only successful fixture callback sink may receive header |
| C14 | List/override discovery, non-macOS, unconfigured/unknown policy | Zero credential lookup or GUI mutation; no installed/healthy inference |

Seal exact variants, expected receipts and source hashes before the first run.
The proposed runnable target is created by the instrumentation preparation:

```sh
heavy-run cargo test --locked --manifest-path "${CONNECTOR_CANDIDATE_MANIFEST:?}" --test connector_credentials_contracts -- --test-threads=1
heavy-run make check BATS_JOBS= TEST_FILE_JOBS=
```

Run from an owned checkout with `CARGO_BUILD_JOBS=1` and the reviewed
invocation-only SDK environment. No sibling-relative build dependency, new
package publication, live gh lookup or launchctl invocation is needed.

## Rollout and regression coverage

- **Merge / deployment order:** prediction, runnable instrumentation, separately
  measured native adapter, then explicit supported installation/activation.
- **Security:** synthetic values only; no live token, auth file, transcript,
  launchd-value read, stable secret digest or service mutation in preparation.
- **Regression coverage:** frozen C01–C14 replay, existing doctor contracts,
  existing explicit-token GitHub CLI behavior and required dotfiles gate.
- **Open decisions:** exact callback format/endpoint and owned installed source
  need source qualification. Native removal authority and runtime readiness stay
  unavailable until those facts and process bounds are proven.

## Reviewer verdict

- **Verdict**: approved for preparation only.
- **Reviewer**: root, independent intake review, 2026-11-02.
- **Concerns**: native consumer format and coverage are unqualified; do not wire
  production or claim the issue resolved from pure contract results.
- **Approval rationale**: the fixed cohort can proceed without live credentials
  or GUI writes. The callback-specific boundary preserves general gh policy.

## Standalone transfer prediction

Record the original local prediction `7d6006d` and the existing sealed
November 2 red/green results as historical evidence. The private reducer run
passed all 37 cases and the authority-separation control. This prediction
comes before the source transfer and standalone results.

Goal: preserve the sealed credential controls in Dotfiles. Question: can the
same reducer, fixtures and assertions run in a standalone test-only package?
Metric: retain 38 of 38 passes with zero ignored or filtered cases and zero
changed bytes in these three inputs. Only Serde 1.0.229 and Serde JSON 1.0.154
are needed by the sealed files. The new manifest and lock isolate those exact
versions from the private fixture owner and its process dependencies.

| Sealed input | SHA-256 |
| --- | --- |
| `src/connector_credentials.rs` | `bda01128a60f33e3ec28b4f0c441c54ed5b0980304713244462d5db8dc4ced3f` |
| `tests/connector_credentials_contracts.rs` | `3c36910a295884dd514f3ae125e35d3330b13453f2c033d67d725a153a479250` |
| `tests/fixtures/connector-contracts.json` | `6a2a1f7f7220e66480a7887feed577bd651379714ca96dd82b11f656185ef7e7` |

```sh
JOBS=1 CARGO_BUILD_JOBS=1 heavy-run /usr/bin/sandbox-exec \
  -p '(version 1) (allow default) (deny network*)' \
  cargo test --offline --locked \
  --manifest-path tests/fixtures/connector-credentials/Cargo.toml \
  --test connector_credentials_contracts -- --test-threads=1
heavy-run make check BATS_JOBS= TEST_FILE_JOBS=
```

Success is the exact hashes above, 38 passing cases and both required gates
green. Pivot on any byte drift, dependency outside the approved standalone
graph, missed control, native authority or credential disclosure. Anchor:
original sealed C01–C14, Basili/Caldiera/Rombach (1994) and Munafò et al. (2017).

The Careerbrew `1b2b5415` reference in `src/careerbrew/workday/mcp_check.py`
and `tests/unit/test_mcp_fix.py` qualifies a command-string `headersHelper`
with one JSON Authorization object in a synthetic client configuration.
Installed consumer ownership and native invocation still need proof. Native
transport depends on the shared bounded Darwin worker. The installed
`launchctl(1)` contract takes the value in `setenv key value`. A native refresh
requires a secret-safe writer. Selected removal requires exact callback
coverage and verified readback. Production issue #693 stays open.
