#!/usr/bin/env bats

@test "vendored registry sources match the reviewed ownership and identities" {
  run python3 "$BATS_TEST_DIRNAME/../docs/plans/rust-vendor-ownership-review.py" --check
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}
