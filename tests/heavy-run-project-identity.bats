#!/usr/bin/env bats

@test "heavy-run: raw and typed project identities preserve admission" {
  run python3 "$BATS_TEST_DIRNAME/helpers/heavy-run-project-interop.py" \
    --candidate "$BATS_TEST_DIRNAME/../bin/heavy-run" \
    --legacy-429 "$BATS_TEST_DIRNAME/fixtures/heavy-run-429" \
    --legacy-430 "$BATS_TEST_DIRNAME/fixtures/heavy-run-430"
  [ "$status" -eq 0 ]
}

@test "heavy-run: duplicate project identities hold admission" {
  run python3 "$BATS_TEST_DIRNAME/helpers/duplicate_identity.py" \
    --candidate "$BATS_TEST_DIRNAME/../bin/heavy-run" \
    --legacy-429 "$BATS_TEST_DIRNAME/fixtures/heavy-run-429" \
    --legacy-430 "$BATS_TEST_DIRNAME/fixtures/heavy-run-430"
  [ "$status" -eq 0 ]
}
