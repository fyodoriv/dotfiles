#!/bin/bash
# Regenerate the Rust inventory ledgers and commit them, for the daily
# .github/workflows/inventory-ledger-refresh.yml job. Pushing is left to the
# caller.
#
# The generator reads HEAD, and the embedded review JSON it writes is itself
# a tracked file the ledgers pin. So one pass can leave the ledgers naming
# the old JSON blob. Commit, then run again, until --check passes (at most
# three rounds).
#
# Refuses (exit 1) when a pass changes any file other than the three
# generated ledgers. INVENTORY_LEDGER_CMD overrides the generator (tests).
set -euo pipefail

GENERATOR=${INVENTORY_LEDGER_CMD:-python3 scripts/inventory-ledger.py}
ALLOWED='rust/migration-inventory/inventory.tsv
rust/migration-inventory/observations.tsv
docs/plans/rust-embedded-discovery-review.json'

commits=0
for _round in 1 2 3; do
  $GENERATOR --write
  changed=$(git status --porcelain --untracked-files=all | cut -c4-)
  if [ -z "$changed" ]; then
    $GENERATOR --check
    echo "inventory-ledger-refresh: current after $commits commit(s)"
    exit 0
  fi
  extra=$(printf '%s\n' "$changed" | grep -vxF "$ALLOWED" || true)
  if [ -n "$extra" ]; then
    echo "inventory-ledger-refresh: refusing to commit files other than the ledgers:" >&2
    printf '%s\n' "$extra" >&2
    exit 1
  fi
  printf '%s\n' "$changed" | xargs git add --
  git commit -q -m "chore: refresh the Rust inventory ledgers"
  commits=$((commits + 1))
done
echo "inventory-ledger-refresh: ledgers still change after 3 rounds" >&2
exit 1
