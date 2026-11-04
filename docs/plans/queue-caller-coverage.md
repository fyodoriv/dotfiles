# Queue caller coverage implementation plan

## Overall goal and vision

Stop explicit Rust compilation and the repository verify script from bypassing
the existing machine queue at the agent hook boundary. Keep safe inspection
commands and inert text usable. This repairs current caller coverage before
the separately measured Rust port; it does not change machine capacity.

This plan registers the task `queue-caller-coverage` before new fixtures or
runtime changes. Predictions below come from source review, not test results.
The earlier live process observation is not a baseline or an outcome metric.

## Decision and alternatives

Extend the existing `agent-hooks/require-heavy-run.sh` classifier. Reuse its
JSON-input Bats fixture convention and its fixed refusal message. Send command
strings to the hook; never execute Cargo, rustc, npm, or a supplied command.

A new process supervisor, Cargo PATH shim or Python measurement engine would
add a new ownership boundary. None is needed to measure this classifier bug.
Blocking all text that mentions Rust would reject documentation and inspection.
Increasing slots or stopping an observed process would not repair the caller.
Those alternatives are excluded.

## Evidence and current state

| Claim | Current source of truth | Delivery path | Status |
| --- | --- | --- | --- |
| The hook has no Cargo or rustc tool case | `agent-hooks/require-heavy-run.sh`, `_is_heavy` | agent `PreToolUse` Bash input | fact |
| The package-script predicate excludes `verify` | same file, `_heavy_script` | npm script classification | fact |
| Existing fixtures pass JSON command text to the real hook | `tests/agent-hooks-require-heavy-run.bats`, `run_hook` | Bats to hook stdin | fact |
| The doctor observer covers headless Chrome, not compilers | `modules/resilience/doctor.sh`, `bin/headless-chrome-unlocked` | advisory check | fact |
| The new frozen cohort passes through the existing parser without fixture failure | proposed fixture below | classifier decisions only | verify |
| A narrow classifier change rejects all unsafe cases without blocking positives | task prediction below | current source hook | proposed |

The reviewed hook SHA-256 is
`4b4a19c9b3b68c9d136e5260f1a1fd9ddbd66535cc4e71f9e9332f73659a2ac0`.
Freeze the unchanged subject and fixture hashes before the baseline. A changed
subject, absent hook, broken fixture or failed JSON extraction is inconclusive.
It is not a successful decision or a product red.

## Scope

Include explicit Cargo build, test, check, Clippy, benchmark, run and rustc
compilation forms, direct rustc compilation, and the exact npm `verify` script.
Preserve quoting, command prefixes, shell execution strings and inert text.
Filtered Cargo tests remain heavy because they can compile dependencies.

Do not generalize this task to arbitrary package scripts, aliases, response-file
contents, repository programs or external Cargo plugins. An unresolved invocation
of a recognized Rust tool must be non-green rather than silently authorized.
This does not prove universal shell analysis or machine-wide enforcement.

Keep compiler ancestry instrumentation in the separate preparation task
`compiler-queue-observation`. Do not change doctor runtime, settings, services,
slot limits, project limits, resource probes, priority or reservation lifetime.
Preserve the existing [resource measurement contract](queue-probe-measurement-preparation.md)
and all of its policy and fault cases unchanged.

The Bats fixture logic remains owned executable code eligible for the planned
Rust migration. Reusing it here is not a necessary-shell exemption.

## Boundary contracts

One hook invocation owns its command text and decision. Read only the existing
tool-input field. Do not resolve or execute caller files, inspect Cargo config,
read response files, expand shell variables, or load another workspace.

For a known heavy or unresolved recognized Rust invocation, exit 2 with the
fixed safe refusal message. Do not echo raw argv, paths, configuration or
environment values. Inert text and the exact inspection forms below exit 0.
Unrelated commands retain the current hook policy.

A syntactic `heavy-run` wrapper means only that this hook delegates admission.
It does not prove that a reservation exists. The canonical queue still owns
held-marker validation, controller identity, nesting and scheduling. Never
accept an inherited marker as a hook bypass, clear one to force admission,
fabricate an owner, or replace a running queue controller.

