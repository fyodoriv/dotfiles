# Dry-run record

## Agent-hook source receipt

The isolated source-collection worktree produced a candidate receipt against
the registered pinned tree. The exact command in
[the landed registration](../../plans/agent-hook-source-receipt.md) exited 0:
it checked seven files and 55 selected source anchors and rejected 132 planted
record errors. Independent source review passed. The delivery checkout
repeated the same check, and [PR #511](https://github.com/fyodoriv/dotfiles/pull/511)
merged. This is bounded source evidence, not a deployed-hook or
whole-inventory result.

## Compiler oracle harness

The isolated test-only harness first failed its valid-control assertion with
the unimplemented subject boundary. After implementation, the registered
command in [the harness plan](../../plans/compiler-oracle-harness.md) exited
0: the valid control, all 12 invalid controls, and the retained fixture tests
passed. Its test step was:

```sh
heavy-run cargo test --offline --locked --manifest-path tests/fixtures/compiler-queue-observer/Cargo.toml
```

The sealed inputs and existing oracle hashes matched. The delivery checkout
passed the same command and full repository gate; the harness shipped in
[PR #513](https://github.com/fyodoriv/dotfiles/pull/513). This tests the
harness only; no actual decision model or live observer was qualified.
