# Compiler queue ownership observation

A process name, priority, working folder or inherited lease marker cannot
prove queue ownership. The owner record's write time also cannot bind a
reused PID to the original process.

## Evidence protocol

Read a bounded companion record from the canonical queue. Bind it to the
queue directory identity, owner, schema and the host boot identity. Each
held reservation needs a nonreused generation and verified controller and
payload birth identities. A ticket is waiting work. A lock without a
qualified companion record leaves ownership unknown. The protocol trusts
the queue controller and does not defend against arbitrary same-user
tampering.

Verify each PID, birth identity and parent link twice in the same queue
view. An owned chain may stop at the verified controller. A claim that
a compiler is outside the queue needs a complete chain to the defined
root and a stable epoch across all normal, legacy, exclusive and fallback
slots. Two identical queue snapshots cannot rule out an intervening
admission. The installed legacy queue does not yet qualify this verdict.

Only emit fixed outcomes and aggregate counts. Keep raw process names,
PIDs, arguments, paths, project names and environment values out of the
report. The observer has no process-control authority.

## Synthetic receipt checks

```sh
heavy-run cargo test --offline --locked --manifest-path tests/fixtures/compiler-queue-observer/Cargo.toml
```

The sealed inputs cover PID reuse, changing epochs, waiting tickets,
partial reads, missing or cyclic ancestry, multiple reservations, and
exclusive and fallback slots. The private marker case must produce an
explicit decision. The receipt oracle accepts only the expected case
IDs and typed outcomes, with no extra fields and empty stderr. It rejects
duplicate keys, wrong verdicts and oversized output.

The fixture checks data and a receipt oracle. It never observes a live
queue, launches a compiler or controls a process. A separate private
Darwin probe confirmed an owned child's OS birth time survived exec.
Live observation still needs a qualified capture wrapper, trusted
reservation records and a coherent queue epoch.

The test-only [oracle harness](compiler-oracle-harness.md) passes each sealed
observation to a trusted in-process callback without its case ID or expected
answer. It checks the callback's bounded response with the existing receipt
oracle. Its positive callback is a harness control, not an observer result.
It does not capture process output or establish live ownership or privacy.

## Admission epoch fixture

Two identical idle snapshots hid one observed admission in a disposable
queue. The ticket sequence advanced for a normal admission. It stayed
unchanged when the launcher admitted work through its ticketless fallback.
An epoch must cover both paths.

A scratch writer published the next epoch after acquiring a slot and before
starting its payload. The normal and ticketless paths each held two active
slots at epoch two. A third payload waited, then observed epoch three. An
unwritable epoch path refused admission before its payload started.

The Rust fixture tests concurrent epoch updates, recovery from the committed
value and refusal of malformed state or an unexpected staging path. It
operates on a disposable directory. It does not install a writer or qualify
the live queue, boot identity, legacy route retirement or filesystem trust.

## Keep and pivot

Require every registered decision, zero false ownership or outside
verdicts, and zero private output. Reject a design that accepts incomplete
evidence. Retain this fixture when adding the actual observer.

Anchor: the existing heavy-run ownership lifecycle and Basili, Caldiera
and Rombach (1994), Goal Question Metric.