## Registered prediction and measurement

**Goal:** stop explicit heavy build callers before unqueued execution.
**Question:** does the hook distinguish compilation and verify from inspection,
wrapped commands and inert text? **Metric:** false permits and false blocks in
the exact frozen command cohort, plus retained hook and lease controls.

**Hypothesis:** source review predicts 29 false permits across H01-H26 and
U01-U03. Reduce that count to zero, with zero false blocks in P01-P22 and no
retained-policy regressions. This prediction is not an observed baseline.

**Success:** 100% expected decisions; zero false permits, false blocks, raw-input
disclosures or weakened retained assertions. Every required command exits zero.
**Pivot:** any mismatch or source/fixture validity failure rejects acceptance.
Change the classifier method after a valid counterexample; do not relax an
expected decision or call a setup failure a product failure.
**Anchor:** Basili, Caldiera and Rombach (1994), Goal Question Metric; Munafò
et al. (2017), preregistration. Cargo distinguishes build and manifest commands
in its [command reference](https://doc.rust-lang.org/cargo/commands/cargo.html).
The [metadata reference](https://doc.rust-lang.org/cargo/commands/cargo-metadata.html)
and [rustc options](https://doc.rust-lang.org/rustc/command-line-arguments.html)
support the bounded inspection cases below.

The new test file is proposed, not present at registration. Implement only its
fixtures after this prediction is committed. Run the baseline before changing
the hook, then repeat the same command after the fix:

```sh
heavy-run env JOBS=1 bats ./tests/agent-hooks-heavy-build-callers.bats ./tests/agent-hooks-require-heavy-run.bats
```

Retain the existing queue's actual identity and nested-marker checks separately:

```sh
heavy-run env JOBS=1 bats --filter 'nested call runs at once|stale HEAVY_RUN_HELD does not skip a free lock|incomplete live identity holds new admissions' ./tests/heavy-run.bats
heavy-run make check BATS_JOBS= TEST_FILE_JOBS=
```

The filtered command must execute all three named controls; zero or missing
selected cases is not green. The docs-only registration gate is the same
`heavy-run make check BATS_JOBS= TEST_FILE_JOBS=` command. It does not run or
establish the new cohort. Keep its receipt separate from future red/green runs.

## Frozen command cohort

Each row is one hook input. Only the hook runs. Every H and U row must exit 2
without copying the input into diagnostics. The unchanged source is predicted
to exit 0 for each, producing 29 false permits. Preserve every row and expected
exit through the fix. Additional cases need a prediction amendment first.

| ID | Command text |
| --- | --- |
| H01 | `cargo build` |
| H02 | `cargo test` |
| H03 | `cargo check` |
| H04 | `cargo clippy` |
| H05 | `cargo bench --no-run` |
| H06 | `cargo run --bin fixture` |
| H07 | `cargo rustc -- --emit=metadata` |
| H08 | `rustc --crate-type lib fixture.rs` |
| H09 | `rustc --test fixture.rs` |
| H10 | `npm run verify` |
| H11 | `time cargo test` |
| H12 | `env CARGO_BUILD_JOBS=1 cargo build` |
| H13 | `/fixture/bin/cargo test` |
| H14 | `cargo +stable check` |
| H15 | `bash -c 'cargo build'` |
| H16 | `cd fixture && npm run verify` |
| H17 | `rustc 'fixture source.rs'` |
| H18 | `'cargo' build` |
| H19 | `"/fixture path/bin/cargo" test` |
| H20 | `cargo test one_name` |
| H21 | `cargo check --manifest-path 'fixture path/Cargo.toml'` |
| H22 | `npm -w web run verify` |
| H23 | `command cargo test` |
| H24 | `cargo --offline build` |
| H25 | `HEAVY_RUN_HELD=SYNTHETIC_FOREIGN cargo test` |
| H26 | `rustc --print link-args fixture.rs` |
| U01 | `cargo custom-action` |
| U02 | `cargo "$MODE"` |
| U03 | `rustc @arguments.rsp` |

Every P row must exit 0. A blanket `--print` allowance is not safe: H26 retains
an actual compilation path, as the official
[print-options contract](https://doc.rust-lang.org/rustc/command-line-arguments/print-options.html#link-args)
states. Inspection exemptions are the specific forms here, not an authority
grant from any flag that looks informational.

| ID | Command text |
| --- | --- |
| P01 | `cargo --version` |
| P02 | `cargo -V` |
| P03 | `cargo --help` |
| P04 | `cargo help build` |
| P05 | `cargo metadata --no-deps --format-version 1` |
| P06 | `cargo locate-project --message-format plain` |
| P07 | `rustc --version` |
| P08 | `rustc -V` |
| P09 | `rustc --print sysroot` |
| P10 | `rustc --help` |
| P11 | `cargo build --help` |
| P12 | `cargo test --help` |
| P13 | `cargo +stable --version` |
| P14 | `printf '%s\n' 'cargo build; rustc fixture.rs'` |
| P15 | `echo "npm run verify"` |
| P16 | quoted heredoc input below |
| P17 | `git commit -m 'docs: run cargo test later'` |
| P18 | `heavy-run cargo build` |
| P19 | `env JOBS=1 CARGO_BUILD_JOBS=1 heavy-run cargo test` |
| P20 | `/fixture/bin/heavy-run cargo check` |
| P21 | `time heavy-run npm run verify` |
| P22 | `sh -c 'heavy-run cargo test'` |

P16 is exactly this multiline string, including its final newline:

```text
cat <<'NOTE'
cargo build
npm run verify
NOTE
```

The existing hook suite remains byte-identical in the baseline and fix unless
an independently reviewed fixture-only defect requires a recorded correction.
Its browser, JS, Bats, single-file, quoted-text, empty-input and explicit hook
opt-out policies stay unchanged. Never count a changed or omitted assertion as
a retained pass. No real tool dispatch, scheduler operation or owner file is
part of this cohort.

### Supplemental full-verify argument control

Register S01 before any caller-fixture result or classifier implementation.
It is separate from the original 51-row denominator and its 29 predicted
false permits. The source of agentbrew's `scripts/verify.sh` runs the full
gate; a filename supplied to that script does not select one test.

| ID | Command text | Required decision |
| --- | --- | --- |
| S01 | `npm run verify tests/fixture.ts` | exit 2; fixed refusal |

Prediction: the unchanged classifier falsely permits this case once; the fix
permits it zero times. Run it through the same new Bats file and command above.
Keep generic single-test exemptions for supported test runners, but never use
a filename to infer that the exact full-verify script became a filtered run.
The original rows, commands and expected decisions remain unchanged.

### Supplemental dynamic toolchain control

Register S02 before its probe or selector-normalization fix. Independent source
review found that the first candidate strips any Cargo argument starting with
`+`. It can mistake a variable-bearing selector for a literal toolchain.
Shell field splitting can then change the executable operation.

| ID | Command text | Required decision |
| --- | --- | --- |
| S02 | `cargo +$MODE metadata --no-deps --format-version 1` | exit 2; fixed refusal |

The command stays JSON data. Never set or expand MODE in a shell that executes
this command. A possible synthetic MODE value `stable run --` explains the
counterexample: real shell splitting would select `run`, with the remaining
words as program arguments. No real Cargo invocation is part of this test.

Prediction before probing: the first candidate at tree
`fd42498ae06cf5821079f3793057a9b92db2e08e` falsely permits S02 once; the
corrected candidate permits it zero times. This is a separate denominator
from the original 51 rows and S01. Preserve their inputs and expectations.
Use the same focused Bats command above. Success requires all 53 new and 17
retained controls to pass, with no raw-input disclosure or dispatch. Any
mismatch rejects acceptance. The GQM and preregistration anchors above apply.
Only an explicitly recognized literal selector may precede an inspection
allowance. A variable or unknown selector must refuse. Keep P13 `+stable`.

The first 69-control candidate result is insufficient for acceptance even
when green: it predates this independently found counterexample. Preserve
that result and the first candidate's separate Perl syntax failure. Neither
can replace this supplemental red/green proof.

## Numbered work breakdown

### 1. Register and freeze the baseline fixture

- **Why:** show actual unsafe hook decisions before a behavior change.
- **Parallelism:** after this registration; independent of Rust preparation.
- **Owner / boundary:** dotfiles hook tests, one invocation's text-to-exit contract.
- **Change:** add the proposed Bats file using the existing JSON fixture pattern.
- **Evidence / acceptance:** fixed inputs and expected exits, unchanged subject
  and original tests, actual semantic mismatches separated from setup errors.
- **Verification:** the exact focused command above; preserve source/test hashes,
  TAP plan and exit status without raw input in failure messages.

### 2. Extend the current classifier after valid red

- **Why:** refuse unwrapped heavy Rust and verify callers.
- **Parallelism:** depends on 1 and outside review; separate from doctor changes.
- **Owner / boundary:** `agent-hooks/require-heavy-run.sh`; no queue policy owner change.
- **Change:** add narrow tool/script classification while retaining safe quoting
  and inspection decisions. Update `docs/agent-hooks.md` in the same change.
- **Evidence / acceptance:** all registered and retained decisions match, fixed
  refusal output contains no supplied command, and no live process is changed.
- **Verification:** repeat the frozen focused command, the three existing lease
  controls and the normal required gate above. An outside judge checks the result.

### 3. Deliver source without claiming machine-wide enforcement

- **Why:** source correctness is not deployment or ownership proof.
- **Parallelism:** after 2; publication requires working authentication.
- **Owner / boundary:** normal dotfiles source delivery; owner installation stays separate.
- **Change:** retain the previous source for normal rollback and document the
  exact caller coverage. Do not install hooks or mutate settings in this task.
- **Evidence / acceptance:** required gate, leak check and independent review
  pass; real command dispatch and other tool protocols remain explicit limits.
- **Verification:** source diff and exact gate receipts; no live process observation
  is substituted for the frozen classifier metric.

## Rollout, security, and regression coverage

Commit registration before fixtures or the fix. The existing Bats harness is
the measurement preparation; it does not need a new engine. Keep the first
semantic red even if it differs from the source prediction. A mismatch with
that prediction must be explained before implementation, not edited away.

Only the agent-hook command channel covered by the input contract is in scope.
Native commands launched elsewhere can bypass it. The [compiler observation protocol](compiler-queue-observation.md) defines
the evidence and test-only receipt checks before implementation.
The browser observer cannot be renamed and treated as lease proof.

Do not log raw argv, real paths, environment values, owner queue records or
other workspace identities. Synthetic markers may be checked in RAM, but test
failure text reports IDs and booleans/counts. Keep owner overrides, native
memory/privacy opt-ins and the resource measurement contract unchanged.

## Focused source evidence

The unchanged hook produced 29 false permits in the original cohort and one
in S01. All 22 positive decisions and 17 retained controls passed. The first
candidate had an embedded Perl syntax error; that attempt is inconclusive.
The corrected parser passed the original 69 controls. Independent review then
found S02; that result alone did not establish acceptance.

After registration commit `62914eb`, S02 reproduced expected exit 2 versus
actual exit 0. The other 69 controls passed. Restricting selector normalization
to the reviewed literal `+stable` made the identical 70-control command pass.
No command payload ran. Unknown selectors refuse; this is not an allowance for
arbitrary expanded toolchain expressions. Literal quoted Rust executable paths
are recognized only at a bare command boundary, not every combination of shell
prefix and quoting. No universal shell-analysis claim follows.

The three registered queue identity controls and the required repository gate
remain separate acceptance requirements. Source delivery does not install the
hook or change machine settings. Compiler ancestry observation, private writer
rollout and Rust migration remain separate open tasks.
