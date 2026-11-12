#!/usr/bin/env bats

@test "batch blob reads preserve content and reject malformed responses" {
  run python3 tests/git_blob_batch_test.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ran 2 tests"*"OK"* ]]
}

@test "bin receipt uses one real Git batch read" {
  local tmp real_git
  tmp="$(mktemp -d)"
  real_git="$(command -v git)"
  printf '%s\n' '#!/bin/sh' \
    'case "$1:$2" in cat-file:--batch) printf "batch\n" >> "$RECEIPT_GIT_LOG";; show:*) printf "show\n" >> "$RECEIPT_GIT_LOG";; esac' \
    'exec "$RECEIPT_REAL_GIT" "$@"' > "$tmp/git"
  chmod +x "$tmp/git"
  run env PATH="$tmp:$PATH" RECEIPT_REAL_GIT="$real_git" RECEIPT_GIT_LOG="$tmp/log" \
    python3 docs/plans/doctor-source-receipt-check.py --generate-bin-sources
  [ "$status" -eq 0 ]
  [ "$(<"$tmp/log")" = "batch" ]
  printf '%s\n' "$output" > "$tmp/receipt"
  cmp "$tmp/receipt" docs/plans/rust-current-bin-source-receipt.json
  rm "$tmp/git" "$tmp/log" "$tmp/receipt"
  rmdir "$tmp"
}
