# Verify stripped App Priority artifacts on both Mac architectures

**Hypothesis:** The pinned build can strip debug data without an LLVM loader
warning on Intel and Apple Silicon. The current delivery receipt shows a
loader warning on both, even though the installed artifacts load.

**Measurement:** Dispatch the App Priority fixture workflow with
`delivery_check=true` and `isolated_toolchain=true`. Check the compiler
log, Mach-O load commands, digest, declared macOS target, no-apply exit,
and scratch rollback on each architecture.

**Success:** Both architecture jobs show 0 strip warnings, install 1
digest-verified macOS 13 artifact each, and make 0 live priority changes.

**Pivot:** If 1 architecture still reports a strip warning or cannot load
and roll back the artifact, keep the task open and keep the current build.

**Anchor:** [Pinned build on Intel and Apple Silicon](https://github.com/fyodoriv/dotfiles/actions/runs/45907826150).

The existing offline build and compiler pin are part of the gate.

Use the proxies already installed by pinned Rustup. They add the selected
toolchain's library directory before starting the compiler and its bundled
LLVM tools. Keep the same compiler pin and locked offline Cargo command.
[Rustup 1.29.3 loader setup](https://github.com/rust-lang/rustup/blob/1.29.3/src/toolchain.rs#L157-L226).

## Hosted results (2026-11-27)

Both [baseline jobs](https://github.com/fyodoriv/dotfiles/actions/runs/46061877737)
reproduced the LLVM loader warning under the pinned toolchain. The
[verified candidate](https://github.com/fyodoriv/dotfiles/actions/runs/46071777204)
built both architecture artifacts with macOS target 13.0. Each job reported
zero strip warnings and no DWARF segment. Both passed the digest, no-apply,
rollback, and re-enable checks. The verified tree merged as `83459348`.

The test installs and rollbacks ran in scratch homes on hosted macOS 15.
