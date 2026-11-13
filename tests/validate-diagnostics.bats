#!/usr/bin/env bats

@test "validator setup shows a failed check's output" {
  local fixture
  fixture="$(mktemp -d)"
  mkdir -p "$fixture/tests" "$fixture/bin"
  cp "$BATS_TEST_DIRNAME/validate.bats" "$fixture/tests/validate.bats"
  printf '#!/bin/bash\nprintf "SYNTHETIC_VALIDATION_FAILURE\\n"\nexit 23\n' > "$fixture/bin/dotfiles-validate"

  run bats -f 'validate --quick exits 0 on clean repo' "$fixture/tests/validate.bats"
  rm -rf "$fixture"

  [ "$status" -ne 0 ]
  [[ "$output" == *SYNTHETIC_VALIDATION_FAILURE* ]]
}
