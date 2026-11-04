# Checkup recorder consumer

The next Dotfiles checkup publisher needs to hold the Agentbrew recorder's
read guard while it publishes a checked result. This fixture checks whether
Dotfiles can call that guard in the same process using a pinned public
dependency. It runs on Apple Silicon and stays outside setup and runtime.

## Prediction and checks

Can Dotfiles use the recorder from a clean Cargo cache and repeat the same
test offline? Expect three passing controls per run, zero local checkout
dependencies, and zero runtime entry points. Keep the fixture only if both
runs pass and Cargo resolves the exact revision and preserves the lockfile.
Pivot if acquisition, dependency identity, or a guard check fails. The
measurement follows Goal–Question–Metric (Basili, Caldiera, Rombach, 1994)
and the independent-writer check in [Agentbrew #732](https://github.com/fyodoriv/agentbrew/pull/732).

- A current digest runs the callback once. A replaced record refuses it.
- An independent writer receives `busy` while the callback holds the guard.
  After release the writer succeeds and the fixture reads back its exact record.
- A missing record refuses the callback and creates no state. A separate write
  succeeds afterward.

Run both commands from the repo root. Use an owned build directory and the
same Cargo cache for both commands.

```sh
fixture=tests/fixtures/checkup-read-consumer/Cargo.toml
export CARGO_TARGET_DIR="$(mktemp -d)"
JOBS=1 CARGO_BUILD_JOBS=1 heavy-run cargo test --locked --manifest-path "$fixture" --target aarch64-apple-darwin --test read_guard -- --test-threads=1
JOBS=1 CARGO_BUILD_JOBS=1 heavy-run cargo test --locked --offline --manifest-path "$fixture" --target aarch64-apple-darwin --test read_guard -- --test-threads=1
```

The qualification acquired the public revision from an empty Cargo cache
with no ambient credentials. All three controls passed online and offline
with Rust 1.99.1. The fixture locks the exact merged Agentbrew revision
`d3ed7b9b183e10cd62f9a900e7a03b6f0811540f`. The writer starts as a
separate process, and the record and lock live in a per-test directory.

## Integration boundary

The phase coordinator, rich writer lease, and dashboard publisher must
land together. The publisher must hold both leases in its own process at
the final directory exchange. It must verify the run, record digest, and
sealed exporter outputs before publishing. Check filesystem and installed
behavior separately, and keep all original model checks for
[Agentbrew #572](https://github.com/fyodoriv/agentbrew/issues/572).
