#!/usr/bin/env bats
# scripts/inventory-ledger-refresh.sh: commits only the generated ledgers,
# and reruns until the ledgers are current (the review JSON it writes is
# itself pinned by the ledgers).

SCRIPT="$BATS_TEST_DIRNAME/../scripts/inventory-ledger-refresh.sh"

setup() {
  REPO="$BATS_TEST_TMPDIR/repo"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  git init -q "$REPO"
  mkdir -p "$REPO/rust/migration-inventory" "$REPO/docs/plans"
  echo old > "$REPO/rust/migration-inventory/inventory.tsv"
  echo old > "$REPO/rust/migration-inventory/observations.tsv"
  echo old > "$REPO/docs/plans/rust-embedded-discovery-review.json"
  git -C "$REPO" add -A
  git -C "$REPO" -c user.name=t -c user.email=t@example.com commit -qm init
  git -C "$REPO" config user.name t
  git -C "$REPO" config user.email t@example.com
  GEN="$BATS_TEST_TMPDIR/gen"
  export INVENTORY_LEDGER_CMD="$GEN"
}

# fake_generator <body>: --write runs the body; --check passes.
fake_generator() {
  printf '#!/bin/bash\n[ "$1" = --check ] && exit 0\n%s\n' "$1" > "$GEN"
  chmod +x "$GEN"
}

@test "current ledgers make no commit" {
  fake_generator 'true'
  cd "$REPO"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"current after 0 commit(s)"* ]]
  [ "$(git rev-list --count HEAD)" -eq 1 ]
}

@test "the JSON change gets a second round, so the ledgers pin the new blob" {
  # Round 1 rewrites the JSON; round 2 records its new blob in the TSV.
  fake_generator 'f=docs/plans/rust-embedded-discovery-review.json; echo new > "$f"; git rev-parse HEAD:"$f" > rust/migration-inventory/inventory.tsv'
  cd "$REPO"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"current after 2 commit(s)"* ]]
  [ "$(cat rust/migration-inventory/inventory.tsv)" = "$(git rev-parse HEAD:docs/plans/rust-embedded-discovery-review.json)" ]
}

@test "a change to any other file is refused and not committed" {
  fake_generator 'echo x > README.md; echo new > rust/migration-inventory/inventory.tsv'
  cd "$REPO"
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing to commit"*"README.md"* ]]
  [ "$(git rev-list --count HEAD)" -eq 1 ]
}

@test "ledgers that never settle fail after three rounds" {
  fake_generator 'date +%s%N >> rust/migration-inventory/inventory.tsv'
  cd "$REPO"
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"still change after 3 rounds"* ]]
}
