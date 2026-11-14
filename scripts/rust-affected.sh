#!/bin/bash
# Build and test Rust when its source differs from the current base.
set -euo pipefail
base="$(git merge-base HEAD "${BATS_AFFECTED_BASE:-origin/feat/chezmoi}" 2>/dev/null || true)"
if [ -n "$base" ]; then
  changed="$(git diff --name-only "$base" -- rust/; git ls-files --others --exclude-standard -- rust/)"
  if [ -z "$changed" ]; then exit 0; fi
fi
cd rust
../bin/heavy-run cargo test --locked --offline --manifest-path app-priority/Cargo.toml
../bin/heavy-run cargo build --locked --offline --release --manifest-path app-priority/Cargo.toml
